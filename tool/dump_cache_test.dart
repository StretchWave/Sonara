// Dumps the full cached entry for the failing song with expiry info.
// Run with:  flutter test tool/dump_cache_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  test('dump SongsUrlCache entry', () async {
    final dbDir = '${Platform.environment['APPDATA']}/Sonara/Sonara/db';
    Hive.init(dbDir);
    final box = await Hive.openBox('SongsUrlCache');
    print('box has ${box.length} entries');
    for (final songId in ['-BJt4fCAtZE', 'eWNqzgPr6S0', '0t0HtFYjcU8']) {
      if (box.containsKey(songId)) {
        final v = box.get(songId);
        print('=== cached entry for $songId ===');
        final s = v.toString();
        final expireMatch = RegExp(r'expire=(\d+)').firstMatch(s);
        if (expireMatch != null) {
          final expire = int.parse(expireMatch[1]!);
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          print('  expire=$expire now=$now delta_s=${expire - now} '
              'valid=${now + 1800 < expire}');
        }
        final low = v['lowQualityAudio'];
        final high = v['highQualityAudio'];
        print('  low=${low?['url']}');
        print('  high=${high?['url']}');
        print('  headers=${high?['headers']}');
        print('  label=${high?['label']}');
        print('  itag=${high?['itag']} mime=${high?['mimeType']}');
      } else {
        print('$songId NOT in cache');
      }
    }
    await box.close();
  });
}
