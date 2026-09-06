import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/cache/stream_cache.dart';

/// In-memory fake box implementing the minimal Box methods used by StreamCache.
class FakeBox {
  final Map<dynamic, dynamic> _store = {};

  bool containsKey(dynamic key) => _store.containsKey(key);

  dynamic get(dynamic key) => _store[key];

  void put(dynamic key, dynamic value) {
    _store[key] = value;
  }

  void delete(dynamic key) {
    _store.remove(key);
  }

  Iterable<dynamic> get keys => _store.keys.toList();

  void clear() => _store.clear();
}

void main() {
  group('StreamCache', () {
    test('buildKey formats provider-aware keys', () {
      expect(
        StreamCache.buildKey(mediaId: 'song-1', providerId: 'qobuz', qualityIndex: 1),
        'song-1::qobuz::1',
      );
      expect(
        StreamCache.buildKey(mediaId: 'song-1'),
        'song-1::auto::default',
      );
    });

    test('put and get round-trip with provider isolation', () {
      final fake = FakeBox();
      // We can test CachedStreamEntry directly and fake store
      final entry = CachedStreamEntry(
        data: {'url': 'https://qobuz.stream', 'playable': true},
        providerId: 'qobuz',
        cachedAtMs: DateTime.now().millisecondsSinceEpoch,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 60000,
      );

      fake.put('s1::qobuz::1', entry.toJson());

      // Correct provider lookup finds it
      final retrieved = fake.get('s1::qobuz::1');
      expect(retrieved, isNotNull);
      final parsed = CachedStreamEntry.fromJson(retrieved);
      expect(parsed.providerId, 'qobuz');
      expect(parsed.isExpired, isFalse);

      // Different provider key does not match
      expect(fake.containsKey('s1::tidal::1'), isFalse);
    });

    test('expired entry reports isExpired as true', () {
      final expired = CachedStreamEntry(
        data: {'url': 'https://stream', 'playable': true},
        providerId: 'qobuz',
        cachedAtMs: DateTime.now().millisecondsSinceEpoch - 100000,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch - 1000,
      );
      expect(expired.isExpired, isTrue);

      final fresh = CachedStreamEntry(
        data: {'url': 'https://stream', 'playable': true},
        providerId: 'qobuz',
        cachedAtMs: DateTime.now().millisecondsSinceEpoch,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 500000,
      );
      expect(fresh.isExpired, isFalse);
    });
  });
}
