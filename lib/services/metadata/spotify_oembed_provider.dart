import 'package:dio/dio.dart';

import 'playlist_metadata_provider.dart';
import '/services/spotify/spotify_api_client.dart';

/// Public metadata for a Spotify playlist — no authentication required.
///
/// Uses Spotify's oEmbed endpoint, which returns the playlist title and
/// artwork for any public playlist. It deliberately does NOT return the
/// track list; this provider exists so the app can identify a playlist
/// before (and without) any Spotify sign-in.
class SpotifyOEmbedProvider implements PlaylistMetadataProvider {
  final Dio _dio;

  SpotifyOEmbedProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://open.spotify.com',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'User-Agent':
                    'HarmonyMusic/2.0 (https://github.com/anandnet/Harmony-Music)',
              },
            ));

  @override
  String get id => 'oembed';

  @override
  String get displayName => 'Public metadata';

  @override
  bool canHandle(Uri url) => SpotifyApiClient.parsePlaylistId(url.toString()) != null;

  @override
  Future<PlaylistMetadataResult> fetchPlaylist(Uri url) async {
    final playlistId = SpotifyApiClient.parsePlaylistId(url.toString());
    if (playlistId == null) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.unsupported,
        message: SpotifyApiClient.invalidPlaylistReason(url.toString()),
      );
    }
    try {
      final res = await _dio.get('/oembed', queryParameters: {
        'url': 'https://open.spotify.com/playlist/$playlistId',
      });
      final data = res.data as Map? ?? const {};
      final title = data['title'] as String?;
      final thumbnail = data['thumbnail_url'] as String?;
      if (title == null && thumbnail == null) {
        return PlaylistMetadataResult(
          status: PlaylistMetadataStatus.notFound,
          playlistId: playlistId,
          message: 'Playlist not found',
        );
      }
      // Identified, but the track list requires another source.
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.partialSuccess,
        playlistId: playlistId,
        name: title,
        artworkUrl: thumbnail,
        message: 'Playlist identified — track list requires another source',
      );
    } on DioException catch (e) {
      return _mapError(playlistId, e);
    } catch (e) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.networkError,
        playlistId: playlistId,
        message: e.toString(),
      );
    }
  }

  PlaylistMetadataResult _mapError(String playlistId, DioException e) {
    final status = e.response?.statusCode;
    if (status == 404) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.notFound,
        playlistId: playlistId,
        message: 'Playlist not found — it may have been deleted',
      );
    }
    if (status == 429) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.rateLimited,
        playlistId: playlistId,
        message: 'Rate limited — wait a moment and try again',
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.networkError,
        playlistId: playlistId,
        message: 'Could not reach Spotify: ${e.message}',
      );
    }
    return PlaylistMetadataResult(
      status: PlaylistMetadataStatus.networkError,
      playlistId: playlistId,
      message: 'Public metadata request failed: ${e.message}',
    );
  }
}
