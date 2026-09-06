import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// Mirrors the FIXED PlaylistScreenController: a GetxController with
/// GetTickerProviderStateMixin (multi-ticker) that disposes any previous
/// AnimationController before creating a new one in onInit, registered
/// per-route with a tag derived from a Key.
class _TickerController extends GetxController
    with GetTickerProviderStateMixin {
  AnimationController? _animationController;

  AnimationController get animationController => _animationController!;

  @override
  void onInit() {
    super.onInit();
    _animationController?.dispose();
    final animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animationController = animationController;
  }

  @override
  void onClose() {
    _animationController?.dispose();
    super.onClose();
  }
}

/// The OLD (broken) pattern: single-ticker mixin with no re-init guard.
/// Calling onInit twice on the same instance must throw "multiple tickers",
/// which is exactly the crash reported on the playlist screen.
class _BrokenTickerController extends GetxController
    with GetSingleTickerProviderStateMixin {
  late final AnimationController animationController;

  @override
  void onInit() {
    super.onInit();
    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void onClose() {
    animationController.dispose();
    super.onClose();
  }
}

const _navId = 1;
const _playlistRoute = '/playlist';

class _PlaylistPage extends StatelessWidget {
  const _PlaylistPage({super.key});
  @override
  Widget build(BuildContext context) {
    final tag = key.hashCode.toString();
    final controller = (Get.isRegistered<_TickerController>(tag: tag))
        ? Get.find<_TickerController>(tag: tag)
        : Get.put(_TickerController(), tag: tag);
    // Start the title animation like PlaylistScreenController does.
    controller.animationController.forward();
    return Scaffold(
      appBar: AppBar(title: const Text('playlist')),
      body: const Center(child: Text('playlist body')),
    );
  }
}

class _NestedNav extends StatelessWidget {
  const _NestedNav();
  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: Get.nestedKey(_navId),
      initialRoute: '/home',
      onGenerateRoute: (settings) {
        Get.routing.args = settings.arguments;
        switch (settings.name) {
          case _playlistRoute:
            final id = (settings.arguments as List)[1] as String;
            return GetPageRoute(
              page: () => _PlaylistPage(key: Key(id)),
              settings: settings,
            );
          default:
            return GetPageRoute(
              page: () => const Scaffold(body: Center(child: Text('home'))),
              settings: settings,
            );
        }
      },
    );
  }
}

Future<void> _openPlaylist(WidgetTester tester, String id) async {
  // Note: do NOT await the push future - it only completes when the route is
  // popped, which would deadlock the test.
  Get.toNamed(_playlistRoute, id: _navId, arguments: [null, id]);
  await tester.pumpAndSettle();
}

Future<void> _closePlaylist(WidgetTester tester) async {
  Get.nestedKey(_navId)!.currentState!.pop();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Get.reset();
  });

  tearDown(() {
    Get.reset();
  });

  test('old single-ticker pattern throws when onInit runs twice', () {
    // Documents the crash: a recycled controller that is initialized again
    // creates a second AnimationController and trips the single-ticker
    // assertion (the _ticker is never cleared by the mixin).
    final controller = _BrokenTickerController();
    controller.onInit();
    expect(() => controller.onInit(), throwsA(isA<FlutterError>()));
  });

  test('fixed pattern survives onInit running twice on the same instance', () {
    final controller = _TickerController();
    controller.onInit();
    // Second initialization on the same instance: the previous animation
    // controller is disposed first and the multi-ticker provider accepts the
    // new one, so no "multiple tickers" error is thrown.
    expect(() => controller.onInit(), returnsNormally);
    expect(controller.animationController, isNotNull);
    // Closing must also be clean (no "disposed with an active Ticker").
    expect(() => controller.onClose(), returnsNormally);
  });

  testWidgets('open -> pop -> reopen same playlist stays healthy',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const GetMaterialApp(home: _NestedNav()),
    );
    await tester.pumpAndSettle();

    await _openPlaylist(tester, 'A');
    final tag = const Key('A').hashCode.toString();
    expect(Get.isRegistered<_TickerController>(tag: tag), isTrue);

    await _closePlaylist(tester);
    expect(Get.isRegistered<_TickerController>(tag: tag), isFalse);

    // Reopen the same playlist: must not create a second ticker on a
    // recycled instance.
    await _openPlaylist(tester, 'A');
    expect(tester.takeException(), isNull);

    await _closePlaylist(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid pop then immediate reopen of same playlist',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const GetMaterialApp(home: _NestedNav()),
    );
    await tester.pumpAndSettle();

    await _openPlaylist(tester, 'B');

    // Pop but do NOT settle: re-open while the pop transition is still
    // running (the route hasn't been disposed yet).
    Get.nestedKey(_navId)!.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 50));
    await _openPlaylist(tester, 'B');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('two different playlists are independent',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const GetMaterialApp(home: _NestedNav()),
    );
    await tester.pumpAndSettle();

    await _openPlaylist(tester, 'C');
    await _openPlaylist(tester, 'D');
    expect(tester.takeException(), isNull);

    await _closePlaylist(tester);
    await _closePlaylist(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replace a playlist route with the same playlist',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const GetMaterialApp(home: _NestedNav()),
    );
    await tester.pumpAndSettle();

    await _openPlaylist(tester, 'E');
    Get.toNamed(_playlistRoute,
        id: _navId, arguments: [null, 'E'], preventDuplicates: false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
