/// Coordinates playback stream resolution with cancellation tokens,
/// ISRC pre-resolution, provider routing, validation, and caching.
library;

import 'dart:async';

import 'cache/stream_cache.dart';
import 'matching/isrc_resolver.dart';
import 'models/match_decision.dart';
import 'models/provider_id.dart';
import 'models/recording_identity.dart';
import 'retry_policy.dart';
import 'stream_route_config.dart';
import 'stream_router.dart';
import 'stream_validator.dart';

/// Information about the resolved source for playback UI indicators.
class PlaybackSourceInfo {
  final ProviderId providerId;
  final String providerDisplayName;
  final String qualityLabel;
  final MatchDecision matchDecision;
  final bool fromCache;
  final int? latencyMs;

  const PlaybackSourceInfo({
    required this.providerId,
    required this.providerDisplayName,
    required this.qualityLabel,
    required this.matchDecision,
    this.fromCache = false,
    this.latencyMs,
  });

  /// Short summary for player UI (e.g. "Qobuz · Hi-Res FLAC").
  String get indicatorLabel => '$providerDisplayName · $qualityLabel';

  /// Explanation for "Why this source?" dialog.
  String get explanation => matchDecision.explanation;
}

/// Result of a playback resolution request.
class PlaybackResolutionResult {
  final bool success;
  final Map<String, dynamic>? streamData;
  final PlaybackSourceInfo? sourceInfo;
  final String? errorMessage;
  final bool wasCancelled;

  const PlaybackResolutionResult({
    required this.success,
    this.streamData,
    this.sourceInfo,
    this.errorMessage,
    this.wasCancelled = false,
  });

  factory PlaybackResolutionResult.cancelled() => const PlaybackResolutionResult(
        success: false,
        wasCancelled: true,
        errorMessage: 'Resolution was superseded by a newer request',
      );

  factory PlaybackResolutionResult.failure(String message) =>
      PlaybackResolutionResult(
        success: false,
        errorMessage: message,
      );

  factory PlaybackResolutionResult.success({
    required Map<String, dynamic> streamData,
    required PlaybackSourceInfo sourceInfo,
  }) =>
      PlaybackResolutionResult(
        success: true,
        streamData: streamData,
        sourceInfo: sourceInfo,
      );
}

/// Orchestrates music stream resolution for playback, ensuring stale requests
/// are cancelled immediately and correct recordings are played.
class PlaybackCoordinator {
  PlaybackCoordinator({
    IsrcResolver? isrcResolver,
    StreamCache? streamCache,
  })  : _isrcResolver = isrcResolver ?? IsrcResolver(),
        _cache = streamCache ?? StreamCache();

  final IsrcResolver _isrcResolver;
  final StreamCache _cache;

  int _activeRequestId = 0;

  /// Starts a new resolution request and invalidates any previous in-flight ones.
  int newRequest() {
    return ++_activeRequestId;
  }

  /// Whether [requestId] is still the active, newest request.
  bool isActive(int requestId) => requestId == _activeRequestId;

  /// Resolves the best playable stream for [identity], checking cache, resolving
  /// ISRC, and cascading through providers with cancellation safety.
  Future<PlaybackResolutionResult> resolve({
    required int requestId,
    required RecordingIdentity identity,
    String? forceProviderId,
    int? qualityIndex,
    bool forceNew = false,
  }) async {
    final mediaId = identity.mediaId;

    // 1. Stale check
    if (!isActive(requestId)) return PlaybackResolutionResult.cancelled();

    // 2. Cache check (provider-aware)
    if (!forceNew) {
      final cachedJson = _cache.get(
        mediaId: mediaId,
        providerId: forceProviderId,
        qualityIndex: qualityIndex,
      );

      if (cachedJson != null && cachedJson['playable'] == true) {
        final cachedProviderId = cachedJson['providerId']?.toString() ??
            forceProviderId ??
            'youtube_music';
        final pId = ProviderId.fromStableId(cachedProviderId) ??
            ProviderId.youtubeMusic;

        return PlaybackResolutionResult.success(
          streamData: cachedJson,
          sourceInfo: PlaybackSourceInfo(
            providerId: pId,
            providerDisplayName: pId.displayName,
            qualityLabel: cachedJson['qualityLabel']?.toString() ?? 'Standard',
            matchDecision: const MatchDecision(
              accepted: true,
              verificationLevel: VerificationLevel.likely,
            ),
            fromCache: true,
          ),
        );
      }
    }

    if (!isActive(requestId)) return PlaybackResolutionResult.cancelled();

    // 3. ISRC Resolution: Check if identity already has ISRC or resolve via Deezer
    String? isrc = identity.isrc;
    if (isrc == null || isrc.isEmpty) {
      if (forceProviderId == null || forceProviderId != 'youtube_music') {
        isrc = await _isrcResolver.resolve(
          song: identity.title,
          artist: identity.primaryArtist,
          durationMs: identity.durationMs,
        );
      }
    }

    if (!isActive(requestId)) return PlaybackResolutionResult.cancelled();

    // 4. Build routing policy and provider chain
    final baseConfig = StreamRouteConfig.fromSettings();
    final router = StreamRouter.build(
      baseConfig,
      forceProviderId: forceProviderId,
    );

    var query = identity.toSongQuery();
    if (isrc != null && isrc.isNotEmpty) {
      query = query.copyWith(isrc: isrc);
    }

    final retryPolicy = RetryPolicy.standard;
    retryPolicy.reset();

    // 5. Attempt providers in configured priority order
    for (final provider in router.providers) {
      if (!isActive(requestId)) return PlaybackResolutionResult.cancelled();

      final pid = provider.typedProviderId;
      final sw = Stopwatch()..start();

      try {
        final result = await provider.resolveResult(query);
        sw.stop();

        if (!isActive(requestId)) return PlaybackResolutionResult.cancelled();

        if (result.isPlayable && result.stream != null) {
          // Validate stream format, duration, preview status
          final validation = StreamValidator.validate(
            result.stream!,
            expectedDurationMs: identity.durationMs,
            expectedProviderId: provider.id,
          );

          if (validation.isValid) {
            final streamJson = result.stream!.toStreamProvider().toJson();
            streamJson['providerId'] = provider.id;

            // Cache with provider isolation
            _cache.put(
              mediaId: mediaId,
              data: streamJson,
              providerId: provider.id,
              qualityIndex: qualityIndex,
            );

            return PlaybackResolutionResult.success(
              streamData: streamJson,
              sourceInfo: PlaybackSourceInfo(
                providerId: pid,
                providerDisplayName: pid.displayName,
                qualityLabel: result.stream!.audioFormats.isNotEmpty
                    ? (result.stream!.audioFormats.first.audioCodec.name.toUpperCase())
                    : 'Standard',
                matchDecision: result.matchDecision,
                latencyMs: sw.elapsedMilliseconds,
              ),
            );
          }
        }
      } catch (_) {
        // Continue to fallback
      }
    }

    return PlaybackResolutionResult.failure('Unable to resolve audio stream for track');
  }
}
