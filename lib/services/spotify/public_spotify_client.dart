import 'dart:async';
import 'package:dio/dio.dart';

import 'spotify_source_track.dart';

/// A fetched anonymous token plus its wall-clock expiry (ms epoch).
class AnonymousSpotifyToken {
  final String token;
  final int expiresAtMs;
  AnonymousSpotifyToken(this.token, this.expiresAtMs);
  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >= (expiresAtMs - 30000);
}

/// Result of fetching a playlist anonymously through Spotify's partner GraphQL channel.
class PublicPlaylistResult {
  final String playlistId;
  final String? name;
  final String? description;
  final String? artworkUrl;
  final int totalCount;
  final List<SpotifySourceTrack> tracks;

  const PublicPlaylistResult({
    required this.playlistId,
    this.name,
    this.description,
    this.artworkUrl,
    required this.totalCount,
    required this.tracks,
  });
}

/// Public, credential-free client for Spotify playlists.
///
/// Bootstraps an anonymous web-player access token from the embed page, then
/// queries Spotify's partner GraphQL (pathfinder) API to enumerate the full
/// playlist (with pagination) and hydrate track metadata.
///
/// Supports playlists of any size (100, 500, 1000+ tracks) without requiring
/// any user login, Spotify Developer account, or server-side proxy.
class PublicSpotifyClient {
  final Dio _dio;
  final Dio _embedDio;

  PublicSpotifyClient({Dio? dio, Dio? embedDio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api-partner.spotify.com',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            )),
        _embedDio = embedDio ??
            Dio(BaseOptions(
              baseUrl: 'https://open.spotify.com',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ));

  AnonymousSpotifyToken? _cachedToken;
  Future<AnonymousSpotifyToken>? _inFlightToken;

  /// Returns a valid anonymous token, fetching from the embed page if absent or expired.
  Future<AnonymousSpotifyToken> ensureToken(String playlistId) {
    final cached = _cachedToken;
    if (cached != null && !cached.isExpired) return Future.value(cached);
    final inFlight = _inFlightToken;
    if (inFlight != null) return inFlight;

    final future = _fetchToken(playlistId).then((token) {
      _cachedToken = token;
      return token;
    }).whenComplete(() => _inFlightToken = null);
    _inFlightToken = future;
    return future;
  }

  Future<AnonymousSpotifyToken> _fetchToken(String playlistId) async {
    final res = await _embedDio.get<String>(
      '/embed/playlist/$playlistId',
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml',
        },
        responseType: ResponseType.plain,
      ),
    );
    final html = res.data ?? '';
    final token =
        _extract(html, r'accessToken(?:\\*)?":\s*(?:\\*)?"([^\\"]+)');
    final expiry = _extract(
        html, r'accessTokenExpirationTimestampMs(?:\\*)?":\s*(\d+)');
    if (token == null || token.isEmpty) {
      throw Exception('Could not bootstrap anonymous Spotify token');
    }
    final expiresAtMs = int.tryParse(expiry ?? '') ??
        (DateTime.now().millisecondsSinceEpoch + 3600000);
    return AnonymousSpotifyToken(token, expiresAtMs);
  }

  String? _extract(String html, String pattern) {
    final match = RegExp(pattern).firstMatch(html);
    return match?.group(1);
  }

  /// Fetches playlist metadata and every track via GraphQL pagination,
  /// followed by chunked metadata decoration.
  Future<PublicPlaylistResult> fetchPlaylist(String playlistId,
      {int maxItems = 10000}) async {
    final token = await ensureToken(playlistId);
    final uri = 'spotify:playlist:$playlistId';
    const pageSize = 100;

    final rawItems = <Map<String, dynamic>>[];
    String? name;
    String? description;
    String? artworkUrl;
    int? totalCount;
    var offset = 0;

    // 1. Enumerate all pages of items from GraphQL
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
      artworkUrl ??= _extractImageUrl(playlist['images']);

      final content = (playlist['content'] as Map?) ?? const {};
      totalCount = ((content['totalCount'] as num?)?.toInt()) ?? totalCount;

      final items = (content['items'] as List?) ?? const [];
      rawItems.addAll(items.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));

