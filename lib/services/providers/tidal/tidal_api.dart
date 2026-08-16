import 'package:dio/dio.dart';

/// Raised when a Tidal resolver rejects a request.
class TidalApiException implements Exception {
  TidalApiException(this.message, {this.statusCode});

  final String message;

  /// HTTP status code when the failure came from an HTTP response.
  final int? statusCode;

  @override
  String toString() => message;
}

/// HTTP access to Tidal's public search API and user-configured resolver
/// endpoints.
///
/// Wrapped so tests can substitute canned responses; production uses
/// [Dio] (already a project dependency).
class TidalApi {
  TidalApi({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Tidal's public web client token, used for catalog search only.
  static const String publicToken = '49YxDN9a2aFV6RTG';

  static const String apiBaseUrl = 'https://tidal.com/v1';

  static const String _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36';

  /// Searches Tidal's public catalog and returns raw track items.
  Future<List<Map<String, dynamic>>> searchTracks(String term) async {
    final response = await _dio.get(
      '$apiBaseUrl/search/tracks',
      queryParameters: {
        'countryCode': 'US',
        'locale': 'en_US',
        'deviceType': 'BROWSER',
        'query': term,
        'limit': 8,
        'offset': 0,
      },
      options: Options(
        headers: {
          'Accept': 'application/json',
          'User-Agent': _browserUserAgent,
          'x-tidal-token': publicToken,
        },
      ),
    );
    final items = response.data is Map ? response.data['items'] : null;
    if (items is! List) return const [];
    return items.whereType<Map>().cast<Map<String, dynamic>>().toList();
  }

  /// Requests a stream manifest for [trackId] at [quality]
  /// (e.g. LOSSLESS, HI_RES_LOSSLESS, HIGH, LOW) from a configured
  /// resolver endpoint. Returns the resolver's `data` object.
  ///
  /// Throws [TidalApiException] on rejection or rate limiting.
  Future<Map<String, dynamic>> requestStream(
    String baseUrl,
    String trackId,
    String quality,
  ) async {
    try {
      final response = await _dio.get(
        '$baseUrl/track',
        queryParameters: {'id': trackId, 'quality': quality},
        options: Options(
          headers: {
            'Accept': 'application/json',
            'User-Agent': _browserUserAgent,
          },
        ),
      );
      final root = response.data;
      if (root is! Map) {
        throw TidalApiException('TIDAL resolver returned no JSON');
      }
      final data = root['data'];
      if (data is! Map) {
        throw TidalApiException('TIDAL resolver returned no data');
      }
      return Map<String, dynamic>.from(data);
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 429) {
        throw TidalApiException(
          'TIDAL resolver is rate limited',
          statusCode: 429,
        );
      }
      throw TidalApiException(
        'TIDAL resolver HTTP $statusCode',
        statusCode: statusCode,
      );
    }
  }
}
