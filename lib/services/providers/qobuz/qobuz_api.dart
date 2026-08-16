import 'package:dio/dio.dart';

/// Raised when a Qobuz resolver rejects a request.
class QobuzApiException implements Exception {
  QobuzApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// HTTP access to Kenny-style Qobuz resolver instances.
///
/// Wrapped so tests can substitute canned responses; production uses
/// [Dio] (already a project dependency).
class QobuzApi {
  QobuzApi({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36';

  /// Searches Qobuz through [baseUrl] and returns the raw track items
  /// (may be empty).
  Future<List<Map<String, dynamic>>> searchTracks(
    String baseUrl,
    String term,
    String country,
  ) async {
    final response = await _dio.get(
      '$baseUrl/api/get-music',
      queryParameters: {'q': term, 'offset': 0},
      options: Options(
        headers: {
          'Accept': 'application/json',
          'Referer': '$baseUrl/',
          'User-Agent': 'Mozilla/5.0',
        },
      ),
    );
    final root = response.data;
    if (root is! Map || root['success'] != true) return const [];
    final data = root['data'];
    if (data is! Map) return const [];
    final tracks = data['tracks'];
    if (tracks is! Map) return const [];
    final items = tracks['items'];
    if (items is! List) return const [];
    return items.whereType<Map>().cast<Map<String, dynamic>>().toList();
  }

  /// Requests a stream URL for [trackId] at [quality] (27/7/6/5).
  /// Throws [QobuzApiException] when the resolver rejects the request.
  Future<Map<String, dynamic>> requestStream(
    String baseUrl,
    String trackId,
    int quality,
  ) async {
    final response = await _dio.get(
      '$baseUrl/api/download-music',
      queryParameters: {'track_id': trackId, 'quality': quality},
      options: Options(
        headers: {
          'Accept': 'application/json,text/plain,*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          'Origin': baseUrl,
          'Referer': '$baseUrl/',
          'User-Agent': _browserUserAgent,
        },
      ),
    );
    final root = response.data;
    if (root is! Map) {
      throw QobuzApiException('Qobuz resolver returned no JSON');
    }
    if (root['success'] != true) {
      final error = root['error'] ?? root['message'] ?? 'unknown error';
      throw QobuzApiException('Qobuz rejected quality $quality: $error');
    }
    final data = root['data'];
    final url = data is Map && data['url'] != null
        ? data['url'] as String
        : root['url'] as String?;
    if (url == null || url.isEmpty) {
      throw QobuzApiException('Qobuz resolver returned no stream URL');
    }
    final result = <String, dynamic>{'url': url};
    if (data is Map) {
      for (final key in const [
        'format_id',
        'bit_depth',
        'sampling_rate',
        'mime_type',
        'bitrate',
        'bit_rate',
        'average_bitrate',
      ]) {
        if (data[key] != null) result[key] = data[key];
      }
    }
    return result;
  }

  /// Estimates the total byte length of [url] with a Range request.
  /// Returns null when the server does not expose a length.
  Future<int?> fetchContentLength(String url) async {
    try {
      final response = await _dio.get(
        url,
        options: Options(
          headers: {
            'Range': 'bytes=0-0',
            'Accept': '*/*',
            'User-Agent': _browserUserAgent,
          },
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final contentRange = response.headers.value('content-range');
      if (contentRange != null) {
        final total = contentRange.split('/').last.trim();
        final parsed = int.tryParse(total);
        if (parsed != null && parsed > 0) return parsed;
      }
      final length = response.headers.value('content-length');
      final parsed = length == null ? null : int.tryParse(length);
      if (parsed != null && parsed > 0) return parsed;
    } catch (_) {
      // Range requests are best-effort; a failure only skips the preview
      // check, never fails the stream.
    }
    return null;
  }
}
