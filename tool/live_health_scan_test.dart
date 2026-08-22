// Live scan of every audio source using the real ProviderHealthChecker.
// Run with:  flutter test tool/live_health_scan_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/provider_health.dart';
import 'package:sonara/services/providers/stream_route_config.dart';

class _AllowAllHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  HttpOverrides.global = _AllowAllHttpOverrides();

  test('live source availability scan', () async {
    // No resolvers configured in the test harness; this still exercises the
    // always-on source probes and the catalog-availability checks.
    const config = StreamRouteConfig();
    final results = await ProviderHealthChecker().checkSources(config);
    for (final r in results) {
      print('${r.sourceId.padRight(14)} '
          '${r.status.name.padRight(9)} '
          'configured=${r.configured} '
          '${(r.latencyMs ?? 0).toString().padLeft(4)}ms  ${r.message}');
    }
    expect(results.length, 8);
  });
}
