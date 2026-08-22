// Probes whether resolution for the failing song produces a localhost URL.
// Run with:  flutter test tool/live_localhost_probe_test.dart
// (Use --dart-define=FLUTTER_TEST=true if needed; network access required.)

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
  HttpOverrides.global = _AllowAllHttpOverrides();

  test('resolve exact failing song and print every URL', () async {
    const songId = 'eWNqzgPr6S0';
    const song = SongQuery(
      mediaId: songId,
      title: 'MERA RANG DE BASANTI CHOLA',
    );

    final config = StreamRouteConfig.fromJsonString('{}');
    final provider =
        await StreamRouter.build(config).fetch(songId, song: song);
    print('playable=${provider.playable} status=${provider.statusMSG}');
    final formats = provider.audioFormats ?? [];
    print('formats=${formats.length}');
    for (final f in formats) {
      print('itag=${f.itag} codec=${f.audioCodec} bitrate=${f.bitrate}');
      print('FULL URL: ${f.url}');
      final uri = Uri.tryParse(f.url);
      print('HOST: ${uri?.host}:${uri?.port}');
    }
  });
}
