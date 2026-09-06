import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/deezer/deezer_api.dart';
import 'package:sonara/services/providers/matching/isrc_resolver.dart';

/// A fake DeezerApi that returns canned search results.
class _FakeDeezerApi extends DeezerApi {
  _FakeDeezerApi(this._items);

  final List<Map<String, dynamic>> _items;

  @override
  Future<List<Map<String, dynamic>>> searchTracks(
    String term, {
    int limit = 12,
    String? proxyUrl,
  }) async =>
      _items;
}

void main() {
  group('IsrcResolver', () {
    test('returns a validated caller-supplied ISRC without searching', () async {
      final resolver = IsrcResolver(deezerApi: _FakeDeezerApi(const []));
      final isrc = await resolver.resolve(
        candidateIsrc: 'us-um7-20-20701',
        song: 'Blinding Lights',
        artist: 'The Weeknd',
      );
      expect(isrc, 'USUM72020701');
    });

    test('resolves an ISRC from the catalog for the exact recording', () async {
      final resolver = IsrcResolver(deezerApi: _FakeDeezerApi(const [
        {
          'id': 'cover',
          'title': 'Blinding Lights (Cover)',
          'artist': {'name': 'FanChannel'},
          'duration': 201,
          'isrc': 'GBKPL1234567',
        },
        {
          'id': 'original',
          'title': 'Blinding Lights',
          'artist': {'name': 'The Weeknd'},
          'album': {'title': 'After Hours'},
          'duration': 200,
          'isrc': 'USUM72020701',
        },
      ]));
      final isrc = await resolver.resolve(
        song: 'Blinding Lights',
        artist: 'The Weeknd',
        durationMs: 200000,
      );
      // The cover is rejected by the scorer; the original's ISRC wins.
      expect(isrc, 'USUM72020701');
    });

    test('returns null when nothing matches', () async {
      final resolver = IsrcResolver(deezerApi: _FakeDeezerApi(const [
        {
          'id': 'cover',
          'title': 'Blinding Lights (Slowed + Reverb)',
          'artist': {'name': 'SlowedBeats'},
          'duration': 240,
          'isrc': 'GBKPL7654321',
        },
      ]));
      final isrc = await resolver.resolve(
        song: 'Blinding Lights',
        artist: 'The Weeknd',
        durationMs: 200000,
      );
      expect(isrc, isNull);
    });

    test('caches the result so repeat calls do not re-search', () async {
      var calls = 0;
      final resolver = IsrcResolver(deezerApi: _CountingApi(() => calls++));
      await resolver.resolve(
          song: 'Song', artist: 'Artist', durationMs: 1000);
      await resolver.resolve(
          song: 'Song', artist: 'Artist', durationMs: 1000);
      expect(calls, 1);
    });
  });
}

class _CountingApi extends DeezerApi {
  _CountingApi(this._onSearch);

  final void Function() _onSearch;

  @override
  Future<List<Map<String, dynamic>>> searchTracks(
    String term, {
    int limit = 12,
    String? proxyUrl,
  }) async {
    _onSearch();
    return const [];
  }
}
