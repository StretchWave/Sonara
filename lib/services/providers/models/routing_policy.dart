/// Routing policy — centralizes playback/download intent, provider
/// preferences, and quality decisions instead of scattering them in
/// MyAudioHandler and Downloader.
library;

import 'match_decision.dart';
import 'provider_id.dart';

/// User intent for a playback or download request.
enum RequestIntent {
  /// Play/download the exact selected recording.
  exactRecording,

  /// Prefer the best available quality.
  bestQuality,

  /// Prefer the fastest startup / download.
  fastest,

  /// Use a specific preferred provider.
  preferredProvider,

  /// Let the system decide (default).
  automatic,
}

/// Quality preference for routing.
enum QualityPreference {
  /// Hi-Res > lossless > lossy.
  hiRes,

  /// Lossless (CD quality) > lossy.
  lossless,

  /// Prefer smaller/faster streams.
  standard,

  /// Any playable quality.
  any,
}

/// Duration tolerance for matching.
class DurationTolerancePolicy {
  /// Maximum absolute difference in seconds for acceptance.
  final int maxAbsoluteDiffSec;

  /// Maximum percentage difference for acceptance.
  final double maxPercentageDiff;

  /// Extra tolerance for short tracks (< 90s).
  final int shortTrackToleranceSec;

  /// Extra tolerance for live recordings.
  final int liveTrackToleranceSec;

  const DurationTolerancePolicy({
    this.maxAbsoluteDiffSec = 5,
    this.maxPercentageDiff = 0.10,
    this.shortTrackToleranceSec = 20,
    this.liveTrackToleranceSec = 30,
  });

  static const DurationTolerancePolicy standard = DurationTolerancePolicy();

  static const DurationTolerancePolicy strict = DurationTolerancePolicy(
    maxAbsoluteDiffSec: 3,
    maxPercentageDiff: 0.05,
    shortTrackToleranceSec: 10,
    liveTrackToleranceSec: 15,
  );

  static const DurationTolerancePolicy relaxed = DurationTolerancePolicy(
    maxAbsoluteDiffSec: 15,
    maxPercentageDiff: 0.20,
    shortTrackToleranceSec: 30,
    liveTrackToleranceSec: 60,
  );
}

/// Timeout configuration.
class TimeoutConfig {
  /// Timeout for ISRC resolution via Deezer/catalog.
  final Duration isrcResolution;

  /// Timeout for provider search queries.
  final Duration providerSearch;

  /// Timeout for stream URL resolution.
  final Duration streamResolution;

  /// Timeout for health probing.
  final Duration healthProbe;

  /// Timeout for source discovery (full resolution pipeline).
  final Duration sourceDiscovery;

  const TimeoutConfig({
    this.isrcResolution = const Duration(seconds: 5),
    this.providerSearch = const Duration(seconds: 8),
    this.streamResolution = const Duration(seconds: 10),
    this.healthProbe = const Duration(seconds: 6),
    this.sourceDiscovery = const Duration(seconds: 15),
  });

  static const TimeoutConfig standard = TimeoutConfig();
}

/// Policy-driven routing configuration.
///
/// Replaces scattered special cases like `playbackConfig()` in
/// MyAudioHandler and manual provider ordering hacks.
class RoutingPolicy {
  /// The user's request intent.
  final RequestIntent intent;

  /// Quality preference.
  final QualityPreference quality;

  /// Provider priority order (highest priority first).
  final List<ProviderId> providerOrder;

  /// Force a specific provider (null = use normal cascade).
  final ProviderId? forceProvider;

  /// Minimum acceptable verification level.
  final VerificationLevel minimumVerification;

  /// Duration tolerance for matching.
  final DurationTolerancePolicy durationTolerance;

  /// Maximum concurrent provider resolutions.
  final int maxConcurrency;

  /// Timeout configuration.
  final TimeoutConfig timeouts;

  /// Whether to prefer YouTube for non-official audio (covers, live, UGC).
  final bool pinNonOfficialToVideo;

