/// Structured match decision — replaces raw integer scores with
/// explainable, tiered confidence judgments.
library;

/// Verification tier, from most to least confident.
enum VerificationLevel {
  /// Confirmed by ISRC + metadata agreement.
  verified,

  /// Strong metadata agreement (all primary signals match).
  highConfidence,

  /// Most signals match, minor discrepancies acceptable.
  likely,

  /// Some signals match but not enough for automatic acceptance.
  uncertain,

  /// Candidate is not the requested recording.
  rejected;

  /// Human-readable description.
  String get description => switch (this) {
        verified => 'Verified match',
        highConfidence => 'High confidence match',
        likely => 'Likely match',
        uncertain => 'Uncertain match',
        rejected => 'Rejected',
      };

  /// Whether this level is acceptable for automatic playback.
  bool get isAcceptable =>
      this == verified || this == highConfidence || this == likely;
}

/// The method used to establish the match.
enum MatchMethod {
  /// Exact ISRC match.
  isrcExact,

  /// Provider-specific track ID (e.g. manual override).
  providerTrackId,

  /// Fuzzy metadata matching (title + artist + album + duration).
  fuzzyMetadata,

  /// User manual override.
  manualOverride,

  /// Direct video ID (YouTube — same video, not a cross-catalog match).
  directVideoId,

  /// No match attempted (e.g. provider not configured).
  none,
}

/// A structured, explainable match decision that replaces raw integer scores.
class MatchDecision {
  /// Whether the candidate was accepted.
  final bool accepted;

  /// Confidence level (0.0 = no match, 1.0 = perfect match).
  final double confidence;

  /// The verification tier.
  final VerificationLevel verificationLevel;

  /// How the match was established.
  final MatchMethod matchMethod;

  /// Human-readable reasons for the decision.
  final List<String> reasons;

  /// Warnings that don't affect the decision but are worth noting.
  final List<String> warnings;

  /// Per-category score contributions for debugging.
  final Map<String, int> scoreBreakdown;

  /// Whether the ISRC matched exactly.
  final bool isrcMatch;

  /// Duration difference in milliseconds (positive = candidate longer).
  final int? durationDiffMs;

  /// Whether the version type is compatible.
  final bool versionCompatible;

  /// Whether the primary artist matched.
  final bool artistCompatible;

  /// Raw numeric score (for backward compat / sorting).
  final int rawScore;

  const MatchDecision({
    required this.accepted,
    this.confidence = 0.0,
    this.verificationLevel = VerificationLevel.rejected,
    this.matchMethod = MatchMethod.none,
    this.reasons = const [],
    this.warnings = const [],
    this.scoreBreakdown = const {},
    this.isrcMatch = false,
    this.durationDiffMs,
    this.versionCompatible = true,
    this.artistCompatible = true,
    this.rawScore = 0,
  });

  /// A rejected decision with a reason.
  factory MatchDecision.rejected(String reason, {
    Map<String, int> breakdown = const {},
    int rawScore = 0,
  }) =>
      MatchDecision(
        accepted: false,
        confidence: 0.0,
        verificationLevel: VerificationLevel.rejected,
        matchMethod: MatchMethod.none,
        reasons: [reason],
        rawScore: rawScore,
        scoreBreakdown: breakdown,
      );

  /// Builds a decision from scoring results.
  factory MatchDecision.fromScore({
    required int score,
    required bool isrcMatch,
    required Map<String, int> breakdown,
    required List<String> reasons,
    List<String> warnings = const [],
    int? durationDiffMs,
    bool versionCompatible = true,
    bool artistCompatible = true,
    MatchMethod method = MatchMethod.fuzzyMetadata,
    int rejectScore = -1000000,
    int minAcceptable = 260,
  }) {
    final accepted = score > rejectScore && (score >= minAcceptable || isrcMatch);

    // Map score to confidence (0.0 - 1.0).
    final confidence = accepted
        ? ((score.clamp(0, 2000)) / 2000.0).clamp(0.0, 1.0)
        : 0.0;

    // Map to verification level.
    final VerificationLevel level;
    if (!accepted) {
      level = VerificationLevel.rejected;
    } else if (isrcMatch && confidence >= 0.6) {
      level = VerificationLevel.verified;
    } else if (confidence >= 0.5) {
      level = VerificationLevel.highConfidence;
    } else if (confidence >= 0.3) {
      level = VerificationLevel.likely;
    } else {
      level = VerificationLevel.uncertain;
    }

    return MatchDecision(
      accepted: accepted,
      confidence: confidence,
      verificationLevel: level,
      matchMethod: isrcMatch ? MatchMethod.isrcExact : method,
      reasons: reasons,
      warnings: warnings,
      scoreBreakdown: breakdown,
      isrcMatch: isrcMatch,
      durationDiffMs: durationDiffMs,
      versionCompatible: versionCompatible,
      artistCompatible: artistCompatible,
      rawScore: score,
    );
  }

  /// Human-readable explanation for the "Why this source?" UI.
  String get explanation {
    final lines = <String>[];
    for (final reason in reasons) {
      lines.add('✓ $reason');
    }
    for (final warning in warnings) {
      lines.add('⚠ $warning');
    }
    return lines.join('\n');
  }

  /// Short summary for display (e.g. "Verified · 95%").
  String get summary {
    final pct = (confidence * 100).round();
    return '${verificationLevel.description} · $pct%';
  }

  @override
  String toString() =>
      'MatchDecision(${accepted ? "ACCEPTED" : "REJECTED"}, '
      '${verificationLevel.name}, ${(confidence * 100).round()}%, '
      'score=$rawScore)';
}
