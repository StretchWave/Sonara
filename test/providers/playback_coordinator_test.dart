import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/models/provider_error.dart';
import 'package:sonara/services/providers/models/provider_id.dart';
import 'package:sonara/services/providers/playback_coordinator.dart';
import 'package:sonara/services/providers/retry_policy.dart';
import 'package:sonara/services/providers/stream_validator.dart';
import 'package:sonara/services/providers/resolved_stream.dart';
import 'package:sonara/services/stream_service.dart';

void main() {
  group('PlaybackCoordinator cancellation tokens', () {
    test('superseded request IDs are detected as inactive', () {
      final coordinator = PlaybackCoordinator();
      final id1 = coordinator.newRequest();
      expect(coordinator.isActive(id1), isTrue);

      final id2 = coordinator.newRequest();
      expect(coordinator.isActive(id1), isFalse);
      expect(coordinator.isActive(id2), isTrue);
    });
  });

  group('StreamValidator', () {
    test('validates playable stream with http url', () {
      final stream = ResolvedStream(
        playable: true,
        providerId: 'qobuz',
        audioFormats: [
          Audio(
            itag: 251,
            audioCodec: Codec.flac,
            bitrate: 1000000,
            duration: 200000,
            loudnessDb: 0.0,
            url: 'https://audio.example/stream.flac',
            size: 20000000,
          ),
        ],
      );
      final result = StreamValidator.validate(stream);
      expect(result.isValid, isTrue);
    });

    test('rejects unplayable or empty streams', () {
      const stream = ResolvedStream(
        playable: false,
        statusMSG: 'Not found',
        audioFormats: [],
      );
      final result = StreamValidator.validate(stream);
      expect(result.isValid, isFalse);
    });

    test('detects preview clip on long track', () {
      final stream = ResolvedStream(
        playable: true,
        providerId: 'qobuz',
        audioFormats: [
          Audio(
            itag: 140,
            audioCodec: Codec.mp4a,
            bitrate: 128000,
            duration: 30000,
            loudnessDb: 0.0,
            url: 'https://audio.example/preview.mp3',
            size: 500000,
          ),
        ],
      );
      final result = StreamValidator.validate(stream, expectedDurationMs: 200000);
      expect(result.isValid, isFalse);
      expect(result.isPreview, isTrue);
    });
  });

  group('RetryPolicy', () {
    test('retries transient network errors up to limit', () {
      final policy = RetryPolicy(maxRetriesPerProvider: 1, maxTotalRetries: 2);
      const err = ProviderError(
        kind: ProviderErrorKind.networkError,
        message: 'Timeout',
      );

      final d1 = policy.decide(ProviderId.qobuz, err);
      expect(d1.action, RetryAction.retrySameProvider);

      // Second attempt on same provider falls back
      final d2 = policy.decide(ProviderId.qobuz, err);
      expect(d2.action, RetryAction.fallbackToNextProvider);
    });
  });
}
