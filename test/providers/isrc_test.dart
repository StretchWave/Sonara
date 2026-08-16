import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/matching/isrc.dart';

void main() {
  group('normalizeIsrc', () {
    test('keeps a clean canonical ISRC', () {
      expect(normalizeIsrc('USUM71703861'), 'USUM71703861');
    });

    test('strips separators and lowercases input', () {
      expect(normalizeIsrc('us-um7-17-03861'), 'USUM71703861');
    });

    test('returns null for non-ISRC values', () {
      expect(normalizeIsrc(null), isNull);
      expect(normalizeIsrc(''), isNull);
      expect(normalizeIsrc('dQw4w9WgXcQ'), isNull);
    });

    test('extracts an ISRC embedded in longer text', () {
      expect(normalizeIsrc('Song (USUM71703861)'), 'USUM71703861');
    });
  });

  group('isIsrcMediaId', () {
    test('detects media ids that are ISRCs', () {
      expect(isIsrcMediaId('USUM71703861'), isTrue);
      expect(isIsrcMediaId('dQw4w9WgXcQ'), isFalse);
    });
  });
}
