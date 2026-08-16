class _Window {
  int startedAt;
  int count;
  _Window(this.startedAt, this.count);
}

/// Fixed-window rate limiter, keyed by client IP (or any request key).
/// Returns 429 with Retry-After when the limit is exceeded.
class RateLimiter {
  final int maxRequests;
  final Duration window;
  final DateTime Function() _now;
  final Map<String, _Window> _windows = {};

  RateLimiter({
    this.maxRequests = 30,
    this.window = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// True when the request is allowed; otherwise the caller should answer
  /// 429 with [retryAfterSeconds].
  bool allow(String key) {
    _prune();
    final nowMs = _now().millisecondsSinceEpoch;
    final w = _windows[key];
    if (w == null) {
      _windows[key] = _Window(nowMs, 1);
      return true;
    }
    if (nowMs - w.startedAt >= window.inMilliseconds) {
      w.startedAt = nowMs;
      w.count = 1;
      return true;
    }
    w.count++;
    return w.count <= maxRequests;
  }

  int retryAfterSeconds(String key) {
    final w = _windows[key];
    if (w == null) return 1;
    final remaining = window.inMilliseconds - (_now().millisecondsSinceEpoch - w.startedAt);
    return (remaining / 1000).ceil().clamp(1, 3600);
  }

  void _prune() {
    if (_windows.length < 1000) return;
    final nowMs = _now().millisecondsSinceEpoch;
    _windows.removeWhere((_, w) => nowMs - w.startedAt >= window.inMilliseconds);
  }
}
