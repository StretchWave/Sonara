import 'models.dart';
import 'providers/playlist_provider.dart';

class _CacheEntry {
  final PlaylistResolution resolution;
  final DateTime expiresAt;
  _CacheEntry(this.resolution, this.expiresAt);
}

/// Simple in-memory TTL cache keyed by `spotify:{playlistId}`.
///
/// Aggressive caching is what makes the public endpoint cheap to operate and
/// hard to abuse; a short TTL keeps playlists reasonably fresh.
class ResolutionCache {
  final Duration ttl;
  final DateTime Function() _now;
  final Map<String, _CacheEntry> _entries = {};

  ResolutionCache({this.ttl = const Duration(hours: 1), DateTime Function()? now})
      : _now = now ?? DateTime.now;

  String keyFor(String playlistId) => 'spotify:$playlistId';

  PlaylistResolution? get(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (_now().isAfter(entry.expiresAt)) {
      _entries.remove(key);
      return null;
    }
    return entry.resolution;
  }

  void put(String key, PlaylistResolution resolution) {
    _entries[key] = _CacheEntry(resolution, _now().add(ttl));
  }

  void invalidate(String playlistId) {
    _entries.remove(keyFor(playlistId));
  }

  int get length => _entries.length;
}

/// Provider that serves a previously resolved playlist from the cache.
/// First in the chain, so repeated requests never touch external APIs.
class CachedPlaylistProvider implements PlaylistMetadataProvider {
  final ResolutionCache cache;

  CachedPlaylistProvider(this.cache);

  @override
  String get id => 'cache';

  @override
  bool canResolve(PlaylistResolveInput input) =>
      cache.get(cache.keyFor(input.playlistId)) != null;

  @override
  Future<PlaylistResolution> resolve(PlaylistResolveInput input) async {
    final cached = cache.get(cache.keyFor(input.playlistId));
    if (cached == null) {
      throw const ResolveError(ResolveErrorCode.noMetadataSource, 'Cache miss');
    }
    // Mark as cached so callers can report it (and skip re-writing).
    return PlaylistResolution(
      playlist: cached.playlist,
      tracks: cached.tracks,
      source: cached.source,
      method: cached.method,
      cached: true,
      total: cached.total,
      resolved: cached.resolved,
      unavailable: cached.unavailable,
      warnings: cached.warnings,
    );
  }
}
