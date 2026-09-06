/// Result from a provider resolution attempt, combining the stream,
/// match decision, performance metrics, and any errors.
library;

import '../resolved_stream.dart';
import 'match_decision.dart';
import 'provider_error.dart';

/// A complete result from one provider's attempt to resolve a recording.
class ProviderResult {
  /// Stable provider identifier.
  final String providerId;

  /// The resolved stream, when successful.
  final ResolvedStream? stream;

  /// The match decision explaining why this candidate was accepted/rejected.
  final MatchDecision matchDecision;

  /// Resolution latency in milliseconds.
  final int? latencyMs;

  /// Error details, when the provider failed.
  final ProviderError? error;

  /// Number of candidates examined during matching.
  final int candidatesExamined;

  const ProviderResult({
    required this.providerId,
    this.stream,
    this.matchDecision = const MatchDecision(accepted: false),
    this.latencyMs,
    this.error,
    this.candidatesExamined = 0,
  });

  /// Whether this result has a playable, verified stream.
  bool get isPlayable =>
      stream != null && stream!.playable && matchDecision.accepted;

  /// Whether this result failed with an error.
  bool get isError => error != null;

  /// Whether the match was rejected (not an error, just not the right track).
  bool get isRejected =>
      !isPlayable && !isError && !matchDecision.accepted;

  /// Creates a successful result.
  factory ProviderResult.success({
    required String providerId,
    required ResolvedStream stream,
    required MatchDecision matchDecision,
    int? latencyMs,
    int candidatesExamined = 0,
  }) =>
      ProviderResult(
        providerId: providerId,
        stream: stream,
        matchDecision: matchDecision,
        latencyMs: latencyMs,
        candidatesExamined: candidatesExamined,
      );

  /// Creates a failure result.
  factory ProviderResult.failure({
    required String providerId,
    required ProviderError error,
    int? latencyMs,
  }) =>
      ProviderResult(
        providerId: providerId,
        error: error,
        latencyMs: latencyMs,
      );

  /// Creates a rejected result (provider answered but match failed).
  factory ProviderResult.rejected({
    required String providerId,
    required MatchDecision matchDecision,
    int? latencyMs,
    int candidatesExamined = 0,
  }) =>
      ProviderResult(
        providerId: providerId,
        matchDecision: matchDecision,
        latencyMs: latencyMs,
        candidatesExamined: candidatesExamined,
      );

  @override
  String toString() {
    if (isPlayable) {
      return 'ProviderResult($providerId: PLAYABLE, '
          '${matchDecision.summary}, ${latencyMs}ms)';
    }
    if (isError) {
      return 'ProviderResult($providerId: ERROR, ${error!.kind})';
    }
    return 'ProviderResult($providerId: REJECTED, ${matchDecision.summary})';
  }
}
