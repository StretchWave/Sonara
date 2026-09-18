/// Provider-aware stream cache with explicit TTL, expiry validation,
/// and schema versioning.
library;

import 'package:hive/hive.dart';

import '../../utils.dart' as utils;

/// Metadata stored alongside a cached stream payload.
class CachedStreamEntry {
  final Map<String, dynamic> data;
  final String providerId;
  final int cachedAtMs;
  final int expiresAtMs;
  final int schemaVersion;

  const CachedStreamEntry({
    required this.data,
    required this.providerId,
    required this.cachedAtMs,
    required this.expiresAtMs,
    this.schemaVersion = StreamCache.currentSchemaVersion,
  });

  bool get isExpired {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= expiresAtMs) return true;

    // Additional URL-level check for YouTube signed URLs
    final lowQuality = data['lowQualityAudio'];
    if (lowQuality is Map && lowQuality['url'] is String) {
      final url = lowQuality['url'] as String;
      if (url.contains('expire=')) {
        return utils.isExpired(url: url);
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'data': data,
        'providerId': providerId,
        'cachedAtMs': cachedAtMs,
        'expiresAtMs': expiresAtMs,
        'schemaVersion': schemaVersion,
      };

  factory CachedStreamEntry.fromJson(Map<dynamic, dynamic> json) {
    final rawData = json['data'];
    final dataMap = rawData is Map
        ? rawData.map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};

    return CachedStreamEntry(
      data: dataMap,
      providerId: json['providerId']?.toString() ?? '',
      cachedAtMs: json['cachedAtMs'] is int
          ? json['cachedAtMs'] as int
          : DateTime.now().millisecondsSinceEpoch,
      expiresAtMs: json['expiresAtMs'] is int
          ? json['expiresAtMs'] as int
          : DateTime.now().millisecondsSinceEpoch +
              StreamCache.defaultStreamTtlMs,
      schemaVersion: json['schemaVersion'] is int
          ? json['schemaVersion'] as int
          : 1,
    );
  }
}

/// Provider-aware cache manager for stream URLs.
///
/// Keys are formatted as `{mediaId}::{providerId}::{qualityIndex}` so forcing
/// a provider or changing quality never returns stale or wrong-provider URLs.
class StreamCache {
  StreamCache({Box? box}) : _box = box;

  final Box? _box;

  Box get box => _box ?? Hive.box('SongsUrlCache');

  static const int currentSchemaVersion = 2;

  /// Default TTL for generic stream URLs (15 minutes).
  static const int defaultStreamTtlMs = 15 * 60 * 1000;

  /// Safety margin for expiry checks (30 seconds).
  static const int expiryMarginMs = 30 * 1000;

  /// Constructs a cache key.
  static String buildKey({
    required String mediaId,
    String? providerId,
    int? qualityIndex,
  }) {
    final p = (providerId != null && providerId.isNotEmpty) ? providerId : 'auto';
    final q = qualityIndex?.toString() ?? 'default';
    return '$mediaId::$p::$q';
  }

  /// Retrieves a cached stream payload if present and not expired.
  ///
  /// If [providerId] is specified, only entries from that provider are returned.
  Map<String, dynamic>? get({
    required String mediaId,
    String? providerId,
    int? qualityIndex,
  }) {
    final targetKey = buildKey(
      mediaId: mediaId,
      providerId: providerId,
      qualityIndex: qualityIndex,
    );

    // 1. Try exact provider-aware key
    if (box.containsKey(targetKey)) {
      final raw = box.get(targetKey);
      final entry = _parseEntry(raw);
      if (entry != null && !entry.isExpired) {
        if (providerId == null ||
            providerId.isEmpty ||
            entry.providerId == providerId) {
          return entry.data;
        }
      } else {
        box.delete(targetKey);
      }
    }

    // 2. Legacy fallback: check bare mediaId only if no provider is forced
    if (providerId == null || providerId.isEmpty) {
      if (box.containsKey(mediaId)) {
        final raw = box.get(mediaId);
        final entry = _parseEntry(raw);
        if (entry != null && !entry.isExpired) {
          return entry.data;
        } else {
          box.delete(mediaId);
        }
      }
    }

    return null;
  }

