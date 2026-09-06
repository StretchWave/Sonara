/// Retry policies and recovery strategies for provider resolution failures.
library;

import 'models/provider_error.dart';
import 'models/provider_id.dart';

/// Action the resolution orchestrator should take after an error.
enum RetryAction {
  /// Retry the same provider (e.g. after transient network glitch or expired URL).
  retrySameProvider,

  /// Skip to the next provider in the chain.
  fallbackToNextProvider,

  /// Give up immediately (e.g. cancelled request or fatal error).
  abort,
}

/// Decision from the retry policy.
class RetryDecision {
  final RetryAction action;
  final Duration delay;
  final String reason;

  const RetryDecision({
    required this.action,
    this.delay = Duration.zero,
    required this.reason,
  });

  factory RetryDecision.retry(String reason, [Duration delay = const Duration(milliseconds: 500)]) =>
      RetryDecision(
        action: RetryAction.retrySameProvider,
        delay: delay,
        reason: reason,
      );

  factory RetryDecision.next(String reason) => RetryDecision(
        action: RetryAction.fallbackToNextProvider,
        reason: reason,
      );

  factory RetryDecision.abort(String reason) => RetryDecision(
        action: RetryAction.abort,
        reason: reason,
      );

  bool get shouldRetry => action == RetryAction.retrySameProvider;
  bool get shouldFallback => action == RetryAction.fallbackToNextProvider;
  bool get shouldAbort => action == RetryAction.abort;
}

/// Tracks retry counts per request and determines next action.
class RetryPolicy {
  final int maxRetriesPerProvider;
  final int maxTotalRetries;

  RetryPolicy({
    this.maxRetriesPerProvider = 1,
    this.maxTotalRetries = 3,
  });

  static final RetryPolicy standard = RetryPolicy();

  final Map<ProviderId, int> _providerAttempts = {};
  int _totalRetries = 0;

  /// Determines what action to take when [error] occurs on [providerId].
  RetryDecision decide(ProviderId providerId, ProviderError error) {
    if (_totalRetries >= maxTotalRetries) {
      return RetryDecision.abort('Maximum total retries ($maxTotalRetries) reached');
    }

    final attempts = _providerAttempts[providerId] ?? 0;

    // If provider error is retryable and under limit, retry it
    if (error.isRetryable && attempts < maxRetriesPerProvider) {
      _providerAttempts[providerId] = attempts + 1;
      _totalRetries++;
      return RetryDecision.retry(
        'Transient ${error.kind.name} on ${providerId.displayName}, retrying (attempt ${attempts + 1})',
      );
    }

    // Otherwise fallback to next provider
    return RetryDecision.next(
      'Provider ${providerId.displayName} failed with ${error.kind.name}: moving to next source',
    );
  }

  /// Resets retry state for a new request.
  void reset() {
    _providerAttempts.clear();
    _totalRetries = 0;
  }
}
