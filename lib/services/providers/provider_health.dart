import 'package:dio/dio.dart';

import 'amazon/amazon_provider.dart';
import 'apple/apple_provider.dart';
import 'deezer/deezer_provider.dart';
import 'models/provider_error.dart';
import 'models/provider_id.dart';
import 'qobuz/qobuz_api.dart';
import 'soundcloud/soundcloud_audio_provider.dart';
import 'stream_route_config.dart';
import 'tidal/tidal_api.dart';

/// Health status of a source / resolver probe.
enum ProviderHealthStatus { online, reachable, offline }

/// Result of probing one audio source or one configured resolver.
class ProviderHealthResult {
  const ProviderHealthResult({
    required this.name,
    required this.endpoint,
    required this.status,
    required this.message,
    this.sourceId = '',
    this.configured = true,
    this.latencyMs,
  });

  /// Stable provider id (`youtube_music`, `qobuz`, `tidal`, ...) so the UI
  /// can map a probe back to a source for priority ordering.
  final String sourceId;

  final String name;

  final String endpoint;

  final ProviderHealthStatus status;

  final String message;

  /// Whether the source is enabled and has the config it needs to stream
  /// (e.g. a resolver URL).  A source can be reachable but not configured.
  final bool configured;

  final int? latencyMs;
}

