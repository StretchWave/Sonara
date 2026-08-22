// Replicates the app's exact playback mechanism: a ConcatenatingAudioSource
// playlist where a UriAudioSource (with headers) is added and played, with
// useProxyForRequestHeaders:false. Verifies the real googlevideo URL plays.
// Run with:
//   export PATH="$PWD/build/windows/x64/runner/Debug:$PATH"
//   flutter test tool/live_playlist_verify_test.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

const _ua =
    'com.google.ios.youtube/21.03.3 (iPad7,6; U; CPU iPadOS 17_7_10 '
    'like Mac OS X; en-US)';

Future<String?> _resolveYoutubeUrl() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.postUrl(Uri.parse(
        'https://music.youtube.com/youtubei/v1/player?prettyPrint=false'));
    req.headers.set('Content-Type', 'application/json');
    req.headers.set('User-Agent', _ua);
    req.headers.set('X-YouTube-Client-Name', '5');
    req.headers.set('X-YouTube-Client-Version', '21.03.3');
    req.headers.set('Origin', 'https://music.youtube.com');
    req.add(utf8.encode(jsonEncode({
      'context': {
        'client': {
          'clientName': 'IOS',
          'clientVersion': '21.03.3',
          'deviceMake': 'Apple',
          'deviceModel': 'iPad7,6',
          'osName': 'iPadOS',
          'osVersion': '17.7.10.21H450',
          'gl': 'US',
          'hl': 'en',
        }
      },
      'videoId': 'eWNqzgPr6S0',
      'contentCheckOk': true,
      'racyCheckOk': true,
    })));
    final res = await req.close().timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final body = await utf8.decoder.bind(res).join();
    final json = jsonDecode(body);
    final formats = (json['streamingData']['adaptiveFormats'] as List? ?? [])
        .where((f) =>
            (f['mimeType'] as String? ?? '').startsWith('audio/mp4') &&
            (f['itag'] as num?) == 140)
        .toList();
    return formats.isNotEmpty ? formats.first['url'] as String? : null;
  } finally {
    client.close();
  }
}

class _AllowAllHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _AllowAllHttpOverrides();
  JustAudioMediaKit.registerWith();

  test('app-style ConcatenatingAudioSource playlist plays with proxy off',
      () async {
    final url = await _resolveYoutubeUrl();
    expect(url, isNotNull);
    expect(url!.contains('127.0.0.1'), isFalse);

    final player = AudioPlayer(useProxyForRequestHeaders: false);
    final playlist = ConcatenatingAudioSource(
        children: [], useLazyPreparation: false);

    // Mimic _createAudioSource: AudioSource.uri(url, headers: {...})
    await playlist.add(AudioSource.uri(
      Uri.parse(url),
      headers: {'User-Agent': _ua},
      tag: 'song1',
    ));
    await player.setAudioSource(playlist);

    final ready = Completer<void>();
    final sub = player.playbackEventStream.listen((event) {
      if (event.processingState == ProcessingState.ready ||
          event.processingState == ProcessingState.completed) {
        if (!ready.isCompleted) ready.complete();
      }
    });

    await player.play();
    try {
      await ready.future.timeout(const Duration(seconds: 25));
      print('PLAYLIST READY: duration=${player.duration} pos=${player.position}');
      await Future.delayed(const Duration(seconds: 3));
      print('POSITION AFTER 3s: ${player.position}');
      expect(player.position, greaterThan(Duration.zero));
    } finally {
      await sub.cancel();
      await player.stop();
      await player.dispose();
    }
  });
}
