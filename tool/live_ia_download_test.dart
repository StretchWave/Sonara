import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sonara/services/providers/internet_archive_provider.dart';
import 'package:sonara/services/providers/song_query.dart';

/// End-to-end proof of the new source + download formats:
///  1. InternetArchiveProvider resolves a real FLAC stream.
///  2. mpv plays it (real duration, position advances, seek works).
///  3. The exact ffmpeg commands the Downloader uses produce valid
///     MP3 (320k) and FLAC files from the downloaded source.
void main() {
  test('IA provider resolves + mpv plays + conversions produce valid files',
      () async {
    const provider = InternetArchiveProvider();
    final resolved = await provider.resolve(const SongQuery(
      mediaId: 'ia-test',
      title: 'Jazz at the Pawnshop',
      artists: ['Arne Domnérus'],
    ));
    print('PLAYABLE: ${resolved.playable}');
    print('LABEL:    ${resolved.label}');
    print('URL:      ${resolved.audioFormats.firstOrNull?.url}');
    expect(resolved.playable, isTrue, reason: resolved.statusMSG);
    final url = resolved.audioFormats.first.url;

    // ---- 1. mpv playback ------------------------------------------------
    MediaKit.ensureInitialized();
    final player = Player();
    await player.open(Media(url));
    await player.play();
    Duration? dur;
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final d = player.state.duration;
      if (d != null && d > const Duration(seconds: 5)) {
        dur = d;
        break;
      }
    }
    print('DURATION: $dur');
    expect(dur, isNotNull, reason: 'mpv never loaded a real duration');
    await Future.delayed(const Duration(seconds: 3));
    final pos1 = player.state.position;
    await Future.delayed(const Duration(seconds: 3));
    final pos2 = player.state.position;
    print('POS: $pos1 -> $pos2');
    expect(pos2 > pos1, isTrue, reason: 'position did not advance');
    await player.seek(Duration(seconds: dur!.inSeconds ~/ 2));
    await Future.delayed(const Duration(seconds: 2));
    print('AFTER SEEK: ${player.state.position} (target ~${dur.inSeconds ~/ 2}s)');
    expect(player.state.position > const Duration(seconds: 10), isTrue);
    await player.dispose();

    // ---- 2. Download + conversions (mirrors Downloader._convertToFormat)
    final dir = Directory.systemTemp.createTempSync('ia_dl_test');
    final tmp = '${dir.path}/source.flac';
    final mp3 = '${dir.path}/out.mp3';
    final flac = '${dir.path}/out.flac';

    final dl = await Process.run(
        'curl', ['-sL', '-o', tmp, url]);
    expect(dl.exitCode, 0);
    expect(File(tmp).lengthSync(), greaterThan(100000));

    final ffmpegOk = await Process.run('ffmpeg', ['-version']);
    expect(ffmpegOk.exitCode, 0, reason: 'ffmpeg not installed');

    final mp3Res = await Process.run('ffmpeg', [
      '-y', '-i', tmp, '-vn', '-codec:a', 'libmp3lame', '-b:a', '320k', mp3
    ]);
    expect(mp3Res.exitCode, 0, reason: 'mp3 conversion failed: ${mp3Res.stderr}');
    expect(File(mp3).lengthSync(), greaterThan(100000));

    final flacRes = await Process.run(
        'ffmpeg', ['-y', '-i', tmp, '-vn', '-codec:a', 'flac', flac]);
    expect(flacRes.exitCode, 0,
        reason: 'flac conversion failed: ${flacRes.stderr}');
    expect(File(flac).lengthSync(), greaterThan(100000));

    // ---- 3. ffprobe verification ----------------------------------------
    final mp3Info = await Process.run('ffprobe', [
      '-v', 'error', '-show_entries',
      'format=format_name,duration:stream=codec_name,bit_rate',
      '-of', 'json', mp3
    ]);
    print('MP3 PROBE: ${mp3Info.stdout}');
    expect(mp3Info.stdout, contains('"mp3"'));
    expect(mp3Info.stdout, contains('320000'));

    final flacInfo = await Process.run('ffprobe', [
      '-v', 'error', '-show_entries',
      'format=format_name,duration:stream=codec_name',
      '-of', 'json', flac
    ]);
    print('FLAC PROBE: ${flacInfo.stdout}');
    expect(flacInfo.stdout, contains('"flac"'));

    // Durations should all be close (~12 min for the Jazz at the Pawnshop
    // track) and consistent with what mpv reported.
    final probe = await Process.run('ffprobe', [
      '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', mp3
    ]);
    final mp3Dur = double.tryParse(probe.stdout.trim()) ?? 0;
    print('MP3 DURATION: ${probe.stdout.trim()} (source ~${dur.inSeconds}s)');
    expect((mp3Dur - dur.inSeconds).abs() < 30, isTrue);

    dir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
