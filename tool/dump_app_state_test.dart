// Dumps the real app state: AppPrefs settings, prevSessionData, and
// SongsUrlCache entries for the recently played songs.
// Run with:  flutter test tool/dump_app_state_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('dump app state', () async {
    final dbDir = '${Platform.environment['APPDATA']}/Sonara/Sonara/db';
    Hive.init(dbDir);

    final prefs = await Hive.openBox('AppPrefs');
    print('=== AppPrefs (${prefs.length} keys) ===');
    prefs.toMap().forEach((k, v) => print('  $k = $v'));
    await prefs.close();

    final session = await Hive.openBox('prevSessionData');
    print('=== prevSessionData ===');
    session.toMap().forEach((k, v) {
      if (k == 'queue') {
        final list = v as List;
        print('  queue (${list.length} items):');
        for (final item in list.take(5)) {
          print('    id=${item['videoId']} title=${item['title']}');
        }
      } else {
        print('  $k = $v');
      }
    });
    await session.close();

    final cache = await Hive.openBox('SongsUrlCache');
    print('=== SongsUrlCache (${cache.length} entries) ===');
    for (final key in cache.keys) {
      final v = cache.get(key);
      final s = v.toString();
      final isLocal = s.contains('127.0.0.1') || s.contains('localhost');
      final hasExpire = s.contains('expire=');
      String? host;
      final m = RegExp(r'https?://([^/]+)').firstMatch(s);
      if (m != null) host = m[1];
      print('  key=$key host=$host local=$isLocal expire=$hasExpire len=${s.length}');
      if (isLocal) print('    VALUE: $s');
    }
    await cache.close();
  });
}
