import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/lyrics_utils.dart';

/// Encrypts KRC text with the KuGou algorithm (for round-trip testing).
String _encryptKrcForTest(String krc, String key) {
  final keyBytes = utf8.encode(key);
  final body = utf8.encode(krc);
  final builder = BytesBuilder();
  final lengthHeader = ByteData(4)
    ..setInt32(0, keyBytes.length, Endian.little);
  builder.add(lengthHeader.buffer.asUint8List());
  builder.add(keyBytes);
  for (var i = 0; i < body.length; i++) {
    builder.addByte(body[i] ^ keyBytes[i % keyBytes.length]);
  }
  return base64.encode(builder.toBytes());
}

void main() {
  group('shiftLyrics (LRC)', () {
    test('shifts timestamps forward', () {
      const lrc = '[00:10.00]First line\n[00:12.50]Second line';
      final shifted = LyricsUtils.shiftLyrics(lrc, 500);
      expect(shifted, '[00:10.50]First line\n[00:13.00]Second line');
    });

    test('shifts timestamps backward', () {
      const lrc = '[00:10.00]First line\n[00:12.50]Second line';
      final shifted = LyricsUtils.shiftLyrics(lrc, -1000);
      expect(shifted, '[00:09.00]First line\n[00:11.50]Second line');
    });

    test('drops tags that would go negative', () {
      const lrc = '[00:00.50]First line';
      final shifted = LyricsUtils.shiftLyrics(lrc, -1000);
      expect(shifted, '[00:00.50]First line');
    });

    test('zero offset returns text unchanged', () {
      const lrc = '[00:10.00]First line';
      expect(identical(LyricsUtils.shiftLyrics(lrc, 0), lrc), true);
    });

    test('handles three-digit millisecond fractions', () {
      const lrc = '[00:01.123]First line';
      final shifted = LyricsUtils.shiftLyrics(lrc, 7);
      expect(shifted, '[00:01.13]First line');
    });
  });

  group('shiftLyrics (QRC)', () {
    test('shifts line start but keeps duration', () {
      const qrc = '[1000,2500]Hello(1000,800)world(1800,700)';
      final shifted = LyricsUtils.shiftLyrics(qrc, 300);
      expect(shifted, '[1300,2500]Hello(1000,800)world(1800,700)');
    });
  });

  group('decryptKrc', () {
    test('round-trips encrypted KRC content', () {
      const krc = '[ti:Test]\n[ar:Artist]\n[00:10.00]Hello world';
      final encrypted = _encryptKrcForTest(krc, 'krc1');
      final decrypted = LyricsUtils.decryptKrc(encrypted);
      expect(decrypted, contains('[ti:Test]'));
      expect(decrypted, contains('[00:10.00]Hello world'));
    });

    test('returns null for garbage payloads', () {
      expect(LyricsUtils.decryptKrc('not-base64!!!'), isNull);
      expect(LyricsUtils.decryptKrc(base64.encode([1, 2, 3])), isNull);
    });
  });

  group('krcToQrc', () {
    test('converts word-level KRC to QRC', () {
      const krc = '''
[ti:Test]
[ar:Artist]
[00:12.34]&Start=00:12.34,00:16.00<0,0,0>Hello<1200,2000,0>world<2200,3000,0>!
[00:16.00]&Start=00:16.00,00:20.00<0,0,0>Second<1000,1500,0>line
''';
      final result = LyricsUtils.krcToQrc(krc);
      expect(result, isNotNull);
      final qrc = result!['qrc']!;
      final plain = result['plain']!;
      expect(
        qrc,
        '[12340,3660]Hello(12340,1200)world(13540,1000)!(14540,800)\n'
        '[16000,4000]Second(16000,1000)line(17000,500)',
      );
      expect(plain, 'Helloworld!\nSecondline');
    });

    test('applies the [offset:] metadata', () {
      const krc = '''
[offset:500]
[00:12.34]<0,0,0>Hello<1000,2000,0>world
''';
      final result = LyricsUtils.krcToQrc(krc)!;
      // Line start shifted by +500ms, word starts too.
      expect(result['qrc'], '[12840,2000]Hello(12840,1000)world(13840,1000)');
    });

    test('falls back to plain lines without word tags', () {
      const krc = '[00:05.00]No word tags here';
      final result = LyricsUtils.krcToQrc(krc)!;
      expect(result['qrc'], '[5000,5000]No word tags here');
    });

    test('returns null when nothing parses', () {
      expect(LyricsUtils.krcToQrc('[ti:no lyrics]'), isNull);
    });
  });
}
