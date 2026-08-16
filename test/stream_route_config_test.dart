import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sonara/services/providers/stream_route_config.dart';
import 'package:sonara/services/providers/stream_router.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
  });

  test('reads settings from the AppPrefs box', () async {
    await Hive.openBox('AppPrefs');
    final box = Hive.box('AppPrefs');
    box.put('qobuzEnabled', true);
    box.put('qobuzInstances', 'https://a.example\nhttps://b.example');
    box.put('qobuzCountry', 'de');
    box.put('qobuzQuality', 7);
    box.put('tidalEnabled', true);
    box.put('tidalEndpoints', 'https://t.example');
    box.put('tidalQuality', 'HI_RES_LOSSLESS');

    final config = StreamRouteConfig.fromSettings();

    expect(config.qobuzEnabled, isTrue);
    expect(config.qobuzInstances, ['https://a.example', 'https://b.example']);
    expect(config.qobuzCountry, 'de');
    expect(config.qobuzQuality, 7);
    expect(config.tidalEnabled, isTrue);
    expect(config.tidalEndpoints, ['https://t.example']);
    expect(config.tidalQuality, 'HI_RES_LOSSLESS');
  });

  test('JSON roundtrip preserves all fields', () {
    const config = StreamRouteConfig(
      qobuzEnabled: true,
      qobuzInstances: ['https://a.example'],
      qobuzCountry: 'FR',
      qobuzQuality: 27,
      tidalEnabled: true,
      tidalEndpoints: ['https://t.example'],
      tidalQuality: 'HIGH',
      matchOverrides: {'qobuz::x': '42'},
    );

    final restored = StreamRouteConfig.fromJsonString(config.toJsonString());

    expect(restored.qobuzEnabled, isTrue);
    expect(restored.qobuzInstances, ['https://a.example']);
    expect(restored.qobuzCountry, 'FR');
    expect(restored.qobuzQuality, 27);
    expect(restored.tidalEnabled, isTrue);
    expect(restored.tidalEndpoints, ['https://t.example']);
    expect(restored.tidalQuality, 'HIGH');
    expect(restored.matchOverrides['qobuz::x'], '42');
  });

  test('empty config defaults to YouTube-only routing', () {
    final config = StreamRouteConfig.fromJsonString('{}');
    expect(config.qobuzEnabled, isFalse);
    expect(config.qobuzInstances, isEmpty);
    final router = StreamRouter.build(config);
    expect(router.providers.map((p) => p.id), ['youtube_music']);
  });

  test('build includes Qobuz and Tidal before YouTube when enabled', () {
    const config = StreamRouteConfig(
      qobuzEnabled: true,
      qobuzInstances: ['https://a.example'],
      tidalEnabled: true,
      tidalEndpoints: ['https://t.example'],
    );
    final router = StreamRouter.build(config);
    expect(router.providers.map((p) => p.id),
        ['qobuz', 'tidal', 'youtube_music']);
  });
}
