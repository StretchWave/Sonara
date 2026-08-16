import 'package:dio/dio.dart';

import 'qobuz/qobuz_api.dart';
import 'stream_route_config.dart';
import 'tidal/tidal_api.dart';

/// Health status of a resolver probe.
enum ProviderHealthStatus { online, reachable, offline }

/// Result of probing one configured resolver instance/endpoint.
class ProviderHealthResult {
  const ProviderHealthResult({
    required this.name,
    required this.endpoint,
    required this.status,
    required this.message,
    this.latencyMs,
  });

  final String name;

  final String endpoint;

  final ProviderHealthStatus status;

  final String message;

  final int? latencyMs;
}

/// Probes each configured resolver with a real request so the user can see
/// at a glance which sources are working (mirrors MetroFuse's
/// ProviderHealthChecker).
class ProviderHealthChecker {
  ProviderHealthChecker({QobuzApi? qobuzApi, TidalApi? tidalApi})
      : _qobuz = qobuzApi ?? QobuzApi(),
        _tidal = tidalApi ?? TidalApi();

  final QobuzApi _qobuz;
  final TidalApi _tidal;

  static const String _qobuzProbeQuery = 'yes and ariana grande';
  static const String _tidalProbeTrackId = '4875683';

  /// Probes every configured Qobuz instance and Tidal endpoint.
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
        return _result(
          'Qobuz Resolver $index',
          base,
          ProviderHealthStatus.reachable,
          stopwatch,
          'Search answered but no downloadable track',
        );
      }
      final data = await _qobuz.requestStream(base, trackId, 5);
      final url = data['url'];
      if (url is String && url.isNotEmpty) {
        return _result(
          'Qobuz Resolver $index',
          base,
          ProviderHealthStatus.online,
          stopwatch,
          'Search and stream OK',
        );
      }
      return _result(
        'Qobuz Resolver $index',
        base,
        ProviderHealthStatus.reachable,
        stopwatch,
        'Stream response missing URL',
      );
    } on DioException catch (e) {
      return _result(
        'Qobuz Resolver $index',
        base,
        ProviderHealthStatus.offline,
        stopwatch,
        'Unreachable: ${e.message ?? 'HTTP error'}',
      );
    } on QobuzApiException catch (e) {
      return _result(
        'Qobuz Resolver $index',
        base,
        ProviderHealthStatus.reachable,
        stopwatch,
        'Answered but rejected: ${e.message}',
      );
    } catch (e) {
      return _result(
        'Qobuz Resolver $index',
        base,
        ProviderHealthStatus.offline,
        stopwatch,
        'Error: ${e.runtimeType}',
      );
    }
  }

  Future<ProviderHealthResult> _checkTidal(String base, int index) async {
    final stopwatch = Stopwatch()..start();
    try {
      final data = await _tidal.requestStream(base, _tidalProbeTrackId, 'LOSSLESS');
      final manifest = data['manifest'];
      if (manifest is String && manifest.isNotEmpty) {
        return _result(
          'Tidal Endpoint $index',
          base,
          ProviderHealthStatus.online,
          stopwatch,
          'Stream manifest OK',
        );
      }
      return _result(
        'Tidal Endpoint $index',
        base,
        ProviderHealthStatus.reachable,
        stopwatch,
        'Answered but no manifest',
      );
    } on TidalApiException catch (e) {
      final status = switch (e.statusCode) {
        null => ProviderHealthStatus.offline,
        429 => ProviderHealthStatus.reachable,
        _ when e.statusCode! >= 400 && e.statusCode! < 500 =>
          ProviderHealthStatus.reachable,
        _ => ProviderHealthStatus.offline,
      };
      return _result(
        'Tidal Endpoint $index',
        base,
        status,
        stopwatch,
        e.message,
      );
    } catch (e) {
      return _result(
        'Tidal Endpoint $index',
        base,
        ProviderHealthStatus.offline,
        stopwatch,
        'Error: ${e.runtimeType}',
      );
    }
  }

  ProviderHealthResult _result(
    String name,
    String endpoint,
    ProviderHealthStatus status,
    Stopwatch stopwatch,
    String message,
  ) {
    stopwatch.stop();
    return ProviderHealthResult(
      name: name,
      endpoint: endpoint,
      status: status,
      latencyMs: stopwatch.elapsedMilliseconds,
      message: message,
    );
  }
}
