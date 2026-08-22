// End-to-end proof of the "download as MP3" flow for the user's real
// library: resolve a YouTube song via the router (VISIONOS + visitor id),
// download the best stream, and convert it to MP3 with the exact ffmpeg
// command the Downloader uses. Verifies codec, bitrate and duration.
//
// Run with:  PATH="<build>/windows/x64/runner/Release:$PATH" flutter test tool/live_yt_mp3_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sonara/services/providers/song_query.dart';
import 'package:sonara/services/providers/stream_route_config.dart';
import 'package:sonara/services/providers/stream_router.dart';
import 'package:sonara/services/stream_service.dart';

class _AllowAllHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowAllHttpOverrides();

  test('YouTube resolve -> download -> MP3 320k conversion', () async {
    // Read the app's cached visitor id (like StreamRouteConfig.fromSettings).
    String visitorId = '';
    try {
      final dbDir = '${Platform.environment['APPDATA']}/Sonara/Sonara/db';
      Hive.init(dbDir);
      final prefs = await Hive.openBox('AppPrefs');
      final v = prefs.get('visitorId');
      if (v is Map && v['id'] is String) visitorId = v['id'] as String;
      await prefs.close();
    } catch (_) {}
    print('visitorId: ${visitorId.isEmpty ? 'EMPTY' : 'present'}');

    // 1. Resolve the user's actual song through the real router.
    final config = StreamRouteConfig(visitorId: visitorId);
    final resolved = await StreamRouter.build(config)
        .fetch('-BJt4fCAtZE', song: const SongQuery(mediaId: '-BJt4fCAtZE'));
    print('PLAYABLE: ${resolved.playable}  MSG: ${resolved.statusMSG}');
    expect(resolved.playable, isTrue, reason: resolved.statusMSG);

    // 2. Pick the stream the Downloader would use for MP3 (flac > opus).
    final formats = resolved.audioFormats ?? const <Audio>[];
    Audio? audio;
    for (final a in formats) {
      if (a.audioCodec == Codec.flac || a.audioCodec == Codec.opus) {
        audio = a;
        break;
      }
    }
    audio ??= formats.first;
    print('SOURCE: ${audio.audioCodec} itag=${audio.itag} '
        'size=${audio.size} url=${audio.url.length}ch');
    expect(audio.audioCodec, Codec.opus);

    // 3. Download (with the same headers the Downloader sends).
    final dir = Directory.systemTemp.createTempSync('yt_mp3_test');
    final tmp = '${dir.path}/source.opus';
    final mp3 = '${dir.path}/out.mp3';
    final headers = <String, String>{
      if (audio.size > 0) 'Range': 'bytes=0-${audio.size}',
      if (audio.headers != null) ...audio.headers!,
    };
    final args = ['-sL', '-o', tmp];
    headers.forEach((k, v) => args.addAll(['-H', '$k: $v']));
    args.add(audio.url);
    final dl = await Process.run('curl', args);
    expect(dl.exitCode, 0, reason: 'download failed: ${dl.stderr}');
    final size = File(tmp).lengthSync();
    print('DOWNLOADED: $size bytes');
    expect(size, greaterThan(100000));

    // 4. Convert exactly like Downloader._convertToFormat.
    final mp3Res = await Process.run('ffmpeg', [
      '-y', '-i', tmp, '-vn', '-codec:a', 'libmp3lame', '-b:a', '320k', mp3
    ]);
    expect(mp3Res.exitCode, 0,
        reason: 'mp3 conversion failed: ${mp3Res.stderr}');
    print('MP3 SIZE: ${File(mp3).lengthSync()} bytes');

    // 5. Verify codec, bitrate and duration.
    final info = await Process.run('ffprobe', [
      '-v', 'error', '-show_entries',
      'format=format_name,duration:stream=codec_name,bit_rate',
      '-of', 'json', mp3
    ]);
    print('PROBE: ${info.stdout}');
    expect(info.stdout, contains('"mp3"'));
    expect(info.stdout, contains('320000'));

    final dur = await Process.run('ffprobe', [
      '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', mp3
    ]);
    final seconds = double.tryParse(dur.stdout.trim()) ?? 0;
    print('MP3 DURATION: ${dur.stdout.trim()}s (song is 4:37 = 277s)');
    expect((seconds - 277).abs() < 20, isTrue);

    dir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
