import 'dart:convert';

import 'package:hive/hive.dart';

/// Settings that control how streams are routed: which providers are
/// enabled, their configuration, and remembered match overrides.
///
/// Built in the main isolate from Hive settings and passed (as JSON) into
/// background isolates, where Hive is unavailable.
class StreamRouteConfig {
  final bool qobuzEnabled;

  /// Raw resolver instance URLs (Kenny-style), one per line/entry.
  final List<String> qobuzInstances;

  final String qobuzCountry;

  /// Qobuz quality code: 27 = Hi-Res, 7 = 24-bit, 6 = CD FLAC, 5 = MP3 320.
  final int qobuzQuality;

  final bool tidalEnabled;

  /// Raw Tidal resolver endpoint URLs, one per line/entry.
  final List<String> tidalEndpoints;

  /// Desired Tidal quality: HI_RES_LOSSLESS, LOSSLESS, HIGH or LOW.
  final String tidalQuality;

  /// Remembered manual match corrections: `providerId::mediaId` → trackId.
  final Map<String, String> matchOverrides;

  const StreamRouteConfig({
    this.qobuzEnabled = false,
    this.qobuzInstances = const [],
    this.qobuzCountry = 'US',
    this.qobuzQuality = 27,
    this.tidalEnabled = false,
    this.tidalEndpoints = const [],
    this.tidalQuality = 'LOSSLESS',
    this.matchOverrides = const {},
  });

  /// Reads the current configuration from the AppPrefs Hive box.
  static StreamRouteConfig fromSettings() {
    final prefs = Hive.box('AppPrefs');
    final instancesRaw =
        (prefs.get('qobuzInstances', defaultValue: '') as String?) ?? '';
    final instances = instancesRaw
        .split(RegExp(r'[\n\r,; \t]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final qualityRaw = prefs.get('qobuzQuality', defaultValue: 27);
    final tidalEndpointsRaw =
        (prefs.get('tidalEndpoints', defaultValue: '') as String?) ?? '';
    final tidalEndpoints = tidalEndpointsRaw
        .split(RegExp(r'[\n\r,; \t]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final overrides = <String, String>{};
    final rawOverrides = prefs.get('providerMatchOverrides');
    if (rawOverrides is Map) {
      rawOverrides.forEach((key, value) {
        if (key != null && value != null) overrides['$key'] = '$value';
      });
    }
    return StreamRouteConfig(
      qobuzEnabled: prefs.get('qobuzEnabled', defaultValue: false) == true,
      qobuzInstances: instances,
      qobuzCountry:
          (prefs.get('qobuzCountry', defaultValue: 'US') as String?) ?? 'US',
      qobuzQuality: qualityRaw is int ? qualityRaw : 27,
      tidalEnabled: prefs.get('tidalEnabled', defaultValue: false) == true,
      tidalEndpoints: tidalEndpoints,
      tidalQuality: (prefs.get('tidalQuality', defaultValue: 'LOSSLESS') as String?) ??
          'LOSSLESS',
      matchOverrides: overrides,
    );
  }

  Map<String, dynamic> toJson() => {
        'qobuzEnabled': qobuzEnabled,
        'qobuzInstances': qobuzInstances,
        'qobuzCountry': qobuzCountry,
        'qobuzQuality': qobuzQuality,
        'tidalEnabled': tidalEnabled,
        'tidalEndpoints': tidalEndpoints,
        'tidalQuality': tidalQuality,
        'matchOverrides': matchOverrides,
      };

  String toJsonString() => jsonEncode(toJson());

  factory StreamRouteConfig.fromJsonString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) return const StreamRouteConfig();
    final quality = decoded['qobuzQuality'];
    final overrides = decoded['matchOverrides'];
    return StreamRouteConfig(
      qobuzEnabled: decoded['qobuzEnabled'] == true,
      qobuzInstances: (decoded['qobuzInstances'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
      qobuzCountry: (decoded['qobuzCountry'] as String?) ?? 'US',
      qobuzQuality: quality is int ? quality : 27,
      tidalEnabled: decoded['tidalEnabled'] == true,
      tidalEndpoints: (decoded['tidalEndpoints'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
      tidalQuality: (decoded['tidalQuality'] as String?) ?? 'LOSSLESS',
      matchOverrides: overrides is Map
          ? overrides.map((key, value) => MapEntry('$key', '$value'))
          : const {},
    );
  }
}
