import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/models/provider_error.dart';
import 'package:sonara/services/providers/models/provider_id.dart';
import 'package:sonara/services/providers/models/recording_identity.dart';
import 'package:sonara/services/providers/playback_coordinator.dart';
import 'package:sonara/services/providers/provider_health.dart';
import 'package:sonara/services/providers/resolved_stream.dart';
import 'package:sonara/services/providers/retry_policy.dart';
import 'package:sonara/services/providers/stream_validator.dart';
import 'package:sonara/services/stream_service.dart';

void main() {
  group('Failure Injection Tests', () {
    test('StreamValidator rejects 0-byte and empty stream URLs', () {
      final emptyUrlStream = ResolvedStream(
        playable: true,
        audioFormats: [
          Audio(
            itag: 140,
            audioCodec: Codec.mp4a,
            bitrate: 128000,
            duration: 200000,
            size: 0,
            loudnessDb: 0,
            url: '',
          ),
        ],
      );

      final result = StreamValidator.validate(emptyUrlStream);
      expect(result.isValid, isFalse);
      expect(result.failureReason, contains('URL is empty'));
    });

    test('StreamValidator rejects non-http/https schemes (e.g. file:// or ftp://)', () {
      final badSchemeStream = ResolvedStream(
        playable: true,
        audioFormats: [
          Audio(
            itag: 140,
            audioCodec: Codec.mp4a,
            bitrate: 128000,
            duration: 200000,
            size: 1000000,
            loudnessDb: 0,
            url: 'ftp://malicious.example.com/audio.mp3',
          ),
        ],
      );

      final result = StreamValidator.validate(badSchemeStream);
      expect(result.isValid, isFalse);
      expect(result.failureReason, contains('protocol'));
    });

    test('StreamValidator detects and rejects 30s preview clips when full length expected', () {
      final previewStream = ResolvedStream(
        playable: true,
        providerId: 'tidal',
        audioFormats: [
          Audio(
            itag: 140,
            audioCodec: Codec.mp4a,
            bitrate: 128000,
            duration: 30000, // 30s sample
            size: 500000,
            loudnessDb: 0,
            url: 'https://cdn.example.com/preview.mp3',
          ),
        ],
      );

      final result = StreamValidator.validate(
        previewStream,
        expectedDurationMs: 240000, // 4:00 song
      );
      expect(result.isValid, isFalse);
      expect(result.failureReason, contains('preview'));
    });

    test('Circuit breaker trips after consecutive failures and recovers on success', () {
      final tracker = RuntimeHealthTracker.instance;
      final pid = ProviderId.qobuz;

      // Successful state
      tracker.recordSuccess(pid, 100);
      expect(tracker.isHealthy(pid), isTrue);

      // Record 3 consecutive failures
      for (int i = 0; i < 3; i++) {
        tracker.recordFailure(pid, ProviderErrorKind.networkError, 100);
      }

      // Circuit breaker should trip
      expect(tracker.isHealthy(pid), isFalse);

      // Successful request resets consecutive errors and closes circuit
      tracker.recordSuccess(pid, 120);
      expect(tracker.isHealthy(pid), isTrue);
    });

    test('RetryPolicy handles retryable vs non-retryable errors correctly', () {
      final policy = RetryPolicy(
        maxRetriesPerProvider: 2,
        maxTotalRetries: 3,
      );

      final pid = ProviderId.tidal;

      // Network error is retryable
      final networkDecision = policy.decide(
        pid,
        ProviderError.network(pid.stableId, 'Timeout'),
      );
      expect(networkDecision.shouldRetry, isTrue);

      // Auth and not found errors are NOT retryable
      final authDecision = policy.decide(
        pid,
        ProviderError.auth(pid.stableId, 'Bad token'),
      );
      expect(authDecision.shouldRetry, isFalse);

      final notFoundDecision = policy.decide(
        pid,
        ProviderError(
          providerId: pid.stableId,
          kind: ProviderErrorKind.httpNotFound,
          message: 'Track not found',
        ),
      );
      expect(notFoundDecision.shouldRetry, isFalse);
    });

    test('Rapid superseding requests cancel previous in-flight resolutions', () async {
      final coordinator = PlaybackCoordinator();
      final req1 = coordinator.newRequest();
      final req2 = coordinator.newRequest();

      // req1 is immediately superseded by req2
      expect(coordinator.isActive(req1), isFalse);
      expect(coordinator.isActive(req2), isTrue);

      final identity = RecordingIdentity(
        mediaId: 'song-test-race',
        title: 'Test Song',
        primaryArtists: const ['Test Artist'],
        durationMs: 180000,
      );

      // Resolving req1 should yield cancelled
      final result = await coordinator.resolve(
        requestId: req1,
        identity: identity,
      );

      expect(result.wasCancelled, isTrue);
      expect(result.success, isFalse);
    });
  });
}
