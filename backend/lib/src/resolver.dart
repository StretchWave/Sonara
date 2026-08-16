import 'cache.dart';
import 'models.dart';
import 'providers/playlist_provider.dart';

/// Runs the metadata provider chain: cache first, then the configured
/// external sources, and stops as soon as one returns a complete result.
///
/// Concurrent requests for the same playlist are coalesced into a single
/// external resolution (ten users asking at once = one upstream request).
class PlaylistResolver {
  final List<PlaylistMetadataProvider> providers;
  final ResolutionCache cache;

  final Map<String, Future<PlaylistResolution>> _inFlight = {};

  PlaylistResolver({required this.providers, required this.cache});

  /// Resolves a playlist. [refresh] bypasses the cache (and the cached
  /// provider) while still re-writing the cache with the fresh result.
  ///
  /// Cached data is served by the first provider in the chain (which marks
  /// the result `cached: true`); concurrent identical requests are
  /// coalesced into a single upstream resolution.
  Future<PlaylistResolution> resolve(PlaylistResolveInput input,
      {bool refresh = false}) async {
    final key = cache.keyFor(input.playlistId);
    if (!refresh) {
      final inFlight = _inFlight[key];
      if (inFlight != null) return inFlight;
    }

    final future = _resolveFresh(input, refresh);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<PlaylistResolution> _resolveFresh(
      PlaylistResolveInput input, bool refresh) async {
    ResolveError? lastError;
    for (final provider in providers) {
      // On refresh the cache provider is skipped (its canResolve would
      // still hit, but we want a fresh upstream result).
      if (refresh && provider.id == 'cache') continue;
      if (!provider.canResolve(input)) continue;
      try {
        final result = await provider.resolve(input);
        if (result.tracks.isNotEmpty || provider.id == 'cache') {
          cache.put(cache.keyFor(input.playlistId), result);
        }
        return result;
      } on ResolveError catch (e) {
        lastError = e;
        // Chain continues: the next provider may still succeed.
      }
    }
    if (lastError != null) throw lastError;
    throw const ResolveError(
        ResolveErrorCode.noMetadataSource,
        'No metadata source could resolve this playlist');
  }
}
