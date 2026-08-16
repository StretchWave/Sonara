import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/lyrics/lrclib_api.dart';

import 'helpers/fake_dio_adapter.dart';

LrcLibClient clientWith(FakeDioAdapter adapter) =>
    LrcLibClient(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

void main() {
  group('fetchByMetadata', () {
    test('returns synced lyrics when present', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse(lrcJson());
      final client = clientWith(adapter);

      final result = await client.fetchByMetadata(
        trackName: 'Blinding Lights',
        artistName: 'The Weeknd',
        albumName: 'After Hours',
        durationMs: 200000,
      );

      expect(result, isNotNull);
      expect(result!.hasSynced, isTrue);
      expect(result.syncedLyrics, contains('[00:01.00]'));
      expect(adapter.requestCount, 1);
    });

    test('sends duration and album in the query', () async {
      final adapter = FakeDioAdapter();
      late RequestOptions seen;
      adapter.handler = (o) {
        seen = o;
        return jsonResponse(lrcJson());
      };
      final client = clientWith(adapter);

      await client.fetchByMetadata(
        trackName: 'Blinding Lights',
        artistName: 'The Weeknd',
        albumName: 'After Hours',
        durationMs: 200400,
      );

      expect(seen.queryParameters['track_name'], 'Blinding Lights');
      expect(seen.queryParameters['artist_name'], 'The Weeknd');
      expect(seen.queryParameters['album_name'], 'After Hours');
      expect(seen.queryParameters['duration'], 200);
    });

    test('404 returns null instead of throwing', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse({}, status: 404);
      final client = clientWith(adapter);

      expect(
          await client.fetchByMetadata(
              trackName: 'x', artistName: 'y'),
          isNull);
    });

    test('429 surfaces Retry-After', () async {
      final adapter = FakeDioAdapter();
      adapter.handler =
          (_) => jsonResponse({}, status: 429, headers: {'retry-after': '7'});
      final client = clientWith(adapter);

      await expectLater(
        client.fetchByMetadata(trackName: 'x', artistName: 'y'),
        throwsA(isA<LrcLibRateLimited>()
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 7))),
      );
    });

    test('429 without Retry-After defaults to 30s', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse({}, status: 429);
      final client = clientWith(adapter);

      await expectLater(
        client.fetchByMetadata(trackName: 'x', artistName: 'y'),
        throwsA(isA<LrcLibRateLimited>()
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 30))),
      );
    });

    test('instrumental flag is preserved', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse(
          lrcJson(synced: null, plain: null, instrumental: true));
      final client = clientWith(adapter);

      final result = await client.fetchByMetadata(
          trackName: 'x', artistName: 'y');
      expect(result!.instrumental, isTrue);
      expect(result.hasSynced, isFalse);
      expect(result.hasPlain, isFalse);
    });
  });

  group('search', () {
    test('returns a list of candidates', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse([lrcJson(id: 1), lrcJson(id: 2)]);
      final client = clientWith(adapter);

      final results = await client.search(
          trackName: 'Blinding Lights', artistName: 'The Weeknd');
      expect(results, hasLength(2));
      expect(results.first.id, 1);
    });

    test('429 surfaces Retry-After', () async {
      final adapter = FakeDioAdapter();
      adapter.handler =
          (_) => jsonResponse({}, status: 429, headers: {'retry-after': '3'});
      final client = clientWith(adapter);

      await expectLater(
        client.search(trackName: 'x', artistName: 'y'),
        throwsA(isA<LrcLibRateLimited>()),
      );
    });
  });

  group('LRC validation', () {
    test('parseLrc extracts monotonic timestamps', () {
      final lines = parseLrc('[00:01.50]Hello\n[00:03.00]World');
      expect(lines, isNotNull);
      expect(lines!.length, 2);
      expect(lines[0].timestampMs, 1500);
      expect(lines[1].timestampMs, 3000);
    });

    test('parseLrc handles minutes and plain seconds', () {
      final lines = parseLrc('[01:02]Two minutes');
      expect(lines, isNotNull);
      expect(lines!.single.timestampMs, 62000);
    });

    test('parseLrc rejects out-of-order timestamps', () {
      expect(parseLrc('[00:05.00]Later\n[00:02.00]Earlier'), isNull);
    });

    test('parseLrc rejects text without timestamps', () {
      expect(parseLrc('no timestamps here'), isNull);
    });

    test('parseLrc rejects empty lyric lines', () {
      expect(parseLrc('[00:01.00]\n[00:02.00]'), isNull);
    });

    test('timestampsPlausible rejects lyrics far longer than the track', () {
      final lines = parseLrc('[10:00.00]Very long intro')!;
      expect(timestampsPlausible(lines, 60000), isFalse);
      expect(timestampsPlausible(lines, 590000), isTrue);
    });

    test('validateSyncedLyrics accepts valid LRC', () {
      expect(
        LrcLibClient.validateSyncedLyrics('[00:01.00]A\n[00:02.00]B',
            durationMs: 120000),
        isNotNull,
      );
    });

    test('validateSyncedLyrics rejects corrupt or implausible LRC', () {
      expect(LrcLibClient.validateSyncedLyrics(null), isNull);
      expect(LrcLibClient.validateSyncedLyrics('', durationMs: 60000), isNull);
      expect(
        LrcLibClient.validateSyncedLyrics('[10:00.00]A', durationMs: 60000),
        isNull,
      );
    });
  });

  group('scoreLrcCandidate', () {
    const base = LrcLyrics(
      trackName: 'Blinding Lights',
      artistName: 'The Weeknd',
      albumName: 'After Hours',
      duration: 200,
    );

    test('exact metadata scores high', () {
      final score = scoreLrcCandidate(
        trackName: 'Blinding Lights',
        artists: const ['The Weeknd'],
        albumName: 'After Hours',
        durationMs: 200000,
        candidate: base,
      );
      expect(score, greaterThanOrEqualTo(0.9));
    });

    test('wrong artist scores poorly', () {
      final score = scoreLrcCandidate(
        trackName: 'Blinding Lights',
        artists: const ['The Weeknd'],
        durationMs: 200000,
        candidate: const LrcLyrics(
          trackName: 'Blinding Lights',
          artistName: 'Some Other Band',
          duration: 200,
        ),
      );
      expect(score, lessThan(0.75));
    });

    test('different song scores poorly', () {
      final score = scoreLrcCandidate(
        trackName: 'Blinding Lights',
        artists: const ['The Weeknd'],
        durationMs: 200000,
        candidate: const LrcLyrics(
          trackName: 'Starboy',
          artistName: 'The Weeknd',
          duration: 200,
        ),
      );
      expect(score, lessThan(0.5));
    });

    test('duration mismatch lowers the score', () {
      final exact = scoreLrcCandidate(
        trackName: 'Blinding Lights',
        artists: const ['The Weeknd'],
        durationMs: 200000,
        candidate: base,
      );
      final off = scoreLrcCandidate(
        trackName: 'Blinding Lights',
        artists: const ['The Weeknd'],
        durationMs: 200000,
        candidate: const LrcLyrics(
          trackName: 'Blinding Lights',
          artistName: 'The Weeknd',
          duration: 500,
        ),
      );
      expect(off, lessThan(exact));
    });
  });
}
