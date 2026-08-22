// Debugs why songs resolve but don't play.
// Run with:  flutter test tool/live_playback_debug_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/background_task.dart';
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

Future<void> _probeUrl(String url, {Map<String, String>? headers}) async {
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(url));
      headers?.forEach((k, v) => req.headers.set(k, v));
      req.headers.set('Range', 'bytes=0-2047');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final bytes = await res
          .fold<List<int>>([], (acc, chunk) => acc..addAll(chunk))
          .timeout(const Duration(seconds: 10));
      final head = bytes.take(16).toList();
      final hex = head.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      print('    HTTP ${res.statusCode} got=${bytes.length}B magic=[$hex] '
          'content-type=${res.headers.value('content-type')}');
    } finally {
      client.close();
    }
  } catch (e) {
    print('    PROBE ERROR: $e');
  }
}

void main() {
  HttpOverrides.global = _AllowAllHttpOverrides();

  test('full playback resolution path', () async {
    const songId = '-BJt4fCAtZE';
    const song = SongQuery(
      mediaId: '-BJt4fCAtZE',
      title: 'Arz Kiya Hai',
      artists: ['Anuv Jain'],
    );

    // 1. Direct router fetch (what the isolate does)
    print('=== 1. StreamRouter.fetch ===');
    final config = StreamRouteConfig.fromJsonString('{}');
    final provider = await StreamRouter.build(config)
        .fetch(songId, song: const SongQuery(mediaId: songId));
    print('  playable=${provider.playable} status=${provider.statusMSG}');
    print('  formats=${provider.audioFormats?.length}');
    if (provider.audioFormats != null) {
      for (final f in provider.audioFormats!) {
        print('    itag=${f.itag} codec=${f.audioCodec} bitrate=${f.bitrate} '
            'url=${f.url.length > 70 ? f.url.substring(0, 70) + '...' : f.url}');
        print('    headers=${f.headers}');
        await _probeUrl(f.url, headers: f.headers);
        break;
      }
    }

    // 2. Simulate the isolate getStreamInfo -> hmStreamingData
    print('=== 2. getStreamInfo (isolate path) ===');
    final json = await getStreamInfo(
      songId,
      RootIsolateToken.instance,
      configJson: '{}',
      songJson: song.toJson(),
    );
    print('  result keys=${json.keys.toList()}');
    print('  playable=${json['playable']} status=${json['statusMSG']}');
    final low = json['lowQualityAudio'];
    final high = json['highQualityAudio'];
    print('  low=$low');
    print('  high=$high');
    final hq = high is Map ? high['url'] : null;
    if (hq is String && hq.isNotEmpty) {
      final headers = high['headers'] is Map
          ? Map<String, String>.from(high['headers'] as Map)
          : null;
      await _probeUrl(hq, headers: headers);
    }
  });
}
