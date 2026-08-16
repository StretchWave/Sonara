import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/provider_health.dart';
import 'package:sonara/services/providers/qobuz/qobuz_api.dart';
import 'package:sonara/services/providers/stream_route_config.dart';
import 'package:sonara/services/providers/tidal/tidal_api.dart';

class _FakeQobuzApi extends QobuzApi {
  _FakeQobuzApi({
    this.items = const [],
    this.throwOnStream = false,
    this.throwNetwork = false,
  });

  final List<Map<String, dynamic>> items;
  final bool throwOnStream;
  final bool throwNetwork;

  @override
  Future<List<Map<String, dynamic>>> searchTracks(
    String baseUrl,
    String term,
    String country,
  ) async {
    if (throwNetwork) {
      throw DioException(requestOptions: RequestOptions(path: baseUrl));
    }
    return items;
  }

  @override
  Future<Map<String, dynamic>> requestStream(
    String baseUrl,
    String trackId,
    int quality,
  ) async {
    if (throwNetwork) {
      throw DioException(requestOptions: RequestOptions(path: baseUrl));
    }
    if (throwOnStream) {
      throw QobuzApiException('Qobuz rejected quality $quality');
    }
    return {'url': 'https://cdn/stream.flac'};
  }
}

class _FakeTidalApi extends TidalApi {
  _FakeTidalApi({
    this.data = const {},
    this.errorStatusCode,
  });

  final Map<String, dynamic> data;
  final int? errorStatusCode;

  @override
  Future<Map<String, dynamic>> requestStream(
    String baseUrl,
    String trackId,
    String quality,
  ) async {
    if (errorStatusCode != null) {
      throw TidalApiException(
        'TIDAL resolver HTTP $errorStatusCode',
        statusCode: errorStatusCode,
      );
    }
    return data;
  }
}

Map<String, dynamic> _trackItem(String id) => {
      'id': id,
      'title': 'Test',
      'downloadable': true,
      'streamable': true,
    };

void main() {
  test('reports online for a healthy Qobuz resolver', () async {
    final checker = ProviderHealthChecker(
      qobuzApi: _FakeQobuzApi(items: [_trackItem('42')]),
    );
    final results = await checker.checkAll(
      const StreamRouteConfig(qobuzInstances: ['https://q.example']),
    );
    expect(results.single.status, ProviderHealthStatus.online);
    expect(results.single.message, contains('OK'));
    expect(results.single.latencyMs, isNotNull);
  });

  test('reports reachable when the Qobuz search returns nothing', () async {
    final checker = ProviderHealthChecker(qobuzApi: _FakeQobuzApi());
    final results = await checker.checkAll(
      const StreamRouteConfig(qobuzInstances: ['https://q.example']),
    );
    expect(results.single.status, ProviderHealthStatus.reachable);
  });

  test('reports reachable when Qobuz rejects the stream request', () async {
    final checker = ProviderHealthChecker(
      qobuzApi: _FakeQobuzApi(items: [_trackItem('42')], throwOnStream: true),
    );
    final results = await checker.checkAll(
      const StreamRouteConfig(qobuzInstances: ['https://q.example']),
    );
    expect(results.single.status, ProviderHealthStatus.reachable);
  });

  test('reports offline when a Qobuz resolver is unreachable', () async {
    final checker = ProviderHealthChecker(
      qobuzApi: _FakeQobuzApi(throwNetwork: true),
    );
    final results = await checker.checkAll(
      const StreamRouteConfig(qobuzInstances: ['https://q.example']),
    );
    expect(results.single.status, ProviderHealthStatus.offline);
  });

  test('reports online for a healthy Tidal endpoint', () async {
    final checker = ProviderHealthChecker(
      tidalApi: _FakeTidalApi(data: {'manifest': 'https://cdn/x.mpd'}),
    );
    final results = await checker.checkAll(
      const StreamRouteConfig(tidalEndpoints: ['https://t.example']),
    );
    expect(results.single.status, ProviderHealthStatus.online);
  });

  test('reports reachable on Tidal rate limiting', () async {
    final checker = ProviderHealthChecker(
      tidalApi: _FakeTidalApi(errorStatusCode: 429),
    );
    final results = await checker.checkAll(
      const StreamRouteConfig(tidalEndpoints: ['https://t.example']),
    );
    expect(results.single.status, ProviderHealthStatus.reachable);
  });

  test('reports offline when a Tidal endpoint is unreachable', () async {
    final checker = ProviderHealthChecker(
      tidalApi: _FakeTidalApi(errorStatusCode: 500),
    );
    final results = await checker.checkAll(
      const StreamRouteConfig(tidalEndpoints: ['https://t.example']),
    );
    expect(results.single.status, ProviderHealthStatus.offline);
  });

  test('returns an empty list when nothing is configured', () async {
    final checker = ProviderHealthChecker(
      qobuzApi: _FakeQobuzApi(),
      tidalApi: _FakeTidalApi(),
    );
    final results = await checker.checkAll(const StreamRouteConfig());
    expect(results, isEmpty);
  });
}
