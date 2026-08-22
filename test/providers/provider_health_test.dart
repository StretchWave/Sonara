import 'dart:convert';
import 'dart:typed_data';

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
    this.searchItems = const [],
  });

  final Map<String, dynamic> data;
  final int? errorStatusCode;
  final List<Map<String, dynamic>> searchItems;

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

  @override
  Future<List<Map<String, dynamic>>> searchTracks(String term) async {
    return searchItems;
  }
}

/// A dio adapter that answers every request from a canned handler so the
/// full source scan can run without touching the network.
class _StubHttpClientAdapter implements HttpClientAdapter {
  _StubHttpClientAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(Object data) => ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

/// A healthy InnerTube player response with a playable stream URL.
Map<String, dynamic> _youtubeOk() => {
      'playabilityStatus': {'status': 'OK'},
      'streamingData': {
        'adaptiveFormats': [
          {'url': 'https://googlevideo.example/audio', 'itag': 140},
        ],
      },
    };

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

  group('checkSources', () {
    ProviderHealthChecker checkerWith(Dio dio) => ProviderHealthChecker(
          qobuzApi: _FakeQobuzApi(items: [_trackItem('42')]),
          tidalApi: _FakeTidalApi(
            data: {'manifest': 'https://cdn/x.mpd'},
            searchItems: [_trackItem('1')],
          ),
          dio: dio,
          soundcloudClientId: () async => 'fake-client-id',
        );

    Dio stubDio(ResponseBody Function(RequestOptions) handler) =>
        Dio(BaseOptions())..httpClientAdapter = _StubHttpClientAdapter(handler);

    test('returns one result per source with stable source ids', () async {
      final dio = stubDio((o) => _jsonResponse({}));
      final checker = checkerWith(dio);
      final results = await checker.checkSources(const StreamRouteConfig());
      expect(
        results.map((r) => r.sourceId).toList(),
        [
          'youtube_music',
          'soundcloud',
          'qobuz',
          'tidal',
          'deezer',
          'apple',
          'amazon',
          'instagram',
        ],
      );
    });

    test('reports online when every probe answers positively', () async {
      final dio = stubDio((o) {
        final path = o.uri.toString();
        if (path.contains('youtubei')) {
          return _jsonResponse(_youtubeOk());
        }
        return _jsonResponse({});
      });
      final checker = checkerWith(dio);
      final results = await checker.checkSources(const StreamRouteConfig(
        qobuzInstances: ['https://q.example'],
        tidalEndpoints: ['https://t.example'],
      ));

      final byId = {for (final r in results) r.sourceId: r};
      expect(byId['youtube_music']!.status, ProviderHealthStatus.online);
      expect(byId['soundcloud']!.status, ProviderHealthStatus.online);
      expect(byId['qobuz']!.status, ProviderHealthStatus.online);
      expect(byId['tidal']!.status, ProviderHealthStatus.online);
    });

    test('sources without a resolver report configured=false', () async {
      final dio = stubDio((o) {
        final path = o.uri.toString();
        if (path.contains('youtubei')) {
          return _jsonResponse(_youtubeOk());
        }
        return _jsonResponse({});
      });
      final checker = checkerWith(dio);
      final results =
          await checker.checkSources(const StreamRouteConfig());

      final byId = {for (final r in results) r.sourceId: r};
      expect(byId['qobuz']!.configured, isFalse);
      expect(byId['deezer']!.configured, isFalse);
      expect(byId['apple']!.configured, isFalse);
      expect(byId['amazon']!.configured, isFalse);
      expect(byId['instagram']!.configured, isFalse);
      expect(byId['instagram']!.message,
          contains(RegExp('no Instagram session', caseSensitive: false)));
    });

    test('deezer resolver probe reports online when a stream is returned',
        () async {
      final dio = stubDio((o) {
        final path = o.uri.toString();
        if (path.contains('youtubei')) {
          return _jsonResponse(_youtubeOk());
        }
        if (path.contains('get_url')) {
          return _jsonResponse({
            'data': [
              {'media': [{'sources': [{'url': 'https://cdn/x.mp3'}]}]},
            ],
          });
        }
        return _jsonResponse({});
      });
      final checker = checkerWith(dio);
      final results = await checker.checkSources(const StreamRouteConfig(
        deezerEnabled: true,
        deezerEndpoints: ['https://d.example'],
      ));

      final byId = {for (final r in results) r.sourceId: r};
      expect(byId['deezer']!.configured, isTrue);
      expect(byId['deezer']!.status, ProviderHealthStatus.online);
    });
  });
}