      final paging = (content['pagingInfo'] as Map?) ?? const {};
      final nextOffset = (paging['nextOffset'] as num?)?.toInt();
      if (nextOffset == null || nextOffset <= offset || items.isEmpty) break;
      if (totalCount != null && rawItems.length >= totalCount) break;
      offset = nextOffset;
    }

    // 2. Collect track URIs preserving playlist order
    final uris = <String>[];
    for (final item in rawItems) {
      final trackUri = _extractTrackUri(item);
      if (trackUri != null && !uris.contains(trackUri)) {
        uris.add(trackUri);
      }
    }

    if (uris.isEmpty) {
      return PublicPlaylistResult(
        playlistId: playlistId,
        name: name,
        description: description,
        artworkUrl: artworkUrl,
        totalCount: totalCount ?? 0,
        tracks: const [],
      );
    }

    // 3. Hydrate track details in chunks of 50
    final decoratedMap = <String, Map<String, dynamic>>{};
    for (final chunk in _chunkList(uris, 50)) {
      try {
        final decorated = await _query(
          token,
          'decorateContextTracks',
          '383de00240775c39a6afe0b1055dc562b2a3930894201f9762f3fc32a74971c7',
          {'uris': chunk},
        );
        final tracksList = ((decorated['tracks'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m));
        for (final t in tracksList) {
          final u = t['uri'] as String?;
          if (u != null) decoratedMap[u] = t;
        }
      } catch (_) {
        // Individual chunk failures don't stop the rest
      }
      if (chunk.length >= 50) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }

    // 4. Assemble final ordered SpotifySourceTrack list
    final tracks = <SpotifySourceTrack>[];
    var trackNum = 1;
    for (final item in rawItems) {
      final trackUri = _extractTrackUri(item);
      if (trackUri == null) continue;

      final trackId = trackUri.startsWith('spotify:track:')
          ? trackUri.substring('spotify:track:'.length)
          : trackUri;

      final decorated = decoratedMap[trackUri];
      if (decorated != null) {
        final title = (decorated['name'] as String?)?.trim() ?? '';
        if (title.isEmpty) continue;

        final artistsList = ((decorated['artists']?['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((a) => (a['profile']?['name'] as String?)?.trim())
            .whereType<String>()
            .where((n) => n.isNotEmpty)
            .toList();

        final albumMap = decorated['albumOfTrack'] as Map?;
        final albumName = albumMap?['name'] as String?;
        final albumArt = _extractImageUrl(albumMap?['coverArt']);

        final duration = decorated['duration'] as Map?;
        final durationMs =
            ((duration?['totalMilliseconds'] as num?)?.toInt()) ??
                _extractDuration(item);

        final rating = decorated['contentRating'] as Map?;
        final explicit = rating?['label'] == 'EXPLICIT';

        tracks.add(SpotifySourceTrack(
          spotifyId: trackId,
          title: title,
          artists: artistsList,
          album: albumName,
          durationMs: durationMs,
          explicit: explicit,
          trackNumber: trackNum++,
          artworkUrl: albumArt ?? artworkUrl,
        ));
      } else {
        // Fallback to basic details extracted from the playlist item if decoration failed
        final itemV2 = item['itemV2'] as Map?;
        final data = itemV2?['data'] as Map?;
        final title = (data?['name'] as String?)?.trim() ?? '';
        if (title.isEmpty) continue;

        final durationMs = _extractDuration(item);
        tracks.add(SpotifySourceTrack(
          spotifyId: trackId,
          title: title,
          artists: const [],
          album: name,
          durationMs: durationMs,
          trackNumber: trackNum++,
          artworkUrl: artworkUrl,
        ));
      }
    }

    return PublicPlaylistResult(
      playlistId: playlistId,
      name: name,
      description: description,
      artworkUrl: artworkUrl,
      totalCount: totalCount ?? tracks.length,
      tracks: tracks,
    );
  }

  Future<Map<String, dynamic>> _query(
    AnonymousSpotifyToken token,
    String operation,
    String hash,
    Map<String, dynamic> variables,
  ) async {
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
              '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        },
      ),
    );
    final body = res.data;
    if (body is! Map) {
      throw Exception('Malformed GraphQL response');
    }
    if (body['errors'] != null) {
      throw Exception('GraphQL error: ${body['errors']}');
    }
    return Map<String, dynamic>.from(body['data'] as Map? ?? const {});
  }

  String? _extractTrackUri(Map<String, dynamic> item) {
    final itemV2 = item['itemV2'] as Map?;
    final data = itemV2?['data'] as Map?;
    final uri = data?['uri'];
    if (uri is String && uri.startsWith('spotify:track:')) return uri;
    return null;
  }

  int _extractDuration(Map<String, dynamic> item) {
    final itemV2 = item['itemV2'] as Map?;
    final data = itemV2?['data'] as Map?;
    final duration = data?['trackDuration'] as Map?;
    return ((duration?['totalMilliseconds'] as num?)?.toInt()) ?? 0;
  }

  String? _extractImageUrl(dynamic coverArt) {
    if (coverArt == null) return null;
    final sources = coverArt is Map
        ? (coverArt['sources'] ?? coverArt['items'])
        : (coverArt is List ? coverArt : null);
    if (sources is List && sources.isNotEmpty) {
      final last = sources.last;
      if (last is Map) return last['url'] as String?;
      if (last is String) return last;
      final first = sources.first;
      if (first is Map) return first['url'] as String?;
    }
    return null;
  }

  List<List<T>> _chunkList<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return chunks;
  }
}