  /// Stores a stream payload in cache with provider info and TTL.
  void put({
    required String mediaId,
    required Map<String, dynamic> data,
    required String providerId,
    int? qualityIndex,
    Duration? ttl,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Never cache range-gated iOS streams that return 403 past 1MB
    if (_containsRangeGatedUrl(data)) {
      return;
    }

    final calculatedTtlMs = ttl?.inMilliseconds ?? _detectTtlMs(data);
    final expiresAt = now + calculatedTtlMs;

    final entry = CachedStreamEntry(
      data: data,
      providerId: providerId,
      cachedAtMs: now,
      expiresAtMs: expiresAt,
      schemaVersion: currentSchemaVersion,
    );

    final key = buildKey(
      mediaId: mediaId,
      providerId: providerId,
      qualityIndex: qualityIndex,
    );

    box.put(key, entry.toJson());

    // Also update legacy bare key for backward compatibility with external components
    if (data['playable'] == true) {
      box.put(mediaId, data);
    }
  }

  /// Removes entries for [mediaId].
  void invalidate(String mediaId, {String? providerId}) {
    box.delete(mediaId);
    if (providerId != null && providerId.isNotEmpty) {
      box.delete(buildKey(mediaId: mediaId, providerId: providerId, qualityIndex: 0));
      box.delete(buildKey(mediaId: mediaId, providerId: providerId, qualityIndex: 1));
      box.delete(buildKey(mediaId: mediaId, providerId: providerId));
    } else {
      // Invalidate all keys matching mediaId::
      final keysToDelete = <dynamic>[];
      for (final key in box.keys) {
        if (key is String && key.startsWith('$mediaId::')) {
          keysToDelete.add(key);
        }
      }
      for (final k in keysToDelete) {
        box.delete(k);
      }
    }
  }

  /// Purges all expired or poisoned entries from cache.
  void purgeExpired() {
    final toDelete = <dynamic>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      final entry = _parseEntry(raw);
      if (entry == null || entry.isExpired) {
        toDelete.add(key);
      }
    }
    for (final k in toDelete) {
      box.delete(k);
    }
  }

  CachedStreamEntry? _parseEntry(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      CachedStreamEntry? entry;
      if (raw.containsKey('schemaVersion') && raw.containsKey('data')) {
        entry = CachedStreamEntry.fromJson(raw);
      } else {
        // Legacy unversioned entry
        entry = CachedStreamEntry(
          data: raw.map((k, v) => MapEntry(k.toString(), v)),
          providerId: raw['providerId']?.toString() ?? '',
          cachedAtMs: DateTime.now().millisecondsSinceEpoch,
          expiresAtMs: DateTime.now().millisecondsSinceEpoch + defaultStreamTtlMs,
        );
      }
      // Poisoned range-gated iOS URLs fail past 1MB with 403 Forbidden.
      // Discard so full unthrottled VISIONOS streams are resolved.
      if (_containsRangeGatedUrl(entry.data)) {
        return null;
      }
      return entry;
    }
    return null;
  }

  static bool _containsRangeGatedUrl(Map<String, dynamic> data) {
    bool isGated(dynamic u) =>
        u is String && (u.contains('c=IOS') || u.contains('c=ios'));
    final low = data['lowQualityAudio'];
    if (low is Map && isGated(low['url'])) return true;
    final high = data['highQualityAudio'];
    if (high is Map && isGated(high['url'])) return true;
    final formats = data['audioFormats'];
    if (formats is List) {
      for (final f in formats) {
        if (f is Map && isGated(f['url'])) return true;
      }
    }
    return false;
  }

  int _detectTtlMs(Map<String, dynamic> data) {
    // Check if lowQualityAudio URL has an expire parameter (YouTube)
    final low = data['lowQualityAudio'];
    if (low is Map && low['url'] is String) {
      final url = low['url'] as String;
      final match = RegExp(r'[?&]expire=([0-9]+)').firstMatch(url);
      if (match != null) {
        final epochSec = int.tryParse(match.group(1)!);
        if (epochSec != null) {
          final expireMs = epochSec * 1000;
          final remainingMs =
              expireMs - DateTime.now().millisecondsSinceEpoch - expiryMarginMs;
          if (remainingMs > 0) return remainingMs;
        }
      }
    }
    return defaultStreamTtlMs;
  }
}
