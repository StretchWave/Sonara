import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../../utils/helper.dart';

/// Signed-in YouTube Music session for added personal surfaces
/// (home feed, liked playlists/albums/artists, LZ/`LM` liked songs).
class YtAccountService extends GetxService {
  /// Google sign-in landing straight back onto YouTube Music, the same
  /// entry the web player uses.
  static const loginUrl =
      'https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F';

  static const ytmOrigin = 'https://music.youtube.com';
  static const _prefsKey = 'ytm';

  final isLoggedIn = false.obs;
  final cookieHeader = ''.obs;
  final accountLabel = 'YouTube Music'.obs;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  void _load() {
    try {
      final stored = Hive.box('AppPrefs').get(_prefsKey);
      if (stored is Map && (stored['cookie'] as String?)?.isNotEmpty == true) {
        cookieHeader.value = stored['cookie'];
        accountLabel.value = stored['label'] as String? ?? 'YouTube Music';
        isLoggedIn.value = true;
      }
    } catch (e) {
      printERROR("YtAccountService load error: $e");
    }
  }

  /// Merges harvested cookies over the stored jar. New values win so a
  /// re-login refreshes rotated names (SID/HSID/SSID/...). Returns true
  /// when at least one SAPISID alias was present, i.e. requests will
  /// authenticate.
  bool applyCookies(Map<String, String> incoming) {
    if (incoming.isEmpty) return false;
    final merged = <String, String>{};
    try {
      final stored = Hive.box('AppPrefs').get(_prefsKey);
      if (stored is Map) {
        for (final kv in stored['cookie'].toString().split(';')) {
          final parts = kv.split('=');
          if (parts.length >= 2) {
            merged[parts.first.trim()] = parts.sublist(1).join('=').trim();
          }
        }
      }
    } catch (_) {}
    merged.removeWhere((k, v) => v.isEmpty);
    merged.addAll(incoming);

    final cookie = merged.entries.map((e) => "${e.key}=${e.value}").join('; ');
    if (sapisidFromCookie(cookie) == null) {
      printERROR(
          "YtAccountService: no SAPISID in harvested cookies, keeping previous session");
      return false;
    }
    _persist(cookie);
    return true;

  }

  void _persist(String cookie) {
    try {
      Hive.box('AppPrefs').put(_prefsKey, {
        'cookie': cookie,
        'label': accountLabel.value,
      });
    } catch (e) {
      printERROR("YtAccountService persist error: $e");
    }
    cookieHeader.value = cookie;
    isLoggedIn.value = cookie.isNotEmpty;
  }

  void signOut() {
    try {
      Hive.box('AppPrefs').delete(_prefsKey);
    } catch (_) {}
    cookieHeader.value = '';
    isLoggedIn.value = false;
  }

  static String? sapisidFromCookie(String cookie) {
    for (final kv in cookie.split(';')) {
      final parts = kv.split('=');
      if (parts.length >= 2) {
        final name = parts.first.trim();
        final value = parts.sublist(1).join('=').trim();
        if ((name == 'SAPISID' ||
                name == '__Secure-1PAPISID' ||
                name == '__Secure-3PAPISID') &&
            value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  /// `Authorization: SAPISIDHASH <epoch>_<sha1("<epoch> <sapisid> <origin">)`,
  /// regenerated per request as YouTube bounds it to fresh epochs.
  static String sapisidHash(String sapisid, {int? epochSeconds}) {
    final epoch = epochSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final digest =
        sha1.convert(utf8.encode('$epoch $sapisid $ytmOrigin')).toString();
    return 'SAPISIDHASH ${epoch}_$digest';
  }
}
