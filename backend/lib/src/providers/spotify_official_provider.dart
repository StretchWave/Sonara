import '../models.dart';
import '../spotify_client.dart';
import 'playlist_provider.dart';

/// Resolves playlists through the Spotify Web API using the server's own
/// client-credentials token. Public playlists work with zero user
/// involvement; private playlists raise permission errors that the chain
/// maps to structured codes (the Flutter app's PKCE flow remains the
/// fallback for those).
class SpotifyOfficialProvider implements PlaylistMetadataProvider {
  final SpotifyClient _client;

  SpotifyOfficialProvider(this._client);

  @override
  String get id => 'spotify';

  @override
  bool canResolve(PlaylistResolveInput input) => _client.isConfigured;

  @override
  Future<PlaylistResolution> resolve(PlaylistResolveInput input) async {
    final tracks = await _client.fetchPlaylistTracks(input.playlistId);
    final meta = await _client.fetchPlaylistMeta(input.playlistId);
    final images = (meta['images'] as List?) ?? const [];
    final artworkUrl = images.isEmpty
        ? null
        : (images.last as Map)['url'] as String?;
    final total = (meta['tracks']?['total'] as num?)?.toInt() ??
        tracks.length;

    final resolved = tracks.where((t) => t.sourceTrackId.isNotEmpty).length;
    final unavailable = tracks.length - resolved;
    return PlaylistResolution(
      playlist: NormalizedPlaylist(
        id: input.playlistId,
        name: (meta['name'] as String?) ?? 'Spotify Playlist',
        description: meta['description'] as String?,
        artworkUrl: artworkUrl,
        trackCount: total,
      ),
      tracks: tracks,
      source: 'spotify',
      method: 'official_api',
      total: total,
      resolved: resolved,
      unavailable: unavailable,
      warnings: unavailable > 0
          ? [
              ResolveWarning(
                  'PARTIAL_PLAYLIST',
                  '$unavailable track${unavailable == 1 ? '' : 's'} could '
                      'not be resolved.'),
            ]
          : const [],
    );
  }
}
