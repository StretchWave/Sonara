import 'dart:io';

import '../models.dart';
import '../public_spotify_client.dart';
import 'playlist_provider.dart';

/// Resolves public Spotify playlists **without any credentials** through the
/// anonymous web-player channel (embed page token + partner GraphQL).
///
/// This is the provider that makes paste-a-URL imports work with zero user
/// setup. It sits behind the same [PlaylistMetadataProvider] interface as
/// the Apify scraper and the official API, so it can be swapped or dropped
/// without touching the resolver chain or the Flutter app.
class PublicSpotifyProvider implements PlaylistMetadataProvider {
  final PublicSpotifyClient client;
  final void Function(String message) _log;

  PublicSpotifyProvider(this.client, {void Function(String message)? log})
      : _log = log ?? ((m) => stdout.writeln('[public-spotify] $m'));

  @override
  String get id => 'public-spotify';

  @override
  bool canResolve(PlaylistResolveInput input) => true;

  @override
  Future<PlaylistResolution> resolve(PlaylistResolveInput input) async {
    _log('Fetching playlist ${input.playlistId} anonymously');
    final page = await client.fetchPlaylist(input.playlistId);

    if (page.rawItems.isEmpty) {
      throw const ResolveError(ResolveErrorCode.playlistNotFound,
          'The playlist could not be found or has no public tracks');
    }

    // Collect track uris from the enumerated items (paged already).
    final uris = <String>[];
    for (final item in page.rawItems) {
      final uri = _trackUri(item);
      if (uri != null && !uris.contains(uri)) uris.add(uri);
    }
    if (uris.isEmpty) {
      throw const ResolveError(ResolveErrorCode.playlistEmpty,
          'The playlist contains no playable tracks');
    }

    _log('Playlist ${input.playlistId}: ${page.totalCount} tracks, '
        '${uris.length} unique uris; hydrating metadata');
    final token = await client.ensureToken(input.playlistId);
    final trackData = await client.fetchTrackMetadata(token, uris);

    // Index hydrated metadata by uri so items keep their playlist order.
    final byUri = <String, Map<String, dynamic>>{};
    for (final t in trackData) {
      final u = t['uri'] as String?;
      if (u != null) byUri[u] = t;
    }

    final tracks = <NormalizedTrack>[];
    var position = 0;
    for (final item in page.rawItems) {
      final uri = _trackUri(item);
      if (uri == null) continue;
      final raw = byUri[uri];
      if (raw == null) {
        // Hydration failed for this track — keep a placeholder so the
        // count/order stays intact (counted as unavailable).
        tracks.add(NormalizedTrack(
          sourceTrackId: _idFromUri(uri),
          position: position++,
          title: '',
          artists: const [],
          durationMs: _durationFromItem(item),
        ));
        continue;
      }
      tracks.add(_normalize(raw, position++, _durationFromItem(item)));
    }

    final available =
        tracks.where((t) => t.title.isNotEmpty && t.sourceTrackId.isNotEmpty).toList();
    final unavailable = tracks.length - available.length;

    if (available.isEmpty) {
      throw const ResolveError(ResolveErrorCode.playlistEmpty,
          'No usable tracks were found in this playlist');
    }

    return PlaylistResolution(
      playlist: NormalizedPlaylist(
        id: input.playlistId,
        name: page.name ?? 'Spotify Playlist',
        description: page.description,
        artworkUrl: page.artworkUrl,
        trackCount: page.totalCount,
      ),
      tracks: available,
      source: 'spotify',
      method: 'anonymous_graphql',
      total: tracks.length,
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

  NormalizedTrack _normalize(
      Map<String, dynamic> raw, int position, int fallbackDurationMs) {
    final uri = raw['uri'] as String? ?? '';
    final duration = raw['duration'] as Map?;
    final durationMs = ((duration?['totalMilliseconds'] as num?)?.toInt()) ??
        fallbackDurationMs;
    final album = raw['albumOfTrack'] as Map?;
    final albumName = album?['name'] as String?;
    final albumArt = _albumArt(album?['coverArt']);
    final artistsRaw = ((raw['artists'] as Map?)?['items'] as List?) ?? const [];
    final artists = <String>[];
    for (final a in artistsRaw.whereType<Map>()) {
      final profile = (a['profile'] as Map?) ?? const {};
      final name = profile['name'] as String?;
      if (name != null && name.trim().isNotEmpty && !artists.contains(name)) {
        artists.add(name);
      }
    }
    final rating = raw['contentRating'] as Map?;
    final explicit = rating?['label'] == 'EXPLICIT';
    final title = (raw['name'] as String?)?.trim() ?? '';

    return NormalizedTrack(
      sourceTrackId: _idFromUri(uri),
      position: position,
      title: title.length > 500 ? title.substring(0, 500) : title,
      artists: artists,
      album: albumName,
      durationMs: durationMs.clamp(0, 86400000),
      explicit: explicit,
      artworkUrl: albumArt ?? _albumArtUrl(album),
    );
  }

  String? _albumArtUrl(Map? album) => _albumArt(album?['coverArt']);

  String? _albumArt(dynamic coverArt) {
    if (coverArt is! Map) return null;
    final sources = coverArt['sources'];
    if (sources is List && sources.isNotEmpty) {
      // Prefer the largest source.
      final largest = sources.whereType<Map>().reduce((a, b) {
        final aw = (a['width'] as num?)?.toInt() ?? 0;
        final bw = (b['width'] as num?)?.toInt() ?? 0;
        return aw >= bw ? a : b;
      });
      final url = largest['url'];
      if (url is String) return url;
    }
    return null;
  }

  String? _trackUri(Map<String, dynamic> item) {
    final itemV2 = item['itemV2'] as Map?;
    final data = itemV2?['data'] as Map?;
    final uri = data?['uri'];
    if (uri is String && uri.startsWith('spotify:track:')) return uri;
    // Some items are podcasts/ads — not playable tracks.
    return null;
  }

  int _durationFromItem(Map<String, dynamic> item) {
    final itemV2 = item['itemV2'] as Map?;
    final data = itemV2?['data'] as Map?;
    final duration = data?['trackDuration'] as Map?;
    return ((duration?['totalMilliseconds'] as num?)?.toInt()) ?? 0;
  }

  String _idFromUri(String uri) => uri.startsWith('spotify:track:')
      ? uri.substring('spotify:track:'.length)
      : uri;
}
