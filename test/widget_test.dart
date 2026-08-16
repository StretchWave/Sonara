import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:harmonymusic/ui/player/components/galaxy_background.dart';
import 'package:harmonymusic/ui/screens/Statistics/statistics_screen.dart'
    show formatListeningTime;

class _ThemeLikeController extends GetxController {
  final themedata = 1.0.obs;
}

class _SettingsLikeController extends GetxController {
  final densityScale = 1.0.obs;
}

void main() {
  group('formatListeningTime', () {
    test('formats seconds only', () {
      expect(formatListeningTime(0), '0s');
      expect(formatListeningTime(15000), '15s');
    });

    test('formats minutes and seconds', () {
      expect(formatListeningTime(65000), '1m 5s');
      expect(formatListeningTime(600000), '10m 0s');
    });

    test('formats hours and minutes', () {
      expect(formatListeningTime(3600000), '1h 0m');
      expect(formatListeningTime(4525000), '1h 15m');
    });
  });

  testWidgets('GalaxyOverlay renders and animates without exceptions',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(child: GalaxyOverlay()),
        ),
      ),
    );
    await tester.pump();
    // Let the animation controller advance a few frames.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.byType(GalaxyOverlay), findsOneWidget);
  });

  testWidgets('nested GetX builders must read observables in their own scope',
      (WidgetTester tester) async {
    // Regression test: GetX throws "improper use of a GetX" when a builder
    // runs without reading any observable. The app's MaterialApp builder
    // nests GetX<ThemeController> inside GetX<SettingsScreenController>, so
    // both builders must read at least one observable.
    Get.put(_ThemeLikeController());
    Get.put(_SettingsLikeController());

    await tester.pumpWidget(
      GetMaterialApp(
        home: GetX<_ThemeLikeController>(
          builder: (controller) {
            // Read in this builder's own scope (like the fixed main.dart).
            final themeData = controller.themedata.value;
            return GetX<_SettingsLikeController>(
              builder: (settings) {
                final scale = settings.densityScale.value * themeData;
                return Text('scale $scale');
              },
            );
          },
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('scale 1.0'), findsOneWidget);
  });
}
