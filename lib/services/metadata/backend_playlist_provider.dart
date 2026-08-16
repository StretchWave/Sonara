import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import 'playlist_metadata_provider.dart';
import '/services/spotify/spotify_api_client.dart';
import '/services/spotify/spotify_source_track.dart';

/// Resolves playlists through the Sonara backend resolver.
///
/// The backend holds any Spotify/third-party credentials server-side and
/// returns normalized, provider-agnostic metadata — the app never learns
/// (or needs to care) which source produced the data.
///
/// The backend URL is resolved at runtime, in this order:
///
/// 1. an explicit [BackendPlaylistProvider] constructor `baseUrl` (tests);
/// 2. `--dart-define=BACKEND_URL=...` (production builds);
/// 3. the `sonaraBackendUrl` value in Hive `AppPrefs` (in-app override);
/// 4. [defaultBackendUrl] — a built-in default so IDE `flutter run` builds
///    (which often drop dart-defines) still reach the local resolver.
///
/// This makes the backend reachable on every launch path — compiled exe,
/// IDE run, or a define-less kernel — so a missing dart-define can never
/// silently disable playlist resolution again.
class BackendPlaylistProvider implements PlaylistMetadataProvider {
  /// Set via `--dart-define=BACKEND_URL=...` (production deployments).
  static const String configuredUrl = String.fromEnvironment('BACKEND_URL');

  /// Built-in default pointing at the local Sonara resolver.
  static const String defaultBackendUrl = 'http://localhost:34567';

  /// Hive `AppPrefs` key for the runtime backend URL override.
  static const String prefsBackendUrl = 'sonaraBackendUrl';

  /// Applies the resolution order above; an explicit [override] wins
  /// (an empty string disables the provider, as in tests).
  static String resolveBackendUrl({String? override}) {
    if (override != null) return override;
    if (configuredUrl.trim().isNotEmpty) return configuredUrl.trim();
    if (Hive.isBoxOpen('AppPrefs')) {
      final saved = Hive.box('AppPrefs').get(prefsBackendUrl) as String?;
      if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    }
    return defaultBackendUrl;
  }

  /// True when a backend URL is available. Always true unless the provider
  /// was explicitly constructed with an empty base URL.
  static bool get isConfigured => resolveBackendUrl().isNotEmpty;

  /// Persists a runtime backend URL override; an empty [url] clears it.
  static Future<void> setBackendUrl(String url) async {
    final box = Hive.box('AppPrefs');
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      await box.delete(prefsBackendUrl);
    } else {
      await box.put(prefsBackendUrl, trimmed);
    }
  }

  /// Instance base URL (see [resolveBackendUrl]).
  final String _baseUrl;
  final Dio _dio;

  BackendPlaylistProvider({Dio? dio, String? baseUrl})
      : _baseUrl = resolveBackendUrl(override: baseUrl),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: resolveBackendUrl(override: baseUrl),
              connectTimeout: const Duration(seconds: 25),
              receiveTimeout: const Duration(seconds: 35),
              headers: {
                'User-Agent':
                    'Sonara/2.0 (https://github.com/anandnet/Harmony-Music)',
              },
            ));

  /// The effective backend base URL this provider talks to.
  String get baseUrl => _baseUrl;

  @override
  String get id => 'sonara-backend';

  @override
  String get displayName => 'Sonara backend';

  @override
  bool canHandle(Uri url) =>
      _baseUrl.trim().isNotEmpty &&
      SpotifyApiClient.parsePlaylistId(url.toString()) != null;

  @override
  Future<PlaylistMetadataResult> fetchPlaylist(Uri url) async {
    final playlistId = SpotifyApiClient.parsePlaylistId(url.toString());
    if (playlistId == null) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.unsupported,
        message: SpotifyApiClient.invalidPlaylistReason(url.toString()),
      );
    }
    if (_baseUrl.trim().isEmpty) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.networkError,
        playlistId: playlistId,
        message: 'Resolver backend is not configured',
      );
    }
    try {
      final res = await _dio.post(
        '/api/playlist/resolve',
        data: {'url': url.toString()},
      );
      final data = res.data;
      if (data is Map && data['success'] == true) {
        final playlist = (data['playlist'] as Map?) ?? const {};
        final tracks = ((data['tracks'] as List?) ?? const [])
            .whereType<Map>()
            .map(_mapTrack)
            .toList();
        return PlaylistMetadataResult(
          status: PlaylistMetadataStatus.success,
          playlistId: playlistId,
          name: playlist['name'] as String?,
          description: playlist['description'] as String?,
          artworkUrl: playlist['artworkUrl'] as String?,
          tracks: tracks,
          message: (data['source'] as Map?)?['provider'] as String?,
        );
      }
      // Unexpected successful response — treat as a provider failure.
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.networkError,
        playlistId: playlistId,
        message: 'The resolver backend returned an unexpected response',
      );
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map && body['error'] is Map) {
        final err = body['error'] as Map;
        return _mapError(
          playlistId,
          err['code'] as String?,
          err['message'] as String?,
          e.response?.statusCode,
        );
      }
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.networkError,
        playlistId: playlistId,
        message: 'Could not reach the resolver backend: ${e.message}',
      );
    } catch (e) {
      return PlaylistMetadataResult(
        status: PlaylistMetadataStatus.networkError,
        playlistId: playlistId,
        message: e.toString(),
      );
    }
  }

  SpotifySourceTrack _mapTrack(Map raw) {
    final album = raw['album'] as String?;
    final albumArtist = raw['albumArtist'] as String?;
    final releaseDate = raw['releaseDate'] as String?;
    final artwork = raw['artworkUrl'] as String?;
    return SpotifySourceTrack(
      spotifyId: (raw['sourceTrackId'] as String?) ?? '',
      title: (raw['title'] as String?) ?? '',
      artists: ((raw['artists'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      album: album,
      albumArtist: albumArtist,
      durationMs: (raw['durationMs'] as num?)?.toInt() ?? 0,
      isrc: raw['isrc'] as String?,
      releaseDate: releaseDate != null ? DateTime.tryParse(releaseDate) : null,
      explicit: raw['explicit'] as bool? ?? false,
      artworkUrl: artwork,
    );
  }

  PlaylistMetadataResult _mapError(
      String playlistId, String? code, String? message, int? httpStatus) {
    final status = switch (code) {
      'INVALID_URL' || 'UNSUPPORTED_SPOTIFY_URL' =>
        PlaylistMetadataStatus.unsupported,
      'PLAYLIST_NOT_FOUND' => PlaylistMetadataStatus.notFound,
      'PLAYLIST_PRIVATE' || 'PERMISSION_DENIED' =>
        PlaylistMetadataStatus.permissionDenied,
      'AUTHENTICATION_REQUIRED' => PlaylistMetadataStatus.authenticationRequired,
      'PROVIDER_RATE_LIMITED' => PlaylistMetadataStatus.rateLimited,
      _ => PlaylistMetadataStatus.networkError,
    };
    return PlaylistMetadataResult(
      status: status,
      playlistId: playlistId,
      message: message ?? 'The resolver backend could not fetch this playlist',
    );
  }
}
