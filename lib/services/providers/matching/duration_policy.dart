/// Duration evaluation and tolerance policies for recording matching.
library;

import '../models/routing_policy.dart';

/// Classification of a track's duration relative to expected duration.
enum DurationStatus {
  /// Matches within the configured tolerance policy.
  exactOrClose,

  /// Acceptable difference (e.g. slight silence padding or fade out).
  acceptable,

  /// Significant difference that is likely a different edit/version.
  significantDifference,

  /// Detected as a preview / snippet (typically <= 30-90s on full song).
  probablePreview,

  /// Duration unknown or not supplied.
  unknown,
}

/// Detailed result of evaluating duration compatibility.
class DurationMatchResult {
  final bool isAcceptable;
  final DurationStatus status;
  final int? diffMs;
  final double? percentageDiff;
  final int scoreContribution;
  final String description;

  const DurationMatchResult({
    required this.isAcceptable,
    required this.status,
    this.diffMs,
    this.percentageDiff,
    required this.scoreContribution,
    required this.description,
  });

  /// Factory for when duration is missing on either side.
  factory DurationMatchResult.unknown() => const DurationMatchResult(
        isAcceptable: true,
        status: DurationStatus.unknown,
        scoreContribution: 0,
        description: 'Duration not available for comparison',
      );

  /// Factory for preview rejection.
  factory DurationMatchResult.preview(int expectedMs, int actualMs) =>
      DurationMatchResult(
        isAcceptable: false,
        status: DurationStatus.probablePreview,
        diffMs: actualMs - expectedMs,
        percentageDiff: (actualMs - expectedMs).abs() / expectedMs,
        scoreContribution: -1000,
        description:
            'Likely preview clip (${actualMs ~/ 1000}s vs expected ${expectedMs ~/ 1000}s)',
      );
}

/// Evaluates duration compatibility between expected and candidate duration.
DurationMatchResult evaluateDuration({
  required int? expectedMs,
  required int? candidateMs,
  DurationTolerancePolicy policy = DurationTolerancePolicy.standard,
  bool isLiveRecording = false,
  bool isrcExact = false,
}) {
  if (expectedMs == null || candidateMs == null || expectedMs <= 0 || candidateMs <= 0) {
    return DurationMatchResult.unknown();
  }

  final diffMs = candidateMs - expectedMs;
  final absDiffMs = diffMs.abs();
  final absDiffSec = (absDiffMs / 1000).round();
  final pctDiff = absDiffMs / expectedMs;

  // 1. Preview detection: If expected is > 60s and candidate is <= 35s or < 35% of length
  if (expectedMs >= 60000 && (candidateMs <= 35000 || candidateMs < expectedMs * 0.40)) {
    return DurationMatchResult.preview(expectedMs, candidateMs);
  }

  // 2. Exact ISRC bypass: If ISRC is exact, small metadata discrepancies are forgivable
  if (isrcExact) {
    if (absDiffSec <= 2) {
      return DurationMatchResult(
        isAcceptable: true,
        status: DurationStatus.exactOrClose,
        diffMs: diffMs,
        percentageDiff: pctDiff,
        scoreContribution: 160,
        description: 'Exact ISRC with matched duration (${absDiffSec}s diff)',
      );
    }
    return DurationMatchResult(
      isAcceptable: true,
      status: DurationStatus.acceptable,
      diffMs: diffMs,
      percentageDiff: pctDiff,
      scoreContribution: 100,
      description: 'Exact ISRC with slight duration diff (${absDiffSec}s diff)',
    );
  }

  // 3. Determine tolerance for this specific track
  final expectedSec = (expectedMs / 1000).round();
  final int allowedSec;
  if (isLiveRecording) {
    allowedSec = policy.liveTrackToleranceSec;
  } else if (expectedSec < 90) {
    allowedSec = policy.shortTrackToleranceSec;
  } else {
    allowedSec = policy.maxAbsoluteDiffSec;
  }

  final exceedsAbsolute = absDiffSec > allowedSec;
  final exceedsPercentage = pctDiff > policy.maxPercentageDiff;

  // Gate check: candidate must satisfy both absolute and percentage tolerance
  if (exceedsAbsolute || exceedsPercentage) {
    return DurationMatchResult(
      isAcceptable: false,
      status: DurationStatus.significantDifference,
      diffMs: diffMs,
      percentageDiff: pctDiff,
      scoreContribution: -500,
      description:
          'Duration mismatch: ${candidateMs ~/ 1000}s vs expected ${expectedSec}s '
          '(diff ${absDiffSec}s exceeds tolerance ${allowedSec}s)',
    );
  }

  // Plausibility scoring
  final int score;
  final DurationStatus status;
  if (absDiffSec <= 2) {
    score = 160;
    status = DurationStatus.exactOrClose;
  } else if (absDiffSec <= 5) {
    score = 100;
    status = DurationStatus.acceptable;
  } else if (absDiffSec <= 10) {
    score = 45;
    status = DurationStatus.acceptable;
  } else if (absDiffSec >= 30) {
    score = -120;
    status = DurationStatus.significantDifference;
  } else {
    score = 10;
    status = DurationStatus.acceptable;
  }

  return DurationMatchResult(
    isAcceptable: true,
    status: status,
    diffMs: diffMs,
    percentageDiff: pctDiff,
    scoreContribution: score,
    description: 'Duration agreement within ${absDiffSec}s',
  );
}

/// Sanity check for stream validation (replaces old isDurationMismatch helper).
bool isStreamDurationMismatched({
  required int? expectedMs,
  required int actualMs,
  required String providerId,
}) {
  if (expectedMs == null || expectedMs < 60000) return false;
  if (providerId.isEmpty ||
      providerId == 'youtube' ||
      providerId == 'youtube_music') {
    return false;
  }

  // Preview / snippet check
  if (actualMs <= 35000 && expectedMs >= 75000) return true;

  // More than 40% shorter with >= 20s gap
  return actualMs < (expectedMs * 0.60) && (expectedMs - actualMs) > 20000;
}