  /// Maximum retry attempts per provider.
  final int maxRetriesPerProvider;

  /// Maximum total retry attempts across all providers.
  final int maxTotalRetries;

  const RoutingPolicy({
    this.intent = RequestIntent.automatic,
    this.quality = QualityPreference.lossless,
    this.providerOrder = const [],
    this.forceProvider,
    this.minimumVerification = VerificationLevel.likely,
    this.durationTolerance = const DurationTolerancePolicy(),
    this.maxConcurrency = 3,
    this.timeouts = const TimeoutConfig(),
    this.pinNonOfficialToVideo = true,
    this.maxRetriesPerProvider = 2,
    this.maxTotalRetries = 3,
  });

  /// Default playback policy.
  ///
  /// Catalog providers (with ISRC verification) go first, then YouTube
  /// as the exact-video fallback, then community/archive sources last.
  static RoutingPolicy forPlayback({
    List<ProviderId>? providerOrder,
    ProviderId? forceProvider,
    QualityPreference quality = QualityPreference.lossless,
  }) {
    final order = providerOrder ?? _playbackOrder;
    return RoutingPolicy(
      intent: RequestIntent.automatic,
      quality: quality,
      providerOrder: order,
      forceProvider: forceProvider,
      minimumVerification: VerificationLevel.likely,
      pinNonOfficialToVideo: true,
    );
  }

  /// Default download policy.
  static RoutingPolicy forDownload({
    List<ProviderId>? providerOrder,
    ProviderId? forceProvider,
    QualityPreference quality = QualityPreference.hiRes,
  }) =>
      RoutingPolicy(
        intent: RequestIntent.bestQuality,
        quality: quality,
        providerOrder: providerOrder ?? ProviderId.defaultOrder,
        forceProvider: forceProvider,
        minimumVerification: VerificationLevel.likely,
        pinNonOfficialToVideo: true,
        maxConcurrency: 3,
      );

  /// Default playback order: catalog sources first, YouTube as exact-video
  /// fallback, community/archive last.
  static const List<ProviderId> _playbackOrder = [
    ProviderId.qobuz,
    ProviderId.tidal,
    ProviderId.deezer,
    ProviderId.apple,
    ProviderId.amazon,
    ProviderId.youtubeMusic,
    ProviderId.soundcloud,
    ProviderId.instagram,
    ProviderId.internetArchive,
  ];

  /// Returns a copy with the given fields replaced.
  RoutingPolicy copyWith({
    RequestIntent? intent,
    QualityPreference? quality,
    List<ProviderId>? providerOrder,
    ProviderId? forceProvider,
    VerificationLevel? minimumVerification,
    DurationTolerancePolicy? durationTolerance,
    int? maxConcurrency,
    TimeoutConfig? timeouts,
    bool? pinNonOfficialToVideo,
    int? maxRetriesPerProvider,
    int? maxTotalRetries,
  }) =>
      RoutingPolicy(
        intent: intent ?? this.intent,
        quality: quality ?? this.quality,
        providerOrder: providerOrder ?? this.providerOrder,
        forceProvider: forceProvider ?? this.forceProvider,
        minimumVerification: minimumVerification ?? this.minimumVerification,
        durationTolerance: durationTolerance ?? this.durationTolerance,
        maxConcurrency: maxConcurrency ?? this.maxConcurrency,
        timeouts: timeouts ?? this.timeouts,
        pinNonOfficialToVideo:
            pinNonOfficialToVideo ?? this.pinNonOfficialToVideo,
        maxRetriesPerProvider:
            maxRetriesPerProvider ?? this.maxRetriesPerProvider,
        maxTotalRetries: maxTotalRetries ?? this.maxTotalRetries,
      );

  @override
  String toString() => 'RoutingPolicy(intent=$intent, quality=$quality, '
      'force=${forceProvider?.stableId}, '
      'providers=${providerOrder.map((p) => p.stableId).join(",")})';
}
