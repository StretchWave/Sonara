import 'dart:convert';
import 'dart:typed_data';

import '../utils/helper.dart';

/// Utilities for lyric text processing:
/// - [shiftLyrics] applies a resync offset (ms) to LRC or QRC lyric text.
/// - [decryptKrc] / [krcToQrc] decode KuGou word-level karaoke lyrics (KRC)
///   and convert them to the QRC format understood by flutter_lyric.
class LyricsUtils {
  LyricsUtils._();

  static final RegExp _lrcTimeTag =
      RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final RegExp _qrcLineTag = RegExp(r'^\[(\d+),(\d+)\]');
  static final RegExp _krcTimeTag =
      RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final RegExp _krcWordTag = RegExp(r'<(\d+),(\d+),(\d+)>');
  static final RegExp _krcOffsetTag = RegExp(r'\[offset:(-?\d+)\]');
  static final RegExp _krcStartMarker = RegExp(
      r'&Start=(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?,(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?');

  /// Shifts every timestamp in [text] by [offsetMs] milliseconds.
  ///
  /// Supports both LRC (`[mm:ss.xx]`) and QRC (`[start,dur]`) line tags.
  /// Positive offsets delay the lyrics (lyrics appear later).
  static String shiftLyrics(String text, int offsetMs) {
    if (offsetMs == 0 || text.isEmpty) return text;

    if (_qrcLineTag.hasMatch(text)) {
      return text.replaceAllMapped(_qrcLineTag, (match) {
        final start = int.parse(match.group(1)!);
        final duration = int.parse(match.group(2)!);
        return '[${start + offsetMs},$duration]';
      });
    }
    return text.replaceAllMapped(_lrcTimeTag, (match) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final frac = match.group(3);
      final ms = minutes * 60000 +
          seconds * 1000 +
          (frac == null
              ? 0
              : frac.length == 3
                  ? int.parse(frac)
                  : int.parse(frac) * 10);
      final shifted = ms + offsetMs;
      if (shifted < 0) return match.group(0)!;
      final m = shifted ~/ 60000;
      final s = (shifted % 60000) ~/ 1000;
      final centi = (shifted % 1000) ~/ 10;
      return '[${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${centi.toString().padLeft(2, '0')}]';
    });
  }

  /// Decrypts the base64 `content` of a KuGou KRC lyric download response.
  ///
  /// Returns the raw KRC text, or null if the payload can't be decoded.
  static String? decryptKrc(String base64Content) {
    try {
      final bytes = base64.decode(base64Content);
      if (bytes.length < 8) return null;
      final keyLength =
          ByteData.sublistView(bytes).getInt32(0, Endian.little);
      if (keyLength <= 0 || 4 + keyLength > bytes.length) return null;
      final key = bytes.sublist(4, 4 + keyLength);
      final out = BytesBuilder(copy: false);
      for (var i = 4 + keyLength; i < bytes.length; i++) {
        out.addByte(bytes[i] ^ key[(i - 4 - keyLength) % keyLength]);
      }
      final text = utf8.decode(out.toBytes(), allowMalformed: true);
      return text.contains('[') ? text : null;
    } catch (e) {
      printERROR("KRC decryption failed: $e");
      return null;
    }
  }

  /// Converts raw KRC text into QRC format (`[start,dur]` lines with
  /// `(start,dur)` word spans) plus plain lyrics.
  ///
  /// Returns `{"qrc": ..., "plain": ...}` or null when nothing parses.
  static Map<String, String>? krcToQrc(String krc) {
    final lines = krc.split('\n');
    // Positive [offset:...] values shift the lyrics later.
    var offset = 0;
    final offsetMatch = _krcOffsetTag.firstMatch(krc);
    if (offsetMatch != null) {
      offset = int.parse(offsetMatch.group(1)!);
    }

    final qrcLines = <String>[];
    final plainLines = <String>[];

    for (final rawLine in lines) {
      final timeMatch = _krcTimeTag.firstMatch(rawLine);
      if (timeMatch == null) continue; // metadata like [ti:...]
      final minutes = int.parse(timeMatch.group(1)!);
      final seconds = int.parse(timeMatch.group(2)!);
      final frac = timeMatch.group(3);
      final lineStart = minutes * 60000 +
          seconds * 1000 +
          (frac == null
              ? 0
              : frac.length == 3
                  ? int.parse(frac)
                  : int.parse(frac) * 10);
      final content = rawLine.substring(timeMatch.end);

      // Line end from the &Start=marker (second time) when present.
      int? markerEnd;
      final marker = _krcStartMarker.firstMatch(content);
      if (marker != null) {
        markerEnd = _krcTimeToMs(
          int.parse(marker.group(4)!),
          int.parse(marker.group(5)!),
          marker.group(6),
        );
      }

      // Extract word spans: <start,end,0>text where times are relative to
      // the line start. A word's end is the next tag's start (the tag marks
      // where the following text begins); the last word ends at its own tag
      // end value.
      final matches = _krcWordTag.allMatches(content).toList();
      final words = <(int, int, String)>[];
      for (var i = 0; i < matches.length; i++) {
        final match = matches[i];
        final wordStart = int.parse(match.group(1)!);
        final wordEnd = i + 1 < matches.length
            ? int.parse(matches[i + 1].group(1)!)
            : int.parse(match.group(2)!);
        final text =
            content.substring(match.end, _nextWordStart(content, match.end));
        if (text.trim().isEmpty) continue;
        words.add((wordStart, wordEnd, text));
      }
      // Fallback: line without word tags
      if (words.isEmpty) {
        final plain = content.replaceAll(_krcWordTag, '').trim();
        if (plain.isNotEmpty) {
          qrcLines.add('[$lineStart,5000]$plain');
          plainLines.add(plain);
        }
        continue;
      }

      final lastWordEnd = words.last.$2;
      final lineDuration = markerEnd != null
          ? (markerEnd - lineStart).clamp(100, 60000)
          : lastWordEnd.clamp(100, 60000);
      final lineStartShifted = lineStart + offset;
      final builder = StringBuffer('[$lineStartShifted,$lineDuration]');
      final plainBuilder = StringBuffer();
      for (final (start, end, text) in words) {
        final absStart = lineStartShifted + start;
        builder.write('$text($absStart,${end - start})');
        plainBuilder.write(text);
      }
      qrcLines.add(builder.toString());
      plainLines.add(plainBuilder.toString());
    }

    if (qrcLines.isEmpty) return null;
    return {
      'qrc': qrcLines.join('\n'),
      'plain': plainLines.join('\n'),
    };
  }

  static int _nextWordStart(String content, int from) {
    final next = _krcWordTag.firstMatch(content.substring(from));
    if (next == null) return content.length;
    return from + next.start;
  }

  static int _krcTimeToMs(int minutes, int seconds, String? frac) {
    return minutes * 60000 +
        seconds * 1000 +
        (frac == null
            ? 0
            : frac.length == 3
                ? int.parse(frac)
                : int.parse(frac) * 10);
  }
}
