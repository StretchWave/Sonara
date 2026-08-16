import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sonara/services/music_service.dart';
import 'package:sonara/ui/screens/Settings/settings_screen_controller.dart';
import 'package:sonara/ui/utils/theme_controller.dart';

/// Mocks the path_provider method channel so the controller can resolve
/// the support/documents directories in a plain Dart test.
void _mockPathProvider(String path) {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'getApplicationSupportDirectory':
      case 'getApplicationDocumentsDirectory':
      case 'getTemporaryDirectory':
      case 'getApplicationCacheDirectory':
      case 'getDownloadsDirectory':
        return path;
      default:
        return null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('settings_test');
    Hive.init(tempDir.path);
    await Hive.openBox('AppPrefs');
    _mockPathProvider(tempDir.path);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('SettingsScreenController', () {
    test('setters persist values to the AppPrefs box', () {
      final controller = SettingsScreenController();

      controller.toggleQobuzEnabled(true);
      controller.changeQobuzInstances('https://a.example\nhttps://b.example');
      controller.changeQobuzCountry('fr');
      controller.changeQobuzQuality(6);
      controller.toggleTidalEnabled(true);
      controller.changeTidalEndpoints('https://t.example');
      controller.changeTidalQuality('FLAC');
      controller.toggleSpotifyAutoFetchLyrics(false);
      controller.toggleSpotifyAutoEnrichTracks(false);

      final box = Hive.box('AppPrefs');
      expect(box.get('qobuzEnabled'), isTrue);
      expect(box.get('qobuzInstances'),
          'https://a.example\nhttps://b.example');
      expect(box.get('qobuzCountry'), 'FR');
      expect(box.get('qobuzQuality'), 6);
      expect(box.get('tidalEnabled'), isTrue);
      expect(box.get('tidalEndpoints'), 'https://t.example');
      expect(box.get('tidalQuality'), 'FLAC');
      expect(box.get('spotifyAutoFetchLyrics'), isFalse);
      expect(box.get('spotifyAutoEnrichTracks'), isFalse);

      // In-memory observables mirror the box.
      expect(controller.qobuzEnabled.value, isTrue);
      expect(controller.qobuzInstances.value,
          'https://a.example\nhttps://b.example');
      expect(controller.qobuzCountry.value, 'FR');
      expect(controller.qobuzQuality.value, 6);
      expect(controller.tidalEnabled.value, isTrue);
      expect(controller.tidalEndpoints.value, 'https://t.example');
      expect(controller.tidalQuality.value, 'FLAC');
      expect(controller.spotifyAutoFetchLyrics.value, isFalse);
      expect(controller.spotifyAutoEnrichTracks.value, isFalse);
    });

    test('reset to default clears the box and restores in-memory state', () async {
      final box = Hive.box('AppPrefs');
      box.putAll({
        'qobuzEnabled': true,
        'qobuzInstances': 'https://a.example',
        'tidalEnabled': true,
        'spotifyAutoFetchLyrics': false,
        'streamingQuality': 0,
        'themeModeType': 2,
        'discoverContentType': 'TR',
        'densityScale': 0.75,
        'cacheHomeScreenData': false,
      });
      final controller = SettingsScreenController();

      await controller.resetAppSettingsToDefault();

      // Persisted defaults are re-seeded.
      expect(box.get('qobuzEnabled'), isNull);
      expect(box.get('streamingQuality'), 1);
      expect(box.get('themeModeType'), 0);
      expect(box.get('discoverContentType'), 'REC');
      expect(box.get('cacheHomeScreenData'), isTrue);

      // In-memory observables reflect the defaults.
      expect(controller.qobuzEnabled.value, isFalse);
      expect(controller.qobuzInstances.value, isEmpty);
      expect(controller.qobuzCountry.value, 'US');
      expect(controller.qobuzQuality.value, 27);
      expect(controller.tidalEnabled.value, isFalse);
      expect(controller.tidalEndpoints.value, isEmpty);
      expect(controller.tidalQuality.value, 'LOSSLESS');
      expect(controller.spotifyAutoFetchLyrics.value, isTrue);
      expect(controller.spotifyAutoEnrichTracks.value, isTrue);
      expect(controller.streamingQuality.value, AudioQuality.High);
      expect(controller.themeModetype.value, ThemeType.dynamic);
      expect(controller.discoverContentType.value, 'REC');
      expect(controller.densityScale.value, 1.0);
      expect(controller.galaxyOverlayEnabled.value, isTrue);
      expect(controller.cacheHomeScreenData.value, isTrue);
    });

    test('reset survives a corrupt streamingQuality value', () async {
      Hive.box('AppPrefs').put('streamingQuality', 99);
      final controller = SettingsScreenController();

      await controller.resetAppSettingsToDefault();

      expect(controller.streamingQuality.value, AudioQuality.High);
      expect(Hive.box('AppPrefs').get('streamingQuality'), 1);
    });
  });
}
