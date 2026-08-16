import 'dart:async';

import 'package:dio/dio.dart';

import 'models.dart';

/// Raised by [SpotifyClient] when the server cannot authenticate with
/// Spotify (no credentials configured, or the app token was rejected).
class SpotifyNotConfigured implements Exception {
  final String message;
  SpotifyNotConfigured([this.message = 'Spotify credentials not configured']);
}

/// Backend-side Spotify client.
///
/// Uses the client-credentials flow: a single app token (SPOTIFY_CLIENT_ID +
/// SPOTIFY_CLIENT_SECRET from the environment) can read any PUBLIC playlist,
/// so the Flutter app's users never need their own Developer App. Tokens are
/// cached and refreshed on expiry/401. Private playlists fail with
/// permission errors that the provider chain maps to structured codes.
class SpotifyClient {
  final Dio _dio;
  final String? _clientId;
  final String? _clientSecret;
  final DateTime Function() _now;

  String? _token;
  DateTime? _tokenExpiry;
  bool _refreshing = false;
  Completer<void>? _refreshCompleter;

  SpotifyClient({
    Dio? dio,
    String? clientId,
    String? clientSecret,
    DateTime Function()? now,
  })  : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.spotify.com/v1',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            )),
        _clientId = clientId,
        _clientSecret = clientSecret,
        _now = now ?? DateTime.now;

  bool get isConfigured => _clientId?.isNotEmpty == true;

  /// Resolves a playlist by id, following pagination. Returns normalized
  /// tracks in playlist order. Throws [ResolveError] for structured
  /// failures and [SpotifyNotConfigured] when no credentials exist.
  Future<List<NormalizedTrack>> fetchPlaylistTracks(String playlistId) async {
    final token = await _ensureToken();
    const fields =
        'tracks(total,next,items(track(id,name,artists(name),album(name,artists(name),release_date,images),duration_ms,track_number,disc_number,explicit,external_ids,uri)))';
    final payload = (await _get('/playlists/$playlistId',
            query: {'fields': fields, 'market': 'from_token'}, token: token))
        .data as Map<String, dynamic>;

    final tracks = <NormalizedTrack>[];
    var total = (payload['tracks']?['total'] as num?)?.toInt() ?? 0;
    var nextUrl = payload['tracks']?['next'] as String?;

    void parseItems(List? items, int start) {
      var position = start;
      for (final raw in items ?? const []) {
        final track = (raw as Map?)?['track'];
        if (track is! Map) {
          // Unavailable/local items come back as null — represent them so
          // the client can show partial results instead of failing.
          tracks.add(NormalizedTrack(
            sourceTrackId: '',
            position: position,
            title: '',
            artists: const [],
            durationMs: 0,
          ));
          position++;
          continue;
        }
        final album = track['album'] as Map?;
        final albumArt = (album?['images'] as List?)
            ?.whereType<Map>()
            .where((i) => i['url'] != null)
            .toList();
        tracks.add(NormalizedTrack(
          sourceTrackId: (track['id'] as String?) ?? '',
          position: position,
          title: (track['name'] as String?) ?? '',
          artists: ((track['artists'] as List?) ?? const [])
              .whereType<Map>()
              .map((a) => (a['name'] as String?) ?? '')
              .where((n) => n.isNotEmpty)
              .toList(),
          album: album?['name'] as String?,
          albumArtist: ((album?['artists'] as List?) ?? const [])
              .whereType<Map>()
              .map((a) => (a['name'] as String?) ?? '')
              .where((n) => n.isNotEmpty)
              .toList()
              .firstOrNull,
          durationMs: (track['duration_ms'] as num?)?.toInt() ?? 0,
          isrc: ((track['external_ids'] as Map?)?['isrc'] as String?),
          releaseDate: track['album']?['release_date'] as String?,
          explicit: (track['explicit'] as bool?) ?? false,
          artworkUrl: albumArt?.isNotEmpty == true
              ? albumArt!.last['url'] as String
              : null,
        ));
        position++;
      }
    }

    parseItems(payload['tracks']?['items'], 0);
    while (nextUrl != null && tracks.length < total && tracks.length < 10000) {
      final page = (await _get(nextUrl, token: token)).data as Map<String, dynamic>;
      parseItems(page['items'] as List?, tracks.length);
      nextUrl = page['next'] as String?;
    }
    return tracks;
  }

  /// Fetches playlist name/description/artwork (cheap, for cache writes).
  Future<Map<String, dynamic>> fetchPlaylistMeta(String playlistId) async {
    final token = await _ensureToken();
    final payload = (await _get('/playlists/$playlistId',
            query: {
              'fields':
                  'id,name,description,images,owner(display_name),tracks(total)'
            },
            token: token))
        .data as Map<String, dynamic>;
    return payload;
  }

  // ---------------------------------------------------------------------
  // Token management
  // ---------------------------------------------------------------------

  Future<String> _ensureToken() async {
    if (_clientId == null || _clientSecret == null) {
      throw SpotifyNotConfigured();
    }
    if (_token != null &&
        _tokenExpiry != null &&
        _now().isBefore(_tokenExpiry!)) {
      return _token!;
    }
    if (_refreshing) {
      await _refreshCompleter!.future;
      return _token!;
    }
    _refreshing = true;
    _refreshCompleter = Completer<void>();
    try {
      final res = await _dio.post(
        'https://accounts.spotify.com/api/token',
        options: Options(contentType: Headers.formUrlEncodedContentType),
        data: {
          'grant_type': 'client_credentials',
          'client_id': _clientId,
          'client_secret': _clientSecret,
        },
      );
      final data = res.data as Map;
      final token = data['access_token'] as String?;
      if (token == null || token.isEmpty) {
        throw const ResolveError(ResolveErrorCode.authenticationRequired,
            'Spotify rejected the server credentials');
      }
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
      _token = token;
      // Refresh slightly early so we never race the boundary.
      _tokenExpiry = _now().add(Duration(seconds: expiresIn - 60));
      return _token!;
    } on DioException catch (e) {
      if (e.response?.statusCode == 400 || e.response?.statusCode == 401) {
        throw const ResolveError(ResolveErrorCode.authenticationRequired,
            'Spotify rejected the server credentials');
      }
      throw const ResolveError(
          ResolveErrorCode.providerUnavailable, 'Could not reach Spotify');
    } finally {
      _refreshing = false;
      _refreshCompleter = null;
    }
  }

  Future<Response> _get(String path,
      {Map<String, dynamic>? query, required String token}) async {
    try {
      return await _dio.get(path,
          queryParameters: query,
          options: Options(headers: {'Authorization': 'Bearer $token'}));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) {
        // App token expired/revoked — clear and let the caller retry once.
        _token = null;
        _tokenExpiry = null;
        throw const ResolveError(ResolveErrorCode.authenticationRequired,
            'Spotify session expired');
      }
      if (status == 403) {
        throw const ResolveError(ResolveErrorCode.permissionDenied,
            'Spotify denied access to this playlist — it may be private');
      }
      if (status == 404) {
        throw const ResolveError(
            ResolveErrorCode.playlistNotFound, 'Playlist not found');
      }
      if (status == 429) {
        throw const ResolveError(ResolveErrorCode.providerRateLimited,
            'Spotify rate limit reached');
      }
      throw const ResolveError(
          ResolveErrorCode.providerUnavailable, 'Spotify request failed');
    }
  }
}
