// Live debug: resolve a real song through the user's configured router,
// print which provider won, and dump every SoundCloud search candidate
// with its match score so we can see whether wrong versions get picked.
//
// Run with:  flutter test tool/live_source_resolve_debug_test.dart
//
// Override the song via SONG_TITLE / SONG_ARTIST / SONG_ALBUM / SONG_DURATION
// (defaults to Blinding Lights - The Weeknd, 3:20).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sonara/services/providers/matching/track_candidate.dart';
import 'package:sonara/services/providers/matching/track_scorer.dart';
import 'package:sonara/services/providers/song_query.dart';
import 'package:sonara/services/audio_handler.dart';
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

  test('live source resolve debug', () async {
    final title = Platform.environment['SONG_TITLE'] ?? 'Blinding Lights';
    final artist = Platform.environment['SONG_ARTIST'] ?? 'The Weeknd';
    final album = Platform.environment['SONG_ALBUM'] ?? 'After Hours';
    final durationSec =
        int.tryParse(Platform.environment['SONG_DURATION'] ?? '') ?? 200;

    final dbDir = '${Platform.environment['APPDATA']}/Sonara/Sonara/db';
    Hive.init(dbDir);
    await Hive.openBox('AppPrefs');
    final config = StreamRouteConfig.fromSettings();
    print('Provider order: ${config.providerOrder}');

    final query = SongQuery(
      mediaId: 'debug',
      title: title,
      artists: [artist],
      album: album,
      durationMs: durationSec * 1000,
    );

    // 1a. Show the playback-ordered config (SoundCloud/IA demoted to
    // fallbacks after YouTube for playback).
    final playback = MyAudioHandler.playbackConfig(config);
    print('Playback order: ${playback.providerOrder}');

    // 1. Resolve through the real router.
    final router = StreamRouter.build(playback);
    final resolved = await router.fetch('debug', song: query);
    print('\n=== ROUTED RESULT ===');
    print('playable: ${resolved.playable}  provider: '
        '"${resolved.providerId}"  msg: ${resolved.statusMSG}');
    final audio = resolved.audioFormats?.isNotEmpty == true
        ? resolved.audioFormats!.first
        : null;
    print('audio: ${audio?.audioCodec} label: ${audio?.label} '
        'duration: ${audio?.duration}ms');

    // 2. Dump SoundCloud candidates + scores.
    print('\n=== SOUNDCLOUD CANDIDATES ===');
    final scProvider = router.providers
        .where((p) => p.id == 'soundcloud')
        .toList();
    if (scProvider.isEmpty) {
      print('SoundCloud not in the router.');
      return;
    }
    final sc = scProvider.first;
    final scResolved = await sc.resolve(query);
    print('SoundCloud resolve -> playable: ${scResolved.playable} '
        'msg: ${scResolved.statusMSG}');
    if (!scResolved.playable) {
      print('(SoundCloud correctly rejected the wrong versions — the router '
          'falls through to YouTube.)');
    }
    for (final r in await _soundcloudRawCandidates(title, artist)) {
      final score = scoreCandidate(candidate: r.$1, query: query);
      print('  ${score == rejectScore ? "REJECT" : score.toString().padLeft(5)}  '
          '${r.$1.title}  [${r.$1.artists.join(', ')}]  '
          '${r.$1.durationMs == null ? "?" : (r.$1.durationMs! / 1000).round()}s');
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}

/// Returns raw SoundCloud search candidates (title + uploader) for display.
Future<List<(TrackCandidate, String)>> _soundcloudRawCandidates(
    String title, String artist) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final clientId = await _scrapeClientId(client);
    if (clientId == null) return const [];
    final term = '$artist - $title';
    final uri = Uri.parse(
        'https://api-v2.soundcloud.com/search/tracks?q='
        '${Uri.encodeComponent(term)}&limit=8&client_id=$clientId'
        '&app_locale=en');
    final req = await client.getUrl(uri);
    req.headers.set('User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0');
    final res = await req.close().timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) return const [];
    final body = await utf8.decoder.bind(res).join();
    final json = jsonDecode(body);
    final collection = json['collection'] as List? ?? [];
    return [
      for (final item in collection.whereType<Map>())
        (
          TrackCandidate(
            trackId: '${item['id'] ?? ''}',
            title: item['title'] as String? ?? '',
            artists: [item['user']?['username'] as String? ?? 'Unknown'],
            durationMs: (item['duration'] as num?)?.toInt(),
          ),
          item['user']?['username'] as String? ?? ''
        )
    ];
  } catch (_) {
    return const [];
  } finally {
    client.close();
  }
}

Future<String?> _scrapeClientId(HttpClient client) async {
  try {
    final homeReq =
        await client.getUrl(Uri.parse('https://soundcloud.com'));
    homeReq.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) '
        'Gecko/20100101 Firefox/140.0');
    final homeRes = await homeReq.close().timeout(const Duration(seconds: 6));
    final homeHtml = await utf8.decoder.bind(homeRes).join();
    final scriptRegex = RegExp(
        r'https://[a-z0-9-]+\.sndcdn\.com/[^"<>\s!]+\.js');
    final scripts = scriptRegex.allMatches(homeHtml).map((m) => m.group(0)!).toSet().toList();
    final idRegex =
        RegExp(r'client_?id[:=]"([A-Za-z0-9]{20,})"', caseSensitive: false);
    for (final scriptUrl in scripts.reversed) {
      try {
        final sReq = await client.getUrl(Uri.parse(scriptUrl));
        sReq.headers.set(
            'User-Agent',
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) '
            'Gecko/20100101 Firefox/140.0');
        final sRes = await sReq.close().timeout(const Duration(seconds: 5));
        if (sRes.statusCode == 200) {
          final js = await utf8.decoder.bind(sRes).join();
          final m = idRegex.firstMatch(js);
          if (m != null) return m.group(1);
        }
      } catch (_) {}
    }
  } catch (_) {}
  return null;
}
