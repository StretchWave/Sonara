import 'playlist_metadata_provider.dart';
import '/services/spotify/spotify_api_client.dart';
import '/services/spotify/spotify_oauth.dart';

/// Official Spotify Web API provider.
///
/// Wraps the existing PKCE-authenticated [SpotifyApiClient]. This is an
/// optional fallback: when the user has no session it reports
/// [PlaylistMetadataStatus.authenticationRequired] instead of blocking the
/// whole import, so other sources (public metadata, cache) can proceed.
class SpotifyOfficialProvider implements PlaylistMetadataProvider {
  final SpotifyApiClient _apiClient;

  SpotifyOfficialProvider(this._apiClient);

  @override
  String get id => 'spotify-official';

  @override
  String get displayName => 'Spotify account';

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
    if (!_apiClient.hasSession) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.authenticationRequired,
        playlistId: playlistId,
        message: 'Connect Spotify to access additional playlist data',
      );
    }
    try {
      final data = await _apiClient.fetchPlaylist(playlistId);
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.success,
        playlistId: data.id,
        name: data.name,
        description: data.description,
        artworkUrl: data.artworkUrl,
        tracks: data.tracks,
      );
    } on SpotifyAuthException catch (e) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.authenticationRequired,
        playlistId: playlistId,
        message: e.message,
      );
    } on SpotifyApiException catch (e) {
      final status = switch (e.statusCode) {
        403 => PlaylistMetadataStatus.permissionDenied,
        404 => PlaylistMetadataStatus.notFound,
        429 => PlaylistMetadataStatus.rateLimited,
        _ => PlaylistMetadataStatus.networkError,
      };
      return PlaylistMetadataResult(
        status: status,
        playlistId: playlistId,
        message: e.message,
      );
    } catch (e) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.networkError,
        playlistId: playlistId,
        message: e.toString(),
      );
    }
  }
}
