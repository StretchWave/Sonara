import 'playlist_metadata_provider.dart';
import 'spotify_oembed_provider.dart';
import 'cached_migration_provider.dart';
import 'backend_playlist_provider.dart';
import 'spotify_official_provider.dart';
import '/services/spotify/spotify_api_client.dart';
import '/services/spotify/spotify_source_track.dart';

/// Outcome of the full metadata acquisition pipeline.
class PlaylistMetadataResolution {
  final PlaylistMetadataStatus status;

  /// True when Spotify sign-in would unlock more data (no tracks were
  /// acquired and the official provider asked for auth).
  final bool authenticationRequired;

  final String? playlistId;
  final String? name;
  final String? description;
  final String? artworkUrl;
  final String? owner;
  final List<SpotifySourceTrack> tracks;

  /// Which provider supplied the track list (for the sources UI).
  final String? tracksSource;

  /// Providers that were attempted, in order.
  final List<String> attemptedSources;

  final String? message;

  const PlaylistMetadataResolution({
    required this.status,
    this.authenticationRequired = false,
    this.playlistId,
    this.name,
    this.description,
    this.artworkUrl,
    this.owner,
    this.tracks = const [],
    this.tracksSource,
    this.attemptedSources = const [],
    this.message,
  });
}

/// Tries every available [PlaylistMetadataProvider] in priority order and
/// merges the results:
///
/// * identification (title/artwork) — first provider that has it;
/// * track list — the last provider that *succeeded* (so a fresh official
///   result overrides cached data, while the cache fills in when there is
///   no session);
/// * status — success when tracks exist, partial when only identified,
///   otherwise the most actionable failure.
class PlaylistMetadataResolver {
  final List<PlaylistMetadataProvider> _providers;

  PlaylistMetadataResolver(this._providers);

  /// The standard provider stack: public metadata first, then the local
  /// cache, then the Synora backend (anonymous, server-side resolution),
  /// and finally the app's own Spotify PKCE flow as an optional fallback
  /// for playlists the backend cannot reach.
  factory PlaylistMetadataResolver.defaultFor(SpotifyApiClient apiClient) =>
      PlaylistMetadataResolver([
        SpotifyOEmbedProvider(),
        CachedMigrationProvider(),
        BackendPlaylistProvider(),
        SpotifyOfficialProvider(apiClient),
      ]);

  Future<PlaylistMetadataResolution> resolve(Uri url) async {
    String? playlistId;
    String? name;
    String? description;
    String? artworkUrl;
    String? owner;
    List<SpotifySourceTrack>? tracks;
    String? tracksSource;
    final attempted = <String>[];
    var authenticationRequired = false;
    final failures = <PlaylistMetadataStatus>[];

    for (final provider in _providers) {
      if (!provider.canHandle(url)) continue;
      attempted.add(provider.id);
      final result = await provider.fetchPlaylist(url);
      playlistId ??= result.playlistId;
      name ??= result.name;
      description ??= result.description;
      artworkUrl ??= result.artworkUrl;
      owner ??= result.owner;
      if (result.status == PlaylistMetadataStatus.authenticationRequired) {
        authenticationRequired = true;
      }
      if (result.status != PlaylistMetadataStatus.success &&
          result.status != PlaylistMetadataStatus.partialSuccess) {
        failures.add(result.status);
        continue;
      }
      // A successful provider overrides earlier data: the official API is
      // fresher than the cache; identification fills in title/artwork.
      if (result.status == PlaylistMetadataStatus.success) {
        tracks = result.tracks;
        tracksSource = provider.id;
      }
    }

    // Final status.
    final PlaylistMetadataStatus status;
    String? message;
    if (tracks != null && tracks.isNotEmpty) {
      status = PlaylistMetadataStatus.success;
    } else if (tracks != null) {
      // A provider succeeded but the playlist has no playable items.
      status = PlaylistMetadataStatus.success;
      message = 'This playlist appears to be empty or has no playable tracks';
    } else if (name != null || artworkUrl != null) {
      status = PlaylistMetadataStatus.partialSuccess;
      message = authenticationRequired
          ? 'Playlist identified — its track list is not available automatically'
          : 'Playlist identified — no track list source is available';
    } else if (authenticationRequired) {
      status = PlaylistMetadataStatus.authenticationRequired;
      message = 'Connect Spotify to access this playlist';
    } else {
      // Most actionable failure wins.
      const priority = [
        PlaylistMetadataStatus.permissionDenied,
        PlaylistMetadataStatus.rateLimited,
        PlaylistMetadataStatus.notFound,
        PlaylistMetadataStatus.networkError,
        PlaylistMetadataStatus.unsupported,
      ];
      status = failures.isEmpty
          ? PlaylistMetadataStatus.unsupported
          : priority.firstWhere((s) => failures.contains(s),
              orElse: () => failures.first);
      message = 'Could not acquire this playlist';
    }

    return PlaylistMetadataResolution(
      status: status,
      // Auth is only worth surfacing when no track list was acquired.
      authenticationRequired:
          authenticationRequired && (tracks == null || tracks.isEmpty),
      playlistId: playlistId ?? playlistIdFrom(url),
      name: name,
      description: description,
      artworkUrl: artworkUrl,
      owner: owner,
      tracks: tracks ?? const [],
      tracksSource: tracksSource,
      attemptedSources: attempted,
      message: message,
    );
  }

  static String? playlistIdFrom(Uri url) =>
      SpotifyApiClient.parsePlaylistId(url.toString());
}
