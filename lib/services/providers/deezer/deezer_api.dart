import 'dart:convert';
import 'dart:io';

/// Thin wrapper around Deezer's public API for searching tracks and
/// fetching track metadata.  No authentication required — the public
/// search API is used for catalog lookups; stream URLs come from a
/// resolver endpoint.
class DeezerApi {
  static const String _searchUrl = 'https://api.deezer.com/search/track';
  static const String _isrcUrl = 'https://api.deezer.com/track/isrc:';

  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) '
      'Gecko/20100101 Firefox/140.0';

  /// Searches Deezer for tracks matching [term].
  ///
  /// Returns a list of raw JSON objects from the Deezer API, or an
  /// empty list on failure.
  Future<List<Map<String, dynamic>>> searchTracks(
    String term, {
    int limit = 12,
    String? proxyUrl,
  }) async {
    final uri = Uri.parse(_searchUrl).replace(queryParameters: {
      'q': term,
      'limit': limit.toString(),
    });

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      try {
        final req = await client.getUrl(uri);
        req.headers.set('User-Agent', _browserUserAgent);
        req.headers.set('Accept', 'application/json');
        final res = await req.close().timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) return const [];
        final body = await utf8.decoder.bind(res).join();
        final json = jsonDecode(body);
        final data = json['data'];
        if (data is List) {
          return data.whereType<Map<String, dynamic>>().toList();
        }
        return const [];
      } finally {
        client.close();
      }
    } catch (_) {
      return const [];
    }
  }

  /// Resolves an ISRC code to a Deezer track ID.
  Future<Map<String, dynamic>?> lookupIsrc(String isrc) async {
    final uri = Uri.parse('$_isrcUrl$isrc');
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      try {
        final req = await client.getUrl(uri);
        req.headers.set('User-Agent', _browserUserAgent);
        req.headers.set('Accept', 'application/json');
        final res = await req.close().timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) return null;
        final body = await utf8.decoder.bind(res).join();
        final json = jsonDecode(body);
        if (json is Map<String, dynamic> && json.containsKey('error')) return null;
        return json as Map<String, dynamic>?;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Fetches the content-length of a URL (HEAD request) for preview
  /// detection.
  Future<int?> fetchContentLength(String url) async {
    try {
      final uri = Uri.parse(url);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      try {
        final req = await client.openUrl('HEAD', uri);
        req.headers.set('User-Agent', _browserUserAgent);
        req.headers.set('Accept', '*/*');
        final res = await req.close().timeout(const Duration(seconds: 6));
        if (res.statusCode >= 200 && res.statusCode < 400) {
          final length = res.headers.value('content-length');
          if (length != null) return int.tryParse(length);
        }
        return null;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }
}
