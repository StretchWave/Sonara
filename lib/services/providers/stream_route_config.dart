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

  final bool soundcloudEnabled;

  /// Free lossless FLAC fallback from archive.org (concerts, classical,
  /// CC/netlabel releases). Tried after every configured source.
  final bool internetArchiveEnabled;

  final bool deezerEnabled;

  /// Raw Deezer resolver endpoint URLs, one per line/entry.
  final List<String> deezerEndpoints;

  /// Desired Deezer quality: FLAC, MP3_320, or MP3_128.
  final String deezerQuality;

  final bool appleEnabled;

  /// Raw Apple Music resolver endpoint URLs, one per line/entry.
  final List<String> appleEndpoints;

  final bool amazonEnabled;

  /// Raw Amazon Music resolver endpoint URLs, one per line/entry.
  final List<String> amazonEndpoints;

  /// Desired Amazon Music quality: HI_RES, LOSSLESS, or HIGH.
  final String amazonQuality;

  final bool instagramEnabled;

  /// Instagram session cookie for authentication.
  final String instagramCookie;

  /// Remembered manual match corrections: `providerId::mediaId` → trackId.
  final Map<String, String> matchOverrides;

  /// YouTube visitor data ("X-Goog-Visitor-Id") used by InnerTube clients
  /// that require it (VISIONOS) to return playable, non-range-gated streams.
  final String visitorId;

  /// Provider priority order: the first entry is used first, then the
  /// second, and so on.  Only providers that are enabled and configured
  /// take part; entries for unknown/disabled providers are ignored.
  final List<String> providerOrder;

  /// Default priority order (preserves the historical cascade).
  static const List<String> defaultProviderOrder = [
    'qobuz',
    'tidal',
    'deezer',
    'apple',
    'amazon',
    'youtube_music',
    'soundcloud',
    'instagram',
    'internet_archive',
  ];

  const StreamRouteConfig({
    this.qobuzEnabled = false,
    this.qobuzInstances = const [],
    this.qobuzCountry = 'US',
    this.qobuzQuality = 27,
    this.tidalEnabled = false,
    this.tidalEndpoints = const [],
    this.tidalQuality = 'LOSSLESS',
    this.soundcloudEnabled = true,
    this.internetArchiveEnabled = true,
    this.deezerEnabled = false,
    this.deezerEndpoints = const [],
    this.deezerQuality = 'FLAC',
    this.appleEnabled = false,
    this.appleEndpoints = const [],
    this.amazonEnabled = false,
    this.amazonEndpoints = const [],
    this.amazonQuality = 'HI_RES',
    this.instagramEnabled = false,
    this.instagramCookie = '',
    this.matchOverrides = const {},
    this.visitorId = '',
    this.providerOrder = defaultProviderOrder,
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

    // Deezer settings
    final deezerEndpointsRaw =
        (prefs.get('deezerEndpoints', defaultValue: '') as String?) ?? '';
    final deezerEndpoints = deezerEndpointsRaw
        .split(RegExp(r'[\n\r,; \t]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Apple Music settings
    final appleEndpointsRaw =
        (prefs.get('appleEndpoints', defaultValue: '') as String?) ?? '';
    final appleEndpoints = appleEndpointsRaw
        .split(RegExp(r'[\n\r,; \t]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Amazon Music settings
    final amazonEndpointsRaw =
        (prefs.get('amazonEndpoints', defaultValue: '') as String?) ?? '';
    final amazonEndpoints = amazonEndpointsRaw
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
    final rawOrder = prefs.get('providerOrder');
    final providerOrder = rawOrder is List && rawOrder.whereType<String>().isNotEmpty
        ? rawOrder.whereType<String>().toList()
        : defaultProviderOrder;
    String visitorId = '';
    final visitorData = prefs.get('visitorId');
    if (visitorData is Map && visitorData['id'] is String) {
      visitorId = visitorData['id'] as String;
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
      soundcloudEnabled:
          prefs.get('soundcloudEnabled', defaultValue: true) == true,
      internetArchiveEnabled: prefs.get('internetArchiveEnabled',
              defaultValue: true) ==
          true,
      deezerEnabled: prefs.get('deezerEnabled', defaultValue: false) == true,
      deezerEndpoints: deezerEndpoints,
      deezerQuality:
          (prefs.get('deezerQuality', defaultValue: 'FLAC') as String?) ?? 'FLAC',
      appleEnabled: prefs.get('appleEnabled', defaultValue: false) == true,
      appleEndpoints: appleEndpoints,
      amazonEnabled: prefs.get('amazonEnabled', defaultValue: false) == true,
      amazonEndpoints: amazonEndpoints,
      amazonQuality:
          (prefs.get('amazonQuality', defaultValue: 'HI_RES') as String?) ?? 'HI_RES',
      instagramEnabled: prefs.get('instagramEnabled', defaultValue: false) == true,
      instagramCookie:
          (prefs.get('instagramCookie', defaultValue: '') as String?) ?? '',
      matchOverrides: overrides,
      visitorId: visitorId,
      providerOrder: providerOrder,
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
        'soundcloudEnabled': soundcloudEnabled,
        'internetArchiveEnabled': internetArchiveEnabled,
        'deezerEnabled': deezerEnabled,
        'deezerEndpoints': deezerEndpoints,
        'deezerQuality': deezerQuality,
        'appleEnabled': appleEnabled,
        'appleEndpoints': appleEndpoints,
        'amazonEnabled': amazonEnabled,
        'amazonEndpoints': amazonEndpoints,
        'amazonQuality': amazonQuality,
        'instagramEnabled': instagramEnabled,
        'instagramCookie': instagramCookie,
        'matchOverrides': matchOverrides,
        'visitorId': visitorId,
        'providerOrder': providerOrder,
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
      soundcloudEnabled: decoded['soundcloudEnabled'] != false,
      internetArchiveEnabled: decoded['internetArchiveEnabled'] != false,
      deezerEnabled: decoded['deezerEnabled'] == true,
      deezerEndpoints: (decoded['deezerEndpoints'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
      deezerQuality: (decoded['deezerQuality'] as String?) ?? 'FLAC',
      appleEnabled: decoded['appleEnabled'] == true,
      appleEndpoints: (decoded['appleEndpoints'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
      amazonEnabled: decoded['amazonEnabled'] == true,
      amazonEndpoints: (decoded['amazonEndpoints'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
      amazonQuality: (decoded['amazonQuality'] as String?) ?? 'HI_RES',
      instagramEnabled: decoded['instagramEnabled'] == true,
      instagramCookie: (decoded['instagramCookie'] as String?) ?? '',
      matchOverrides: overrides is Map
          ? overrides.map((key, value) => MapEntry('$key', '$value'))
          : const {},
      visitorId: (decoded['visitorId'] as String?) ?? '',
      providerOrder: (decoded['providerOrder'] as List?)
              ?.whereType<String>()
              .toList() ??
          defaultProviderOrder,
    );
  }
}
