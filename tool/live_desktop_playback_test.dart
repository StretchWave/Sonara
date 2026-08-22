// End-to-end desktop playback verification:
//   1. Resolve a stream through the real provider (VISIONOS + visitor id)
//   2. Play it through the app's exact code path (ConcatenatingAudioSource
//      with headers) on the media_kit backend
//   3. Assert real playback: duration known, position advances, seek works,
//      no errors
// Run with:  PATH="<build>/windows/x64/runner/Release:$PATH" flutter test tool/live_desktop_playback_test.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:sonara/services/providers/song_query.dart';
import 'package:sonara/services/providers/stream_route_config.dart';
import 'package:sonara/services/providers/stream_router.dart';

class _AllowAllHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowAllHttpOverrides();

  test('desktop playback works end to end', () async {
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
    print('visitorId: ${visitorId.isEmpty ? 'EMPTY' : 'present (${visitorId.length} chars)'}');
    expect(visitorId, isNotEmpty,
        reason: 'the app must have a cached visitor id for VISIONOS');

    // 1. Resolve through the real router (same as getStreamInfo's isolate).
    final config = StreamRouteConfig(visitorId: visitorId);
    final provider = await StreamRouter.build(config)
        .fetch('eWNqzgPr6S0',
            song: const SongQuery(mediaId: 'eWNqzgPr6S0'));
    expect(provider.playable, isTrue,
        reason: 'provider must resolve a playable stream: ${provider.statusMSG}');
    final audio = provider.highestQualityAudio!;
    print('resolved itag=${audio.itag} codec=${audio.audioCodec} '
        'bitrate=${audio.bitrate} urlHost=${Uri.parse(audio.url).host} '
        'c=${Uri.parse(audio.url).queryParameters['c']} '
        'headers=${audio.headers}');

    // 2. Play via the app's code path (headers + concat source).
    JustAudioMediaKit.registerWith();
    final playlist =
        ConcatenatingAudioSource(children: [], useLazyPreparation: false);
    final player = AudioPlayer(useProxyForRequestHeaders: false);
    final errors = <Object>[];
    final sub = player.playbackEventStream.listen((_) {},
        onError: (Object e) => errors.add(e));
    try {
      await player.setAudioSource(playlist);
      await playlist.add(AudioSource.uri(
        Uri.parse(audio.url),
        headers: audio.headers,
        tag: 'test',
      ));
      await player.play();

      await Future.delayed(const Duration(seconds: 10));
      print('after 10s: state=${player.processingState} '
          'duration=${player.duration} pos=${player.position}');
      expect(player.duration, isNotNull,
          reason: 'duration must be known (real audio loaded)');
      expect(player.duration!.inSeconds, greaterThan(0));
      expect(player.position.inSeconds, greaterThan(6),
          reason: 'position must advance (real playback)');

      // Seek far into the song (past 1 MiB) — requires a range request.
      await player.seek(const Duration(seconds: 150));
      await Future.delayed(const Duration(seconds: 3));
      print('after seek: pos=${player.position}');
      expect(player.position.inSeconds, greaterThan(140));

      await Future.delayed(const Duration(seconds: 4));
      print('final: pos=${player.position} errors=$errors');
      expect(errors, isEmpty, reason: 'no playback errors allowed');
      print('DESKTOP PLAYBACK VERIFIED');
    } finally {
      await sub.cancel();
      await player.stop();
      await player.dispose();
    }
  });
}
