import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/matching/duration_policy.dart';
import 'package:sonara/services/providers/models/routing_policy.dart';

void main() {
  group('DurationPolicy', () {
    test('exact duration gives highest score', () {
      final result = evaluateDuration(
        expectedMs: 200000,
        candidateMs: 200000,
      );
      expect(result.isAcceptable, isTrue);
      expect(result.status, DurationStatus.exactOrClose);
      expect(result.scoreContribution, 160);
    });

    test('preview clip (30s on 200s track) is detected and rejected', () {
      final result = evaluateDuration(
        expectedMs: 200000,
        candidateMs: 30000,
      );
      expect(result.isAcceptable, isFalse);
      expect(result.status, DurationStatus.probablePreview);
    });

    test('strict policy rejects 10s difference on standard track', () {
      final result = evaluateDuration(
        expectedMs: 200000,
        candidateMs: 190000,
        policy: DurationTolerancePolicy.strict,
      );
      expect(result.isAcceptable, isFalse);
    });

    test('live recording gets higher duration tolerance', () {
      final result = evaluateDuration(
        expectedMs: 200000,
        candidateMs: 215000,
        isLiveRecording: true,
      );
      expect(result.isAcceptable, isTrue);
    });

    test('isrc exact bypasses duration mismatch gate', () {
      final result = evaluateDuration(
        expectedMs: 200000,
        candidateMs: 100000,
        isrcExact: true,
      );
      expect(result.isAcceptable, isTrue);
    });

    test('isStreamDurationMismatched flags previews correctly', () {
      expect(
        isStreamDurationMismatched(
          expectedMs: 200000,
          actualMs: 30000,
          providerId: 'qobuz',
        ),
        isTrue,
      );
      expect(
        isStreamDurationMismatched(
          expectedMs: 200000,
          actualMs: 30000,
          providerId: 'youtube_music',
        ),
        isFalse, // YouTube is reference
      );
    });
  });
}
