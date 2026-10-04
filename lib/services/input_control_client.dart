import 'dart:async';

import 'package:flutter/services.dart';

/// Sole Dart access path to the native-owned `inputControlEnabled` flag.
///
/// Native ([InputControlStore]) persists the flag in Jetpack DataStore and
/// exposes it as a `StateFlow`. Dart never persists its own copy (no Hive,
/// no `shared_preferences`): reads/writes go through the MethodChannel and
/// live updates arrive via the EventChannel.
class InputControlClient {
  static const MethodChannel _method =
      MethodChannel('com.sonara.music/inputControl');
  static const EventChannel _events =
      EventChannel('com.sonara.music/inputControlEvents');

  /// Current native value (defaults to true before the engine is ready).
  Future<bool> get() async {
    try {
      final value = await _method.invokeMethod<bool>(
        'getInputControlEnabled',
      );
      return value ?? true;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  /// Persists natively; the native gating collector and [watch] emit it back.
  Future<void> set(bool enabled) async {
    try {
      await _method.invokeMethod(
        'setInputControlEnabled',
        {'enabled': enabled},
      );
    } on MissingPluginException {
      // Non-Android platforms: no-op, controls stay enabled.
    } on PlatformException {
      // Best effort; Dart keeps last known value via watch fallback.
    }
  }

  /// Live native values. Emits nothing on non-Android platforms.
  Stream<bool> watch() {
    try {
      return _events.receiveBroadcastStream().map((event) {
        if (event is bool) return event;
        return true;
      }).handleError((Object _) {});
    } on MissingPluginException {
      return const Stream.empty();
    }
  }
}
