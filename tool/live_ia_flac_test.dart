import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

/// Proves mpv can stream an Internet Archive FLAC file end-to-end:
/// real duration, position advances, seek works.
void main() {
  test('mpv plays Internet Archive FLAC', () async {
    MediaKit.ensureInitialized();
    final player = Player();
    const url =
        'https://archive.org/download/dong-hai-cd-various-artists-me-oi-flac/01.%20Me%20Oi%20-%20Phuong%20Thanh.flac';
    await player.open(Media(url));
    await player.play();

    // Wait for real duration (proves the stream fully loads).
    Duration? dur;
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final d = player.state.duration;
      if (d != null && d > const Duration(seconds: 10)) {
        dur = d;
        break;
      }
    }
    print('DURATION: $dur');
    expect(dur, isNotNull, reason: 'mpv never loaded a real duration');

    // Position must advance.
    await Future.delayed(const Duration(seconds: 3));
    final pos1 = player.state.position;
    await Future.delayed(const Duration(seconds: 3));
    final pos2 = player.state.position;
    print('POS: $pos1 -> $pos2');
    expect(pos2 > pos1, isTrue, reason: 'position did not advance');

    // Seek far into the file and confirm we get there.
    await player.seek(Duration(seconds: dur!.inSeconds ~/ 2));
    await Future.delayed(const Duration(seconds: 2));
    final afterSeek = player.state.position;
    print('AFTER SEEK: $afterSeek (target ~${dur.inSeconds ~/ 2}s)');
    expect(afterSeek > const Duration(seconds: 10), isTrue,
        reason: 'seek did not move into the file');

    await player.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
