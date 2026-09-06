import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/duration_match.dart';

void main() {
  group('isDurationMismatch', () {
    test('flags a 3-minute song played as under 1 minute from a FLAC source',
        () {
      // 3 min expected, 50 s actual from Qobuz -> preview/wrong recording.
      expect(isDurationMismatch(180000, 50000, 'qobuz'), isTrue);
    });

    test('flags a 30-second preview of a long song', () {
      expect(isDurationMismatch(420000, 30000, 'deezer'), isTrue);
    });

    test('accepts a close-enough length from a FLAC source', () {
      expect(isDurationMismatch(180000, 175000, 'tidal'), isFalse);
    });

    test('never second-guesses the YouTube source', () {
      expect(isDurationMismatch(180000, 30000, 'youtube_music'), isFalse);
    });

    test('ignores songs without an expected length', () {
      expect(isDurationMismatch(null, 30000, 'qobuz'), isFalse);
    });

    test('ignores very short songs', () {
      expect(isDurationMismatch(45000, 20000, 'qobuz'), isFalse);
    });

    test('ignores unknown sources (local files / old cache)', () {
      expect(isDurationMismatch(180000, 30000, ''), isFalse);
    });

    test('a small gap on a short-ish song does not trigger', () {
      // 70 s expected, 55 s actual (79%) — not far enough off.
      expect(isDurationMismatch(70000, 55000, 'qobuz'), isFalse);
    });
  });
}
