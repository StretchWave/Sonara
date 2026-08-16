import 'dart:io';

import 'package:dio/dio.dart';

import 'models.dart';

/// A fetched anonymous token plus its wall-clock expiry (ms epoch).
class AnonymousToken {
  final String token;
  final int expiresAtMs;
  AnonymousToken(this.token, this.expiresAtMs);
  bool get isExpired => DateTime.now().millisecondsSinceEpoch >= expiresAtMs;
}

/// Public, credential-free access to Spotify playlist data.
///
/// Bootstrap: the open.spotify.com **embed** page for a playlist embeds an
/// anonymous web-player access token (with an expiry) plus the web client
/// id. That token is used against Spotify's own partner GraphQL
/// (pathfinder) API to enumerate the playlist and fetch full track
/// metadata. No Client ID, secret, or OAuth is involved — this is the same
/// anonymous path the Spotify web player itself uses before sign-in.
///
/// This is inherently a best-effort channel: Spotify may change the embed
/// page shape or block anonymous tokens at any time. Every failure is
/// reported as a structured [ResolveError] so the resolver chain can fall
/// through to the next provider (Apify scraper, official API, app PKCE).
class PublicSpotifyClient {
  final Dio _dio;
  final void Function(String message) _log;

  PublicSpotifyClient({Dio? dio, void Function(String message)? log})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api-partner.spotify.com',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            )),
        _log = log ?? ((m) => stdout.writeln('[public-spotify] $m'));

  AnonymousToken? _cached;
  Future<AnonymousToken>? _inFlight;

  /// Returns a fresh-enough anonymous token, fetching the embed page only
  /// when the cached one is missing or about to expire. Concurrent callers
  /// share one bootstrap request.
  Future<AnonymousToken> ensureToken(String playlistId) {
    final cached = _cached;
    if (cached != null && !cached.isExpired) return Future.value(cached);
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final future = _fetchToken(playlistId).then((token) {
      _cached = token;
      return token;
    }).whenComplete(() => _inFlight = null);
    _inFlight = future;
    return future;
  }

  Future<AnonymousToken> _fetchToken(String playlistId) async {
    _log('Bootstrapping anonymous token from the embed page');
    try {
      final res = await _dio.get(
        'https://open.spotify.com/embed/playlist/$playlistId',
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );
      final html = res.data?.toString() ?? '';
      final token = _extract(html, r'accessToken\\":\\"([^\\"]+)') ??
          _extract(html, r'accessToken":"([^"]+)');
      final expiry = _extract(html, r'accessTokenExpirationTimestampMs\\":(\d+)') ??
          _extract(html, r'accessTokenExpirationTimestampMs":(\d+)');
      if (token == null || token.isEmpty) {
        throw const ResolveError(ResolveErrorCode.providerUnavailable,
            'Spotify did not provide an anonymous token for this playlist');
      }
      final expiresAtMs = int.tryParse(expiry ?? '') ?? 0;
      _log('Anonymous token acquired (expires in '
          '${((expiresAtMs - DateTime.now().millisecondsSinceEpoch) / 1000).round()}s)');
      return AnonymousToken(token, expiresAtMs);
    } on DioException catch (e) {
      throw _mapDioError(e, 'Could not fetch the Spotify embed page');
    }
  }

  String? _extract(String html, String pattern) {
    final match = RegExp(pattern).firstMatch(html);
    if (match == null) return null;
    return _unescape(match.group(1)!);
  }

  String _unescape(String s) =>
      s.replaceAll(r'\"', '"').replaceAll(r'\/', '/').replaceAll(r'\u0026', '&');

  // ---------------------------------------------------------------------
  // GraphQL
  // ---------------------------------------------------------------------

