import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:sonara/ui/screens/Settings/components/configure_sources_screen.dart';
import 'package:sonara/ui/screens/Settings/settings_screen_controller.dart';
import 'package:sonara/ui/utils/theme_controller.dart';

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

void _mockWinTitlebar() {
  const channel = MethodChannel('win_titlebar_color');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('configure_sources_test');
    Hive.init(tempDir.path);
    await Hive.openBox('AppPrefs');
    await Hive.openBox('appPrefs');
    _mockPathProvider(tempDir.path);
    _mockWinTitlebar();
    Get.testMode = true;
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('win_titlebar_color'), null);
    Get.reset();
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('ConfigureSourcesScreen renders without error and toggles sources',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    Get.put(ThemeController());
    final controller = Get.put(SettingsScreenController());

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const ConfigureSourcesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Configure sources'), findsOneWidget);
    expect(find.text('Qobuz (no login, resolver-based)'), findsOneWidget);
    expect(find.text('Tidal (no login, resolver-based)'), findsOneWidget);
    expect(find.text('Deezer (resolver-based)'), findsOneWidget);
    expect(find.text('Apple Music (resolver-based)'), findsOneWidget);
    expect(find.text('Amazon Music (resolver-based)'), findsOneWidget);
    expect(find.text('SoundCloud'), findsOneWidget);
    expect(find.text('Internet Archive'), findsOneWidget);
    expect(find.text('Instagram Audio (Reels/Clips)'), findsOneWidget);

    // Toggle Deezer on
    controller.toggleDeezerEnabled(true);
    await tester.pumpAndSettle();

    expect(controller.deezerEnabled.value, isTrue);
    expect(find.text('Stream quality'), findsWidgets);
  });
}
