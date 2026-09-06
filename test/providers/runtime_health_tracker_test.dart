import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/models/provider_error.dart';
import 'package:sonara/services/providers/models/provider_id.dart';
import 'package:sonara/services/providers/provider_health.dart';

void main() {
  group('RuntimeHealthTracker', () {
    final tracker = RuntimeHealthTracker.instance;

    setUp(() {
      tracker.resetAll();
    });

    test('records successes and updates average latency', () {
      tracker.recordSuccess(ProviderId.qobuz, 100);
      tracker.recordSuccess(ProviderId.qobuz, 200);

      final metrics = tracker.getMetrics(ProviderId.qobuz);
      expect(metrics.successes, 2);
      expect(metrics.failures, 0);
      expect(metrics.averageLatencyMs, 150);
      expect(metrics.successRate, 1.0);
      expect(tracker.shouldAttempt(ProviderId.qobuz), isTrue);
    });

    test('circuit breaker trips after consecutive failures', () {
      tracker.recordFailure(ProviderId.tidal, ProviderErrorKind.timeout, 5000);
      tracker.recordFailure(ProviderId.tidal, ProviderErrorKind.networkError, 100);
      expect(tracker.shouldAttempt(ProviderId.tidal), isTrue);

      // 3rd consecutive failure trips breaker
      tracker.recordFailure(ProviderId.tidal, ProviderErrorKind.httpServerError, 200);
      expect(tracker.shouldAttempt(ProviderId.tidal), isFalse);
      expect(tracker.getMetrics(ProviderId.tidal).isCircuitOpen, isTrue);

      // Success resets circuit
      tracker.recordSuccess(ProviderId.tidal, 120);
      expect(tracker.shouldAttempt(ProviderId.tidal), isTrue);
      expect(tracker.getMetrics(ProviderId.tidal).isCircuitOpen, isFalse);
    });

    test('match rejections do not trip circuit breaker', () {
      tracker.recordMatchRejection(ProviderId.deezer, 150);
      tracker.recordMatchRejection(ProviderId.deezer, 150);
      tracker.recordMatchRejection(ProviderId.deezer, 150);
      tracker.recordMatchRejection(ProviderId.deezer, 150);

      expect(tracker.shouldAttempt(ProviderId.deezer), isTrue);
      expect(tracker.getMetrics(ProviderId.deezer).matchRejections, 4);
      expect(tracker.getMetrics(ProviderId.deezer).failures, 0);
    });
  });
}
