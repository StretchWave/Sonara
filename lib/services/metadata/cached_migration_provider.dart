import 'package:hive/hive.dart';

import 'playlist_metadata_provider.dart';
import '/services/spotify/playlist_migration_item.dart';
import '/services/spotify/spotify_api_client.dart';

/// Serves a previously imported playlist straight from the local migration
/// cache — no network, no authentication. This is what makes repeated
/// imports instant and offline-friendly.
class CachedMigrationProvider implements PlaylistMetadataProvider {
  CachedMigrationProvider();

  @override
  String get id => 'cached';

  @override
  String get displayName => 'Cached mappings';

  @override
  bool canHandle(Uri url) =>
      SpotifyApiClient.parsePlaylistId(url.toString()) != null;

  @override
  Future<PlaylistMetadataResult> fetchPlaylist(Uri url) async {
    final playlistId = SpotifyApiClient.parsePlaylistId(url.toString());
    if (playlistId == null) {
      return const PlaylistMetadataResult(
        status: PlaylistMetadataStatus.unsupported,
      );
    }
    final box = await Hive.openBox('SpotifyMigrations');
    try {
      final stored = box.get(playlistId);
      if (stored is! Map) {
        return PlaylistMetadataResult(
          status: PlaylistMetadataStatus.notFound,
          playlistId: playlistId,
          message: 'No cached import for this playlist',
        );
      }
      final items = ((stored['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => PlaylistMigrationItem.fromJson(e))
          .toList();
      final tracks = items
          .map((item) => item.sourceTrack)
          .where((t) => t.spotifyId.isNotEmpty)
          .toList();
      return PlaylistMetadataResult(
        status: tracks.isEmpty
            ? PlaylistMetadataStatus.partialSuccess
            : PlaylistMetadataStatus.success,
        playlistId: playlistId,
        name: stored['name'] as String?,
        tracks: tracks,
        message: tracks.isEmpty ? null : 'Loaded from a previous import',
      );
    } finally {
      await box.close();
    }
  }
}
