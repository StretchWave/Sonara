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

  test('reads providerOrder from the AppPrefs box', () async {
    await Hive.openBox('AppPrefs');
    final box = Hive.box('AppPrefs');
    box.put('providerOrder', ['soundcloud', 'youtube_music', 'qobuz']);

    final config = StreamRouteConfig.fromSettings();

    expect(config.providerOrder, ['soundcloud', 'youtube_music', 'qobuz']);
  });

  test('providerOrder defaults to the historical cascade', () {
    const config = StreamRouteConfig();
    expect(config.providerOrder, StreamRouteConfig.defaultProviderOrder);
  });

  test('empty config defaults to YouTube and SoundCloud routing', () {
    final config = StreamRouteConfig.fromJsonString('{}');
    expect(config.qobuzEnabled, isFalse);
    expect(config.qobuzInstances, isEmpty);
    expect(config.soundcloudEnabled, isTrue);
    final router = StreamRouter.build(config);
    expect(router.providers.map((p) => p.id),
        ['youtube_music', 'soundcloud', 'internet_archive']);
  });

  test('build includes Qobuz and Tidal before YouTube and SoundCloud when enabled', () {
    const config = StreamRouteConfig(
      qobuzEnabled: true,
      qobuzInstances: ['https://a.example'],
      tidalEnabled: true,
      tidalEndpoints: ['https://t.example'],
    );
    final router = StreamRouter.build(config);
    expect(router.providers.map((p) => p.id), [
      'qobuz',
      'tidal',
      'youtube_music',
      'soundcloud',
      'internet_archive'
    ]);
  });

  test('build sorts providers by the configured priority order', () {
    const config = StreamRouteConfig(
      qobuzEnabled: true,
      qobuzInstances: ['https://q.example'],
      tidalEnabled: true,
      tidalEndpoints: ['https://t.example'],
      deezerEnabled: true,
      deezerEndpoints: ['https://d.example'],
      amazonEnabled: true,
      amazonEndpoints: ['https://a.example'],
      soundcloudEnabled: true,
      providerOrder: [
        'amazon',
        'deezer',
        'youtube_music',
        'qobuz',
        'tidal',
        'soundcloud',
      ],
    );
    final router = StreamRouter.build(config);
    expect(router.providers.map((p) => p.id), [
      'amazon',
      'deezer',
      'youtube_music',
      'qobuz',
      'tidal',
      'soundcloud',
      'internet_archive'
    ]);
  });

  test('Apple, Deezer and Amazon are included when just enabled (defaults)', () {
    const config = StreamRouteConfig(
      deezerEnabled: true,
      appleEnabled: true,
      amazonEnabled: true,
    );
    final router = StreamRouter.build(config);
    expect(router.providers.map((p) => p.id), [
      'deezer',
      'apple',
      'amazon',
      'youtube_music',
      'soundcloud',
      'internet_archive'
    ]);
  });

  test('disabled providers are skipped even when listed first in priority', () {
    const config = StreamRouteConfig(
      qobuzEnabled: true,
      qobuzInstances: ['https://q.example'],
      providerOrder: ['tidal', 'qobuz', 'youtube_music'],
    );
    final router = StreamRouter.build(config);
    // SoundCloud is enabled by default and not listed, so it trails at the end.
    expect(router.providers.map((p) => p.id),
        ['qobuz', 'youtube_music', 'soundcloud', 'internet_archive']);
  });
}