/// Probes each audio source with real requests so the user can see at a
/// glance which sources are available and working (mirrors MetroFuse's
/// ProviderHealthChecker).
class ProviderHealthChecker {
  ProviderHealthChecker({
    QobuzApi? qobuzApi,
    TidalApi? tidalApi,
    Dio? dio,
    Future<String?> Function()? soundcloudClientId,
  })  : _qobuz = qobuzApi ?? QobuzApi(),
        _tidal = tidalApi ?? TidalApi(),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 8),
            )),
        _soundcloudClientId = soundcloudClientId ??
            SoundCloudAudioProvider.getClientId;

  final QobuzApi _qobuz;
  final TidalApi _tidal;
  final Dio _dio;
  final Future<String?> Function() _soundcloudClientId;

  /// Display names for every source the app can route through.
  static const Map<String, String> sourceNames = {
    'youtube_music': 'YouTube Music',
    'soundcloud': 'SoundCloud',
    'qobuz': 'Qobuz',
    'tidal': 'Tidal',
    'deezer': 'Deezer',
    'apple': 'Apple Music',
    'amazon': 'Amazon Music',
    'instagram': 'Instagram',
  };

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36';

  static const String _youtubeProbeVideoId = 'dQw4w9WgXcQ';
  static const String _tidalProbeQuery = 'starboy';
  static const String _tidalProbeTrackId = '4875683';
  static const String _qobuzProbeQuery = 'yes and ariana grande';
  static const int _deezerProbeTrackId = 3135556;
  static const String _appleProbeIsrc = 'USUM71703861';
  static const String _amazonProbeAsin = 'B0C4Y6R4H3';

  /// Probes every configured Qobuz instance and Tidal endpoint.
  ///
  /// Kept for backward compatibility; prefer [checkSources] for a full scan.
  Future<List<ProviderHealthResult>> checkAll(StreamRouteConfig config) async {
    final results = <ProviderHealthResult>[];
    for (var i = 0; i < config.qobuzInstances.length; i++) {
      results.add(await _checkQobuz(config.qobuzInstances[i], i + 1));
    }
    for (var i = 0; i < config.tidalEndpoints.length; i++) {
      results.add(await _checkTidal(config.tidalEndpoints[i], i + 1));
    }
    return results;
  }

  /// Scans every source the app can route through (in parallel) and returns
  /// one result per source.  Resolver-based sources probe their configured
  /// resolvers when present, otherwise they report the catalog availability.
  Future<List<ProviderHealthResult>> checkSources(
    StreamRouteConfig config,
  ) async {
    final futures = <Future<ProviderHealthResult>>[
      _checkYouTube(),
      _checkSoundCloud(),
      _checkQobuzSource(config),
      _checkTidalSource(config),
      _checkDeezerSource(config),
      _checkAppleSource(config),
      _checkAmazonSource(config),
      _checkInstagramSource(config),
    ];
    return Future.wait(futures);
  }

  // ---- Always-on sources ------------------------------------------------

  Future<ProviderHealthResult> _checkYouTube() async {
    final sw = Stopwatch()..start();
    try {
      final res = await _dio.post(
        'https://music.youtube.com/youtubei/v1/player?prettyPrint=false',
        data: {
          'context': {
            'client': {
              'clientName': 'IOS',
              'clientVersion': '21.03.3',
              'deviceMake': 'Apple',
              'deviceModel': 'iPad7,6',
              'osName': 'iPadOS',
              'osVersion': '17.7.10.21H450',
              'gl': 'US',
              'hl': 'en',
            }
          },
          'videoId': _youtubeProbeVideoId,
          'contentCheckOk': true,
          'racyCheckOk': true,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Origin': 'https://music.youtube.com',
            'X-YouTube-Client-Name': '5',
            'X-YouTube-Client-Version': '21.03.3',
            'User-Agent': _userAgent,
          },
        ),
      );
      final json = res.data;
      Object? status;
      Object? streamUrl;
      if (json is Map) {
        final playability = json['playabilityStatus'];
        if (playability is Map) status = playability['status'];
        final streamingData = json['streamingData'];
        if (streamingData is Map) {
          final formats = streamingData['adaptiveFormats'];
          if (formats is List && formats.isNotEmpty) {
            final first = formats.first;
            if (first is Map) streamUrl = first['url'];
          }
        }
      }
      if (res.statusCode == 200 &&
          status == 'OK' &&
          streamUrl is String &&
          streamUrl.isNotEmpty) {
        return _result('youtube_music', true, ProviderHealthStatus.online, sw,
            'Streams available');
      }
      return _result('youtube_music', true, ProviderHealthStatus.reachable, sw,
          'Player answered (status: $status)');
    } on DioException catch (e) {
      return _result('youtube_music', true, ProviderHealthStatus.offline, sw,
          'Unreachable: ${e.message ?? e.type}');
    } catch (e) {
      return _result('youtube_music', true, ProviderHealthStatus.offline, sw,
          'Error: ${e.runtimeType}');
    }
  }

  Future<ProviderHealthResult> _checkSoundCloud() async {
    final sw = Stopwatch()..start();
    try {
      final clientId = await _soundcloudClientId();
      if (clientId != null && clientId.isNotEmpty) {
        return _result('soundcloud', true, ProviderHealthStatus.online, sw,
            'Client ID acquired');
      }
      return _result('soundcloud', true, ProviderHealthStatus.offline, sw,
          'Could not acquire client ID');
    } catch (e) {
      return _result('soundcloud', true, ProviderHealthStatus.offline, sw,
          'Error: ${e.runtimeType}');
    }
  }

  // ---- Resolver-based sources -------------------------------------------

  Future<ProviderHealthResult> _checkQobuzSource(
    StreamRouteConfig config,
  ) async {
    if (config.qobuzInstances.isEmpty) {
      return _result('qobuz', false, ProviderHealthStatus.offline,
          Stopwatch()..start(), 'No Qobuz resolver configured');
    }
    final results = <ProviderHealthResult>[];
    for (var i = 0; i < config.qobuzInstances.length; i++) {
      results.add(await _checkQobuz(config.qobuzInstances[i], i + 1));
    }
    return _aggregate('qobuz', results);
  }

  Future<ProviderHealthResult> _checkTidalSource(
    StreamRouteConfig config,
  ) async {
    final sw = Stopwatch()..start();
    String catalogMsg;
    ProviderHealthStatus catalogStatus;
    try {
      final items = await _tidal.searchTracks(_tidalProbeQuery);
      catalogStatus = ProviderHealthStatus.reachable;
      catalogMsg =
          items.isNotEmpty ? 'Catalog search OK' : 'Catalog answered (empty)';
    } catch (_) {
      catalogStatus = ProviderHealthStatus.offline;
      catalogMsg = 'Catalog unreachable';
    }
    if (config.tidalEndpoints.isEmpty) {
      return _result('tidal', false, catalogStatus, sw,
          '$catalogMsg — no Tidal resolver configured');
    }
    final results = <ProviderHealthResult>[];
    for (var i = 0; i < config.tidalEndpoints.length; i++) {
      results.add(await _checkTidal(config.tidalEndpoints[i], i + 1));
    }
    final agg = _aggregate('tidal', results);
    return ProviderHealthResult(
      sourceId: 'tidal',
      name: sourceNames['tidal']!,
      endpoint: 'Tidal',
      configured: true,
      status: agg.status,
      message: '${agg.message} · $catalogMsg',
      latencyMs: agg.latencyMs,
    );
  }

  Future<ProviderHealthResult> _checkDeezerSource(
    StreamRouteConfig config,
  ) async {
    final endpoints = config.deezerEnabled
        ? (config.deezerEndpoints.isNotEmpty
              ? config.deezerEndpoints
              : DeezerProvider.defaultEndpoints)
        : const <String>[];
    if (endpoints.isEmpty) {
      final sw = Stopwatch()..start();
      try {
        final res = await _dio.get('https://api.deezer.com/infos');
        final ok = res.statusCode == 200;
        return _result('deezer', false,
            ok ? ProviderHealthStatus.reachable : ProviderHealthStatus.offline,
            sw, ok
                ? 'Catalog API OK — Deezer not enabled'
                : 'Deezer API HTTP ${res.statusCode}');
      } catch (e) {
        return _result('deezer', false, ProviderHealthStatus.offline, sw,
            'Deezer API unreachable');
      }
    }
    final results = <ProviderHealthResult>[];
    for (var i = 0; i < endpoints.length; i++) {
      results.add(await _checkDeezer(endpoints[i], i + 1));
    }
    return _aggregate('deezer', results);
  }

  Future<ProviderHealthResult> _checkAppleSource(
    StreamRouteConfig config,
  ) async {
    final endpoints = config.appleEnabled
        ? (config.appleEndpoints.isNotEmpty
              ? config.appleEndpoints
              : AppleProvider.defaultEndpoints)
        : const <String>[];
    if (endpoints.isEmpty) {
      final sw = Stopwatch()..start();
      try {
        final res = await _dio.get(
          'https://yesitworkssomehow-funny-deeza-api-and-yeah.hf.space/apple/token',
        );
        final ok = res.statusCode == 200;
        return _result('apple', false,
            ok ? ProviderHealthStatus.reachable : ProviderHealthStatus.offline,
            sw, ok
                ? 'Token API OK — Apple not enabled'
                : 'Apple token API HTTP ${res.statusCode}');
      } catch (e) {
        return _result('apple', false, ProviderHealthStatus.offline, sw,
            'Apple token API unreachable');
      }
    }
    final results = <ProviderHealthResult>[];
    for (var i = 0; i < endpoints.length; i++) {
      results.add(await _checkApple(endpoints[i], i + 1));
    }
    return _aggregate('apple', results);
  }

  Future<ProviderHealthResult> _checkAmazonSource(
    StreamRouteConfig config,
  ) async {
    final endpoints = config.amazonEnabled
        ? (config.amazonEndpoints.isNotEmpty
              ? config.amazonEndpoints
              : AmazonProvider.defaultEndpoints)
        : const <String>[];
    if (endpoints.isEmpty) {
      final sw = Stopwatch()..start();
      try {
        final res = await _dio.get('https://music.amazon.com');
        final ok = res.statusCode! < 500;
        return _result('amazon', false,
            ok ? ProviderHealthStatus.reachable : ProviderHealthStatus.offline,
            sw, ok
                ? 'Site reachable — Amazon not enabled'
                : 'Amazon HTTP ${res.statusCode}');
      } catch (e) {
        return _result('amazon', false, ProviderHealthStatus.offline, sw,
            'Amazon unreachable');
      }
    }
    final results = <ProviderHealthResult>[];
    for (var i = 0; i < endpoints.length; i++) {
      results.add(await _checkAmazon(endpoints[i], i + 1));
    }
    return _aggregate('amazon', results);
  }

  Future<ProviderHealthResult> _checkInstagramSource(
    StreamRouteConfig config,
  ) async {
    final sw = Stopwatch()..start();
    if (config.instagramCookie.isEmpty) {
      return _result('instagram', false, ProviderHealthStatus.offline, sw,
          'No Instagram session cookie configured');
    }
    try {
      final res = await _dio.get(
        'https://www.instagram.com/',
        options: Options(
          headers: {
            'User-Agent': _userAgent,
            'Cookie': config.instagramCookie,
          },
        ),
      );
      if (res.statusCode == 200) {
        return _result('instagram', true, ProviderHealthStatus.online, sw,
            'Authenticated session OK');
      }
      return _result('instagram', true, ProviderHealthStatus.offline, sw,
          'HTTP ${res.statusCode}');
    } catch (e) {
      return _result('instagram', true, ProviderHealthStatus.offline, sw,
          'Unreachable: ${e.runtimeType}');
    }
  }

  // ---- Individual resolver probes ---------------------------------------

  Future<ProviderHealthResult> _checkQobuz(String base, int index) async {
    final stopwatch = Stopwatch()..start();
    try {
      final items = await _qobuz.searchTracks(base, _qobuzProbeQuery, 'US');
      final downloadable = items.firstWhere(
        (item) => item['downloadable'] == true || item['streamable'] == true,
        orElse: () => const {},
      );
      final trackId = downloadable['id']?.toString();
      if (trackId == null || trackId.isEmpty) {
        return _result('qobuz', true, ProviderHealthStatus.reachable, stopwatch,
            'Search answered but no downloadable track',
            name: 'Qobuz Resolver $index', endpoint: base);
      }
      final data = await _qobuz.requestStream(base, trackId, 5);
      final url = data['url'];
      if (url is String && url.isNotEmpty) {
        return _result('qobuz', true, ProviderHealthStatus.online, stopwatch,
            'Search and stream OK',
            name: 'Qobuz Resolver $index', endpoint: base);
      }
      return _result('qobuz', true, ProviderHealthStatus.reachable, stopwatch,
          'Stream response missing URL',
          name: 'Qobuz Resolver $index', endpoint: base);
    } on DioException catch (e) {
      return _result('qobuz', true, ProviderHealthStatus.offline, stopwatch,
          'Unreachable: ${e.message ?? 'HTTP error'}',
          name: 'Qobuz Resolver $index', endpoint: base);
    } on QobuzApiException catch (e) {
      return _result('qobuz', true, ProviderHealthStatus.reachable, stopwatch,
          'Answered but rejected: ${e.message}',
          name: 'Qobuz Resolver $index', endpoint: base);
    } catch (e) {
      return _result('qobuz', true, ProviderHealthStatus.offline, stopwatch,
          'Error: ${e.runtimeType}',
          name: 'Qobuz Resolver $index', endpoint: base);
    }
  }

  Future<ProviderHealthResult> _checkTidal(String base, int index) async {
    final stopwatch = Stopwatch()..start();
    try {
      final data =
          await _tidal.requestStream(base, _tidalProbeTrackId, 'LOSSLESS');
      final manifest = data['manifest'];
      if (manifest is String && manifest.isNotEmpty) {
        return _result('tidal', true, ProviderHealthStatus.online, stopwatch,
            'Stream manifest OK',
            name: 'Tidal Endpoint $index', endpoint: base);
      }
      return _result('tidal', true, ProviderHealthStatus.reachable, stopwatch,
          'Answered but no manifest',
          name: 'Tidal Endpoint $index', endpoint: base);
    } on TidalApiException catch (e) {
      final status = switch (e.statusCode) {
        null => ProviderHealthStatus.offline,
        429 => ProviderHealthStatus.reachable,
        _ when e.statusCode! >= 400 && e.statusCode! < 500 =>
          ProviderHealthStatus.reachable,
        _ => ProviderHealthStatus.offline,
      };
      return _result('tidal', true, status, stopwatch, e.message,
          name: 'Tidal Endpoint $index', endpoint: base);
    } catch (e) {
      return _result('tidal', true, ProviderHealthStatus.offline, stopwatch,
          'Error: ${e.runtimeType}',
          name: 'Tidal Endpoint $index', endpoint: base);
    }
  }

  Future<ProviderHealthResult> _checkDeezer(String base, int index) async {
    final sw = Stopwatch()..start();
    try {
      var url = base.trim();
      if (!url.endsWith('/get_url')) {
        url = url.replaceAll(RegExp(r'/+$'), '') + '/get_url';
      }
      final res = await _dio.post(
        url,
        data: {
          'formats': ['MP3_128'],
          'ids': [_deezerProbeTrackId],
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': _userAgent,
          },
        ),
      );
      if (res.statusCode == 200) {
        final json = res.data;
        Object? media;
        if (json is Map) {
          final data = json['data'];
          if (data is List && data.isNotEmpty) {
            final first = data[0];
            if (first is Map) media = first['media'];
          }
        }
        if (media is List && media.isNotEmpty) {
          return _result('deezer', true, ProviderHealthStatus.online, sw,
              'Stream available',
              name: 'Deezer Resolver $index', endpoint: base);
        }
        return _result('deezer', true, ProviderHealthStatus.reachable, sw,
            'Answered but no stream',
            name: 'Deezer Resolver $index', endpoint: base);
      }
      return _result('deezer', true, ProviderHealthStatus.reachable, sw,
          'HTTP ${res.statusCode}',
          name: 'Deezer Resolver $index', endpoint: base);
    } on DioException catch (e) {
      return _result('deezer', true, ProviderHealthStatus.offline, sw,
          'Unreachable: ${e.message ?? e.type}',
          name: 'Deezer Resolver $index', endpoint: base);
    } catch (e) {
      return _result('deezer', true, ProviderHealthStatus.offline, sw,
          'Error: ${e.runtimeType}',
          name: 'Deezer Resolver $index', endpoint: base);
    }
  }

  Future<ProviderHealthResult> _checkApple(String base, int index) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse(base).replace(queryParameters: {
        'isrc': _appleProbeIsrc,
      });
      final res = await _dio.getUri(
        uri,
        options: Options(headers: {
          'Accept': 'application/json',
          'User-Agent': _userAgent,
        }),
      );
      if (res.statusCode == 200) {
        final json = res.data;
        final url = json is Map
            ? (json['url'] ?? json['streamUrl'] ?? json['mediaUri'])
            : json is String
                ? json
                : null;
        if (url is String && url.isNotEmpty) {
          return _result('apple', true, ProviderHealthStatus.online, sw,
              'Stream available',
              name: 'Apple Resolver $index', endpoint: base);
        }
        return _result('apple', true, ProviderHealthStatus.reachable, sw,
            'Answered but no stream URL',
            name: 'Apple Resolver $index', endpoint: base);
      }
      return _result('apple', true, ProviderHealthStatus.reachable, sw,
          'HTTP ${res.statusCode}',
          name: 'Apple Resolver $index', endpoint: base);
    } on DioException catch (e) {
      return _result('apple', true, ProviderHealthStatus.offline, sw,
          'Unreachable: ${e.message ?? e.type}',
          name: 'Apple Resolver $index', endpoint: base);
    } catch (e) {
      return _result('apple', true, ProviderHealthStatus.offline, sw,
          'Error: ${e.runtimeType}',
          name: 'Apple Resolver $index', endpoint: base);
    }
  }

  Future<ProviderHealthResult> _checkAmazon(String base, int index) async {
    final sw = Stopwatch()..start();
    try {
      final uri = Uri.parse(base).replace(queryParameters: {
        'asin': _amazonProbeAsin,
        'country': 'US',
        'codec': 'flac',
      });
      final res = await _dio.getUri(
        uri,
        options: Options(headers: {
          'Accept': 'application/json',
          'Origin': 'https://t2tunes.site',
          'Referer': 'https://t2tunes.site/',
          'User-Agent': _userAgent,
        }),
      );
      if (res.statusCode == 200) {
        final url = _deepFindUrl(res.data);
        if (url != null) {
          return _result('amazon', true, ProviderHealthStatus.online, sw,
              'Stream available',
              name: 'Amazon Resolver $index', endpoint: base);
        }
        return _result('amazon', true, ProviderHealthStatus.reachable, sw,
            'Answered but no stream URL',
            name: 'Amazon Resolver $index', endpoint: base);
      }
      return _result('amazon', true, ProviderHealthStatus.reachable, sw,
          'HTTP ${res.statusCode}',
          name: 'Amazon Resolver $index', endpoint: base);
    } on DioException catch (e) {
      return _result('amazon', true, ProviderHealthStatus.offline, sw,
          'Unreachable: ${e.message ?? e.type}',
          name: 'Amazon Resolver $index', endpoint: base);
    } catch (e) {
      return _result('amazon', true, ProviderHealthStatus.offline, sw,
          'Error: ${e.runtimeType}',
          name: 'Amazon Resolver $index', endpoint: base);
    }
  }

  /// Walks a resolver JSON payload looking for a playable URL.
  String? _deepFindUrl(dynamic node) {
    if (node is Map) {
      for (final key in const ['url', 'streamUrl', 'mediaUri']) {
        final v = node[key];
        if (v is String && v.isNotEmpty) return v;
      }
      for (final v in node.values) {
        final found = _deepFindUrl(v);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final v in node) {
        final found = _deepFindUrl(v);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Combines several resolver probes for one source into a single result.
  ProviderHealthResult _aggregate(
    String sourceId,
    List<ProviderHealthResult> results,
  ) {
    var best = results.first;
    for (final r in results) {
      if (_rank(r.status) >= _rank(best.status)) best = r;
    }
    final online =
        results.where((r) => r.status == ProviderHealthStatus.online).length;
    final reachable =
        results.where((r) => r.status == ProviderHealthStatus.reachable).length;
    final offline =
        results.where((r) => r.status == ProviderHealthStatus.offline).length;
    return ProviderHealthResult(
      sourceId: sourceId,
      name: sourceNames[sourceId] ?? sourceId,
      endpoint: sourceId,
      configured: true,
      status: best.status,
      message:
          '${results.length} resolver(s): $online OK, $reachable reachable, $offline offline',
      latencyMs: best.latencyMs,
    );
  }

  static int _rank(ProviderHealthStatus status) => switch (status) {
        ProviderHealthStatus.online => 2,
        ProviderHealthStatus.reachable => 1,
        ProviderHealthStatus.offline => 0,
      };

  ProviderHealthResult _result(
    String sourceId,
    bool configured,
    ProviderHealthStatus status,
    Stopwatch stopwatch,
    String message, {
    String name = '',
    String endpoint = '',
  }) {
    stopwatch.stop();
    return ProviderHealthResult(
      sourceId: sourceId,
      name: name.isEmpty ? (sourceNames[sourceId] ?? sourceId) : name,
      endpoint: endpoint,
      configured: configured,
      status: status,
      latencyMs: stopwatch.elapsedMilliseconds,
      message: message,
    );
  }
}

/// Runtime metrics for one provider during actual resolution attempts.
class RuntimeProviderMetrics {
  RuntimeProviderMetrics(this.providerId);

  final ProviderId providerId;

  int successes = 0;
  int failures = 0;
  int timeouts = 0;
  int matchRejections = 0;
  int totalLatencyMs = 0;
  int requestsCount = 0;
  int consecutiveFailures = 0;

  DateTime? lastSuccessAt;
  DateTime? lastFailureAt;
  DateTime? circuitBreakerCooldownUntil;

  /// Whether the circuit breaker is currently open (provider temporarily disabled).
  bool get isCircuitOpen {
    final cooldown = circuitBreakerCooldownUntil;
    if (cooldown == null) return false;
    if (DateTime.now().isAfter(cooldown)) {
      // Cooldown expired, half-open
      circuitBreakerCooldownUntil = null;
      return false;
    }
    return true;
  }

  /// Average resolution latency in ms.
  int get averageLatencyMs =>
      requestsCount > 0 ? (totalLatencyMs / requestsCount).round() : 0;

  /// Success rate between 0.0 and 1.0.
  double get successRate {
    final totalAttempts = successes + failures;
    if (totalAttempts == 0) return 1.0;
    return successes / totalAttempts;
  }
}

/// Global runtime health tracker for providers during playback & downloads.
class RuntimeHealthTracker {
  RuntimeHealthTracker._();

  static final RuntimeHealthTracker instance = RuntimeHealthTracker._();

  final Map<ProviderId, RuntimeProviderMetrics> _metrics = {};

  static const int _circuitBreakerThreshold = 3;
  static const Duration _cooldownDuration = Duration(seconds: 30);

  /// Retrieves metrics for [id], initializing if absent.
  RuntimeProviderMetrics getMetrics(ProviderId id) {
    return _metrics.putIfAbsent(id, () => RuntimeProviderMetrics(id));
  }

  /// Whether [id] is healthy enough to query right now.
  bool shouldAttempt(ProviderId id) {
    final m = _metrics[id];
    if (m == null) return true;
    return !m.isCircuitOpen;
  }

  bool isHealthy(ProviderId id) => shouldAttempt(id);

  /// Records a successful resolution from [id].
  void recordSuccess(ProviderId id, int latencyMs) {
    final m = getMetrics(id);
    m.successes++;
    m.requestsCount++;
    m.totalLatencyMs += latencyMs;
    m.consecutiveFailures = 0;
    m.circuitBreakerCooldownUntil = null;
    m.lastSuccessAt = DateTime.now();
  }

  /// Records a failure from [id].
  void recordFailure(ProviderId id, ProviderErrorKind kind, int? latencyMs) {
    final m = getMetrics(id);
    m.failures++;
    m.requestsCount++;
    if (latencyMs != null) m.totalLatencyMs += latencyMs;
    m.lastFailureAt = DateTime.now();

    if (kind == ProviderErrorKind.timeout) {
      m.timeouts++;
    }

    // Server errors, timeouts, network issues trip the circuit breaker
    if (kind == ProviderErrorKind.timeout ||
        kind == ProviderErrorKind.networkError ||
        kind == ProviderErrorKind.httpServerError) {
      m.consecutiveFailures++;
      if (m.consecutiveFailures >= _circuitBreakerThreshold) {
        m.circuitBreakerCooldownUntil = DateTime.now().add(_cooldownDuration);
      }
    }
  }

  /// Records that the provider answered successfully, but the track did not match.
  void recordMatchRejection(ProviderId id, int? latencyMs) {
    final m = getMetrics(id);
    m.matchRejections++;
    m.requestsCount++;
    if (latencyMs != null) m.totalLatencyMs += latencyMs;
  }

  /// Resets metrics for [id].
  void reset(ProviderId id) {
    _metrics.remove(id);
  }

  /// Resets all metrics.
  void resetAll() {
    _metrics.clear();
  }
}
