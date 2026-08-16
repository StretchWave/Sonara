import 'dart:io';

import '../apify_client.dart';
import '../apify_normalizer.dart';
import '../models.dart';
import 'playlist_provider.dart';

/// Resolves Spotify playlists through an Apify scraper actor.
///
/// This provider owns every bit of Apify-specific behavior: the actor id,
/// input shape, polling, and normalization. The resolver chain (and the
/// Flutter app) only ever see the generic [PlaylistResolution].
///
/// No credentials ever leave the backend; the token is injected via
/// environment (APIFY_API_TOKEN) and only sent to api.apify.com.
class ApifyPlaylistProvider implements PlaylistMetadataProvider {
  final ApifyClient client;
  final void Function(String message) _log;

  ApifyPlaylistProvider(this.client, {void Function(String message)? log})
      : _log = log ?? ((m) => stdout.writeln('[apify-provider] $m'));

  @override
  String get id => 'apify';

  @override
  bool canResolve(PlaylistResolveInput input) => client.isConfigured;

  @override
  Future<PlaylistResolution> resolve(PlaylistResolveInput input) async {
    final settings = client.settings;
    _log('Apify run started for playlist ${input.playlistId}');

    final items = await client.runActor(settings.actorId!,
        settings.buildInput(input.url));

    _log('Apify run completed for ${input.playlistId}: '
        '${items.length} raw rows');

    final normalized = <NormalizedTrack>[];
    for (var i = 0; i < items.length; i++) {
      final track = normalizeApifyTrack(items[i], i);
      // Unavailable placeholder rows (no title and no id) still count
      // toward the playlist but are reported as unavailable.
      normalized.add(track);
    }

    if (normalized.isEmpty) {
      throw const ResolveError(ResolveErrorCode.playlistEmpty,
          'The scraper returned no tracks for this playlist');
    }

    // Position-aware ordering + deduplication (ISRC > spotify id > url >
    // normalized title+artist+album). Keeps the first occurrence.
    final ordered = _dedupe(
        normalized..sort((a, b) => a.position.compareTo(b.position)));

    final available = ordered
        .where((t) => t.title.isNotEmpty && t.sourceTrackId.isNotEmpty)
        .toList();
    final unavailable = ordered.length - available.length;

    var playlist = playlistMetaFromItems(items, input.playlistId);
    if (playlist.trackCount <= 0) {
      playlist = NormalizedPlaylist(
        id: playlist.id,
        name: playlist.name,
        description: playlist.description,
        artworkUrl: playlist.artworkUrl,
        trackCount: ordered.length,
      );
    }

    _log('Apify resolved ${input.playlistId}: '
        '${available.length} tracks ($unavailable unavailable)');

    if (available.isEmpty) {
      throw const ResolveError(ResolveErrorCode.playlistEmpty,
          'No usable tracks were found in this playlist');
    }

    return PlaylistResolution(
      playlist: playlist,
      tracks: available,
      source: 'apify',
      method: 'actor',
      total: ordered.length,
      resolved: available.length,
      unavailable: unavailable,
      warnings: unavailable > 0
          ? [
              ResolveWarning('PARTIAL_PLAYLIST',
                  '$unavailable tracks could not be resolved.')
            ]
          : const [],
    );
  }

  /// Deduplicates by priority: ISRC > spotify id > spotify url >
  /// normalized artist+title+album. Later occurrences of the same song are
  /// dropped so an imported playlist does not contain doubles.
  List<NormalizedTrack> _dedupe(List<NormalizedTrack> tracks) {
    final seen = <String>{};
    final result = <NormalizedTrack>[];
    for (final track in tracks) {
      final key = _dedupeKey(track);
      if (key != null) {
        if (seen.contains(key)) continue;
        seen.add(key);
      }
      result.add(track);
    }
    return result;
  }

  String? _dedupeKey(NormalizedTrack track) {
    final isrc = track.isrc?.trim().toUpperCase();
    if (isrc != null && isrc.isNotEmpty) return 'isrc:$isrc';
    if (track.sourceTrackId.isNotEmpty) {
      return 'spotify:${track.sourceTrackId}';
    }
    final url = _trackUrlOf(track);
    if (url != null) return 'url:$url';
    final title = track.title.trim().toLowerCase();
    final artist = (track.artists.firstOrNull ?? '').trim().toLowerCase();
    if (title.isNotEmpty && artist.isNotEmpty) {
      return 'name:$artist|$title|${track.album?.trim().toLowerCase() ?? ''}';
    }
    return null;
  }

  String? _trackUrlOf(NormalizedTrack track) {
    // The normalized model keeps the spotify id; rebuild the url only for
    // dedupe purposes when present.
    return track.sourceTrackId.isNotEmpty
        ? 'https://open.spotify.com/track/${track.sourceTrackId}'
        : null;
  }
}