  /// Enumerates the playlist (name/artwork/total + track uris), following
  /// paging until all tracks are collected (bounded).
  Future<PlaylistMetadataPage> fetchPlaylist(String playlistId) async {
    final token = await ensureToken(playlistId);
    final uri = 'spotify:playlist:$playlistId';
    const pageSize = 100;
    const maxItems = 10000;

    List<Map<String, dynamic>> rawItems = [];
    String? name;
    String? description;
    String? owner;
    String? artworkUrl;
    int? totalCount;
    var offset = 0;

    while (rawItems.length < maxItems) {
      final data = await _query(
        token,
        'fetchPlaylistMetadata',
        'a65e12194ed5fc443a1cdebed5fabe33ca5b07b987185d63c72483867ad13cb4',
        {
          'uri': uri,
          'offset': offset,
          'limit': pageSize,
          'enableWatchFeedEntrypoint': true,
        },
      );
      final playlist = (data['playlistV2'] as Map?) ?? const {};
      name ??= playlist['name'] as String?;
      description ??= playlist['description'] as String?;
      final ownerV2 = playlist['ownerV2'] as Map?;
      final ownerData = (ownerV2?['data'] as Map?) ?? const {};
      owner ??= (ownerData['name'] ?? ownerData['username']) as String?;
      artworkUrl ??= _imageUrl(playlist['images']);
      final content = (playlist['content'] as Map?) ?? const {};
      totalCount = ((content['totalCount'] as num?)?.toInt()) ?? totalCount;

      final items = (content['items'] as List?) ?? const [];
      rawItems
          .addAll(items.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
      final paging = (content['pagingInfo'] as Map?) ?? const {};
      final nextOffset = (paging['nextOffset'] as num?)?.toInt();
      if (nextOffset == null || nextOffset <= offset || items.isEmpty) break;
      offset = nextOffset;
    }

    return PlaylistMetadataPage(
      playlistId: playlistId,
      name: name,
      description: description,
      owner: owner,
      artworkUrl: artworkUrl,
      totalCount: totalCount ?? rawItems.length,
      rawItems: rawItems,
    );
  }

  /// Fetches full metadata (title, artists, album, duration, artwork,
  /// explicit) for the given track uris in chunks of 50.
  Future<List<Map<String, dynamic>>> fetchTrackMetadata(
      AnonymousToken token, List<String> uris) async {
    final results = <Map<String, dynamic>>[];
    for (final chunk in _chunks(uris, 50)) {
      final data = await _query(
        token,
        'decorateContextTracks',
        '383de00240775c39a6afe0b1055dc562b2a3930894201f9762f3fc32a74971c7',
        {'uris': chunk},
      );
      final tracks = ((data['tracks'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      results.addAll(tracks);
      // Be gentle with the anonymous channel.
      if (chunk.length < 50) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return results;
  }

  Future<Map<String, dynamic>> _query(
    AnonymousToken token,
    String operation,
    String hash,
    Map<String, dynamic> variables,
  ) async {
    try {
      final res = await _dio.post(
        '/pathfinder/v2/query',
        data: {
          'operationName': operation,
          'variables': variables,
          'extensions': {
            'persistedQuery': {'version': 1, 'sha256Hash': hash},
          },
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer ${token.token}',
            'Content-Type': 'application/json',
            'App-Platform': 'WebPlayer',
            'Origin': 'https://open.spotify.com',
            'Referer': 'https://open.spotify.com/',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
          },
        ),
      );
      final body = res.data;
      if (body is! Map) {
        throw const ResolveError(ResolveErrorCode.invalidScraperResponse,
            'Spotify returned a malformed GraphQL response');
      }
      final errors = body['errors'];
      if (errors != null) {
        throw ResolveError(ResolveErrorCode.providerUnavailable,
            'Spotify GraphQL rejected the request: $errors');
      }
      return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
    } on DioException catch (e) {
      throw _mapDioError(e, 'Spotify GraphQL $operation failed');
    }
  }

  String? _imageUrl(dynamic images) {
    // GraphQL returns {"items": [{"sources": [{"url": ...}]}]};
    // tolerate a bare list too.
    final list = images is List
        ? images
        : ((images is Map && images['items'] is List)
            ? images['items'] as List
            : null);
    if (list == null || list.isEmpty) return null;
    final first = list.first;
    if (first is Map) {
      final sources = first['sources'];
      if (sources is List && sources.isNotEmpty) {
        final last = sources.last;
        if (last is Map) return last['url'] as String?;
      }
      final url = first['url'];
      if (url is String) return url;
    }
    if (first is String) return first;
    return null;
  }

  List<List<String>> _chunks(List<String> items, int size) {
    final result = <List<String>>[];
    for (var i = 0; i < items.length; i += size) {
      result.add(items.sublist(i, i + size > items.length ? items.length : i + size));
    }
    return result;
  }

  ResolveError _mapDioError(DioException e, String fallback) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      // Anonymous token rejected — Spotify has cut off this channel. Clear
      // the cached token so the next attempt bootstraps fresh.
      _cached = null;
      return const ResolveError(ResolveErrorCode.providerUnavailable,
          'Spotify anonymous access was rejected (credentials required)');
    }
    if (status == 429) {
      return const ResolveError(ResolveErrorCode.providerRateLimited,
          'Spotify anonymous access was rate limited');
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return const ResolveError(
          ResolveErrorCode.providerUnavailable, 'Spotify anonymous access timed out');
    }
    return ResolveError(
        ResolveErrorCode.providerUnavailable, '$fallback: ${e.message}');
  }
}

/// Raw page-level playlist data from the anonymous GraphQL channel.
class PlaylistMetadataPage {
  final String playlistId;
  final String? name;
  final String? description;
  final String? owner;
  final String? artworkUrl;
  final int totalCount;
  final List<Map<String, dynamic>> rawItems;

  const PlaylistMetadataPage({
    required this.playlistId,
    this.name,
    this.description,
    this.owner,
    this.artworkUrl,
    required this.totalCount,
    required this.rawItems,
  });
}
