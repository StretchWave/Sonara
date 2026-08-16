import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import 'spotify_oauth.dart';
import 'spotify_source_track.dart';

/// Raised for any Spotify API failure (404, 403, 429, ...). The status code
/// distinguishes \"not found\" from \"denied access\" from \"rate limited\".
class SpotifyApiException implements Exception {
  final String message;
  final int? statusCode;
  SpotifyApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Result of fetching a Spotify playlist.
class SpotifyPlaylistData {
  final String id;
  final String name;
  final String? description;
  final String? artworkUrl;
  final List<SpotifySourceTrack> tracks;

  const SpotifyPlaylistData({
    required this.id,
    required this.name,
    this.description,
    this.artworkUrl,
    required this.tracks,
  });
}

/// Loopback redirect used by the PKCE flow. Must be registered in the
/// Spotify app's Redirect URIs (http://localhost:<port>/callback).
const String spotifyRedirectUri = 'http://localhost:53178/callback';
const int spotifyCallbackPort = 53178;

/// Thin client for the Spotify Web API.
///
/// Auth uses Authorization Code with PKCE — only the PUBLIC Client ID is
/// stored in the app; there is no client secret anywhere. Tokens are
/// persisted in Hive and refreshed automatically on 401.
class SpotifyApiClient {
  late final Dio _dio;

  SpotifyApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.spotify.com/v1',
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
            ));

  static const String _accountsUrl = 'https://accounts.spotify.com/api/token';
  static const String _prefsClientId = 'spotifyClientId';
  static const String _prefsToken = 'spotifyAccessToken';
  static const String _prefsRefreshToken = 'spotifyRefreshToken';
  static const String _prefsTokenExpiry = 'spotifyTokenExpiry';

  /// True when the user has configured a public Client ID.
  bool get isConfigured {
    final id = Hive.box('AppPrefs').get(_prefsClientId) as String?;
    return id?.isNotEmpty ?? false;
  }

  String? get clientId {
    final id = Hive.box('AppPrefs').get(_prefsClientId) as String?;
    return (id?.isNotEmpty ?? false) ? id : null;
  }

  bool get hasSession {
    final box = Hive.box('AppPrefs');
    final refresh = box.get(_prefsRefreshToken) as String?;
    final access = box.get(_prefsToken) as String?;
    return (refresh != null && refresh.isNotEmpty) ||
        (access != null && access.isNotEmpty);
  }

  /// Stores the public Client ID (no secret involved) and runs the PKCE
  /// sign-in. [openBrowser] launches the authorization URL in the user's
  /// browser; the flow completes when Spotify redirects to the loopback
  /// callback.
  Future<void> connectWithPkce(
    String clientId, {
    required Future<void> Function(Uri url) openBrowser,
  }) async {
    final box = Hive.box('AppPrefs');
    await box.put(_prefsClientId, clientId.trim());

    final state = _randomState();
    final pair = generatePkcePair();
    final authUrl = buildSpotifyAuthorizeUrl(
      clientId: clientId.trim(),
      redirectUri: spotifyRedirectUri,
      codeChallenge: pair.challenge,
      state: state,
    );

    await openBrowser(authUrl);
    final code = await awaitSpotifyCallback(
      port: spotifyCallbackPort,
      state: state,
    );
    await _exchangeCode(code, pair.verifier, clientId.trim());
  }

  Future<void> _exchangeCode(
      String code, String verifier, String clientId) async {
    final res = await _postToken({
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': spotifyRedirectUri,
      'client_id': clientId,
      'code_verifier': verifier,
    });
    await _storeTokenResponse(res, clientId);
  }

  Future<void> _refreshToken() async {
    final box = Hive.box('AppPrefs');
    final clientId = box.get(_prefsClientId) as String? ?? '';
    final refreshToken = box.get(_prefsRefreshToken) as String? ?? '';
    if (clientId.isEmpty || refreshToken.isEmpty) {
      throw SpotifyAuthException('Spotify session expired — sign in again');
    }
    final res = await _postToken({
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': clientId,
    });
    await _storeTokenResponse(res, clientId);
  }

  Future<Map> _postToken(Map<String, String> body) async {
    try {
      final res = await _dio.post(
        _accountsUrl,
        options: Options(contentType: Headers.formUrlEncodedContentType),
        data: body,
      );
      return res.data as Map;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400 || status == 401) {
        throw SpotifyAuthException(
            'Spotify rejected the sign-in — check your Client ID');
      }
      throw SpotifyApiException('Could not reach Spotify: ${e.message}',
          statusCode: status);
    }
  }

  Future<void> _storeTokenResponse(Map data, String clientId) async {
    final token = data['access_token'] as String?;
    final refreshToken = data['refresh_token'] as String?;
    final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 3600;
    if (token == null || token.isEmpty) {
      throw SpotifyAuthException('Spotify returned an invalid token');
    }
    final box = Hive.box('AppPrefs');
    await box.put(_prefsClientId, clientId);
    await box.put(_prefsToken, token);
    await box.put(_prefsTokenExpiry,
        DateTime.now().millisecondsSinceEpoch + (expiresIn - 60) * 1000);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await box.put(_prefsRefreshToken, refreshToken);
    }
  }

  String _randomState() {
    final rng = Random.secure();
    return base64UrlEncode(List<int>.generate(24, (_) => rng.nextInt(256)))
        .replaceAll('=', '');
  }

  /// Fetches a bearer token, refreshing when expired.
  Future<String> _getToken() async {
    final box = Hive.box('AppPrefs');
    final expiry = box.get(_prefsTokenExpiry) as int? ?? 0;
    final cached = box.get(_prefsToken) as String?;
    if (cached != null &&
        cached.isNotEmpty &&
        DateTime.now().millisecondsSinceEpoch < expiry) {
      return cached;
    }
    await _refreshToken();
    return box.get(_prefsToken) as String;
  }

  /// Signs out locally (tokens are deleted; the browser session remains).
  Future<void> disconnect() async {
    final box = Hive.box('AppPrefs');
    await box.delete(_prefsToken);
    await box.delete(_prefsRefreshToken);
    await box.delete(_prefsTokenExpiry);
  }

  /// Extracts a playlist id from a Spotify URL, URI or bare id.
  ///
  /// Rejects non-playlist Spotify URLs (album/track/artist pages) and
  /// malformed input — a useful error is shown before any network call.
  static String? parsePlaylistId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    // spotify:playlist:<id>
    final uriMatch = RegExp(r'^spotify:playlist:([A-Za-z0-9]{22})$')
        .firstMatch(trimmed);
    if (uriMatch != null) return uriMatch.group(1);
    // https://open.spotify.com/playlist/<id>?si=... — the path segment must
    // be "playlist"; album/track/artist pages are rejected.
    final urlMatch = RegExp(
            r'^https?://(?:open\.spotify\.com|play\.spotify\.com|spotify\.link)/'
            r'(?:intl-[a-z-]+/)?playlist/([A-Za-z0-9]{22})(?:[/?].*)?$')
        .firstMatch(trimmed);
    if (urlMatch != null) return urlMatch.group(1);
    if (RegExp(r'^(?:https?://)?(?:open\.spotify\.com|play\.spotify\.com)/'
            r'(?:intl-[a-z-]+/)?(?:album|track|artist|episode|show)/')
        .hasMatch(trimmed)) {
      // A valid Spotify URL that is not a playlist — return null so the
      // caller can say "this is not a playlist link".
      return null;
    }
    // Bare 22-char id.
    if (RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(trimmed)) return trimmed;
    return null;
  }

  /// Describes why a URL is not a valid playlist link (for the error UI).
  static String? invalidPlaylistReason(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return 'Enter a Spotify playlist URL or ID';
    if (parsePlaylistId(trimmed) != null) return null;
    if (RegExp(r'^https?://').hasMatch(trimmed) ||
        trimmed.startsWith('spotify:')) {
      if (RegExp(r'(?:album|track|artist|episode|show)/').hasMatch(trimmed)) {
        return 'That is a Spotify ${RegExp(r'(?:album|track|artist|episode|show)').firstMatch(trimmed)!.group(0)} link — paste a playlist link instead';
      }
      return 'That does not look like a Spotify playlist link';
    }
    return 'That does not look like a Spotify playlist URL or ID';
  }

  /// GET with a bearer token; refreshes the token once on 401 and retries.
  Future<Response> _getWithAuth(String path, {Map<String, dynamic>? query}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await _getToken();
      try {
        return await _dio.get(
          path,
          queryParameters: query,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      } on DioException catch (e) {
        if (e.response?.statusCode == 401 && attempt == 0) {
          await _refreshToken();
          continue;
        }
        throw _mapDioError(e);
      }
    }
    throw SpotifyApiException('Spotify request failed', statusCode: 401);
  }

  /// Fetches playlist metadata and every track, following pagination.
  /// Distinguishes auth failures, denied access, not found and rate limits.
  Future<SpotifyPlaylistData> fetchPlaylist(String playlistId) async {
    const fields =
        'name,description,images,external_urls,tracks(total,next,items(track(id,name,artists(name),album(name,artists(name),release_date,images),duration_ms,track_number,disc_number,explicit,external_ids,uri)))';

    final payload = (await _getWithAuth('/playlists/$playlistId',
            query: {'fields': fields, 'market': 'from_token'}))
        .data as Map<String, dynamic>;

    final tracks = <SpotifySourceTrack>[];
    var total = (payload['tracks']?['total'] as num?)?.toInt() ?? 0;
    var nextUrl = payload['tracks']?['next'] as String?;

    void parseItems(List? items) {
      for (final raw in items ?? const []) {
        final track = (raw as Map?)?['track'];
        if (track is! Map) {
          // Unavailable/local tracks come back as null — represented
          // separately so they never crash the migration.
          tracks.add(const SpotifySourceTrack(
            spotifyId: '',
            title: '',
            artists: [],
          ));
          continue;
        }
        final album = track['album'] as Map?;
        final albumArt = (album?['images'] as List?)
            ?.whereType<Map>()
            .where((i) => i['url'] != null)
            .toList();
        final releaseDate = track['album']?['release_date'] as String?;
        tracks.add(SpotifySourceTrack(
          spotifyId: (track['id'] as String?) ?? '',
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
          releaseDate:
              releaseDate != null ? DateTime.tryParse(releaseDate) : null,
          explicit: (track['explicit'] as bool?) ?? false,
          trackNumber: (track['track_number'] as num?)?.toInt(),
          artworkUrl: albumArt?.isNotEmpty == true
              ? albumArt!.last['url'] as String
              : null,
        ));
      }
    }

    parseItems(payload['tracks']?['items']);

    // Follow pagination (max 100 per page) with a safety cap.
    while (nextUrl != null && tracks.length < total && tracks.length < 10000) {
      final page = (await _getWithAuth(nextUrl)).data as Map<String, dynamic>;
      parseItems(page['items'] as List?);
      nextUrl = page['next'] as String?;
    }

    return SpotifyPlaylistData(
      id: playlistId,
      name: (payload['name'] as String?) ?? 'Spotify Playlist',
      description: payload['description'] as String?,
      artworkUrl: ((payload['images'] as List?) ?? const [])
          .whereType<Map>()
          .where((i) => i['url'] != null)
          .toList()
          .isEmpty
          ? null
          : ((payload['images'] as List).last as Map)['url'] as String,
      tracks: tracks,
    );
  }

  Exception _mapDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401) {
      // Token expired or revoked — refresh once and retry.
      return SpotifyAuthException('Spotify session expired — sign in again');
    }
    if (status == 403) {
      return SpotifyApiException(
          'Spotify denied access to this playlist — it may be private or '
          'owned by another account',
          statusCode: status);
    }
    if (status == 404) {
      return SpotifyApiException(
          'Playlist not found — it may have been deleted or the ID is wrong',
          statusCode: status);
    }
    if (status == 429) {
      return SpotifyApiException(
          'Spotify rate limit reached — wait a moment and try again',
          statusCode: status);
    }
    return SpotifyApiException(
        'Spotify request failed: ${e.message}', statusCode: status);
  }
}
