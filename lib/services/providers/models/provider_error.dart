/// Structured provider errors — replaces generic exceptions with typed
/// errors that inform retry/recovery decisions.
library;

import 'dart:async';

/// Error category for routing decisions.
enum ProviderErrorKind {
  timeout,
  networkError,
  httpForbidden,
  httpNotFound,
  httpRateLimited,
  httpServerError,
  authenticationFailure,
  regionUnavailable,
  noMatch,
  invalidStream,
  expiredUrl,
  malformedResponse,
  unsupportedOperation,
  previewOnly,
  unknown,
}

/// A structured error from a provider, carrying enough information
/// to decide whether to retry, skip, or surface to the user.
class ProviderError implements Exception {
  /// The kind of error.
  final ProviderErrorKind kind;

  /// Human-readable message (safe for logs, may not be for end users).
  final String message;

  /// Provider that produced this error.
  final String providerId;

  /// HTTP status code, when applicable.
  final int? statusCode;

  /// The underlying exception, if any.
  final Object? cause;

  const ProviderError({
    required this.kind,
    required this.message,
    this.providerId = '',
    this.statusCode,
    this.cause,
  });

  // ---------------------------------------------------------------------------
  // Factory constructors for common errors
  // ---------------------------------------------------------------------------

  factory ProviderError.timeout(String providerId, [Duration? duration]) =>
      ProviderError(
        kind: ProviderErrorKind.timeout,
        message: duration != null
            ? 'Request timed out after ${duration.inSeconds}s'
            : 'Request timed out',
        providerId: providerId,
      );

  factory ProviderError.network(String providerId, [Object? cause]) =>
      ProviderError(
        kind: ProviderErrorKind.networkError,
        message: 'Network error',
        providerId: providerId,
        cause: cause,
      );

  factory ProviderError.http(String providerId, int statusCode,
          [String? body]) =>
      ProviderError(
        kind: _kindForStatus(statusCode),
        message: 'HTTP $statusCode${body != null ? ': $body' : ''}',
        providerId: providerId,
        statusCode: statusCode,
      );

  factory ProviderError.noMatch(String providerId, [String? detail]) =>
      ProviderError(
        kind: ProviderErrorKind.noMatch,
        message: detail ?? 'No matching track found',
        providerId: providerId,
      );

  factory ProviderError.expiredUrl(String providerId) => ProviderError(
        kind: ProviderErrorKind.expiredUrl,
        message: 'Stream URL has expired',
        providerId: providerId,
      );

  factory ProviderError.invalidStream(String providerId, [String? detail]) =>
      ProviderError(
        kind: ProviderErrorKind.invalidStream,
        message: detail ?? 'Invalid or unplayable stream',
        providerId: providerId,
      );

  factory ProviderError.auth(String providerId, [String? detail]) =>
      ProviderError(
        kind: ProviderErrorKind.authenticationFailure,
        message: detail ?? 'Authentication required',
        providerId: providerId,
      );

  factory ProviderError.regionUnavailable(String providerId,
          [String? region]) =>
      ProviderError(
        kind: ProviderErrorKind.regionUnavailable,
        message: region != null
            ? 'Unavailable in $region'
            : 'Unavailable in your region',
        providerId: providerId,
      );

  factory ProviderError.malformedResponse(String providerId, [Object? cause]) =>
      ProviderError(
        kind: ProviderErrorKind.malformedResponse,
        message: 'Malformed response from provider',
        providerId: providerId,
        cause: cause,
      );

  factory ProviderError.previewOnly(String providerId) => ProviderError(
        kind: ProviderErrorKind.previewOnly,
        message: 'Only a preview is available (not the full track)',
        providerId: providerId,
      );

  factory ProviderError.unknown(String providerId, [Object? cause]) =>
      ProviderError(
        kind: ProviderErrorKind.unknown,
        message: cause?.toString() ?? 'Unknown provider error',
        providerId: providerId,
        cause: cause,
      );

  factory ProviderError.fromException(String providerId, Object error) {
    if (error is ProviderError) return error;
    if (error is TimeoutException) {
      return ProviderError.timeout(providerId);
    }
    return ProviderError.unknown(providerId, error);
  }

  // ---------------------------------------------------------------------------
  // Recovery policy
  // ---------------------------------------------------------------------------

  /// Whether this error is worth retrying (e.g. timeout, network blip).
  bool get isRetryable => switch (kind) {
        ProviderErrorKind.timeout => true,
        ProviderErrorKind.networkError => true,
        ProviderErrorKind.httpServerError => true,
        ProviderErrorKind.expiredUrl => true,
        _ => false,
      };

  /// Whether this error should cause the provider to be skipped entirely
  /// for the current request (move to next provider).
  bool get shouldSkipProvider => switch (kind) {
        ProviderErrorKind.httpForbidden => true,
        ProviderErrorKind.httpNotFound => true,
        ProviderErrorKind.authenticationFailure => true,
        ProviderErrorKind.regionUnavailable => true,
        ProviderErrorKind.noMatch => true,
        ProviderErrorKind.invalidStream => true,
        ProviderErrorKind.previewOnly => true,
        ProviderErrorKind.unsupportedOperation => true,
        _ => false,
      };

  /// Whether this error indicates the user should refresh authentication.
  bool get shouldRefreshAuth =>
      kind == ProviderErrorKind.authenticationFailure ||
      (kind == ProviderErrorKind.httpForbidden && statusCode == 401);

  /// Whether this error indicates rate limiting (should back off).
  bool get isRateLimited =>
      kind == ProviderErrorKind.httpRateLimited ||
      (statusCode != null && statusCode == 429);

  /// User-facing error message (safe for display).
  String get userMessage => switch (kind) {
        ProviderErrorKind.timeout => 'Provider took too long to respond',
        ProviderErrorKind.networkError => 'Network error — check your connection',
        ProviderErrorKind.httpForbidden => 'Access denied by provider',
        ProviderErrorKind.httpNotFound => 'Track not found on this provider',
        ProviderErrorKind.httpRateLimited =>
          'Too many requests — try again shortly',
        ProviderErrorKind.httpServerError =>
          'Provider is experiencing issues',
        ProviderErrorKind.authenticationFailure =>
          'Authentication required — check provider settings',
        ProviderErrorKind.regionUnavailable => message,
        ProviderErrorKind.noMatch => 'No verified match found',
        ProviderErrorKind.invalidStream => 'Stream is not playable',
        ProviderErrorKind.expiredUrl => 'Stream URL has expired',
        ProviderErrorKind.malformedResponse =>
          'Unexpected response from provider',
        ProviderErrorKind.unsupportedOperation =>
          'Operation not supported by this provider',
        ProviderErrorKind.previewOnly => 'Only a preview is available',
        ProviderErrorKind.unknown => 'An unexpected error occurred',
      };

  static ProviderErrorKind _kindForStatus(int statusCode) => switch (statusCode) {
        401 || 403 => ProviderErrorKind.httpForbidden,
        404 => ProviderErrorKind.httpNotFound,
        429 => ProviderErrorKind.httpRateLimited,
        _ when statusCode >= 500 => ProviderErrorKind.httpServerError,
        _ => ProviderErrorKind.unknown,
      };

  @override
  String toString() => 'ProviderError($kind, $providerId: $message)';
}
