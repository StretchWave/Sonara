import 'package:hive/hive.dart';

/// Persists user corrections for automatic cross-catalog matching:
/// providerId::mediaId → chosen track id in that provider's catalog.
class MatchOverrideStore {
  MatchOverrideStore._();

  static const String _prefsKey = 'providerMatchOverrides';

  static Map<String, String> _read() {
    final raw = Hive.box('AppPrefs').get(_prefsKey);
    if (raw is Map) return Map<String, String>.from(raw);
    return const {};
  }

  static String? getOverride(String providerId, String mediaId) =>
      _read()['$providerId::$mediaId'];

  static void setOverride(String providerId, String mediaId, String trackId) {
    final overrides = _read();
    overrides['$providerId::$mediaId'] = trackId;
    Hive.box('AppPrefs').put(_prefsKey, overrides);
  }

  static void clearOverride(String providerId, String mediaId) {
    final overrides = _read();
    overrides.remove('$providerId::$mediaId');
    Hive.box('AppPrefs').put(_prefsKey, overrides);
  }
}
