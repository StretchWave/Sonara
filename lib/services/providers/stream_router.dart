import 'dart:async';

import '../stream_service.dart' show Audio, Codec, StreamProvider;
import 'audio_source_provider.dart';
import 'models/provider_error.dart';
import 'models/provider_result.dart';
import 'provider_health.dart';
import 'provider_registry.dart';
import 'resolved_stream.dart';
import 'song_query.dart';
import 'stream_route_config.dart';

/// Routes stream requests through the configured providers in priority
/// order. The first provider that returns a playable stream wins; if every
/// provider fails, the last failure (with its status message) is returned.
class StreamRouter {
  StreamRouter({List<AudioSourceProvider>? providers})
      : providers = List.unmodifiable(
          providers ??
              ProviderRegistry.instance
                  .buildProviderChain(StreamRouteConfig.fromSettings()),
        );

  /// The ordered list of providers, highest priority first.
  final List<AudioSourceProvider> providers;

  static final StreamRouter instance = StreamRouter();

  /// Builds a router for [config]: the enabled/configured providers sorted
  /// by [StreamRouteConfig.providerOrder] (highest priority first).
  ///
  /// Uses [ProviderRegistry] to construct the provider chain cleanly.
  static StreamRouter build(
    StreamRouteConfig config, {
    String? forceProviderId,
  }) {
    final ordered = ProviderRegistry.instance.buildProviderChain(
      config,
      forceProviderId: forceProviderId,
    );
    return StreamRouter(providers: ordered);
  }

  /// Resolves a playable stream for [videoId], optionally using [song]
  /// metadata (title/artist/isrc/...) for cross-catalog matching.
  Future<StreamProvider> fetch(String videoId, {SongQuery? song}) async {
    final query = song ?? SongQuery(mediaId: videoId);
    StreamProvider? lastFailure;

    for (final provider in providers) {
      final pid = provider.typedProviderId;

      // Circuit breaker: skip degraded providers unless forced
      if (providers.length > 1 &&
          !RuntimeHealthTracker.instance.shouldAttempt(pid)) {
        continue;
      }

      final sw = Stopwatch()..start();
      try {
        final resolved = await provider.resolve(query);
        sw.stop();

        if (resolved.playable) {
          RuntimeHealthTracker.instance
              .recordSuccess(pid, sw.elapsedMilliseconds);
          return resolved.withProviderId(provider.id).toStreamProvider();
        }

        RuntimeHealthTracker.instance
            .recordMatchRejection(pid, sw.elapsedMilliseconds);
        lastFailure = resolved.withProviderId(provider.id).toStreamProvider();
      } catch (e) {
        sw.stop();
        RuntimeHealthTracker.instance.recordFailure(
          pid,
          e is TimeoutException
              ? ProviderErrorKind.timeout
              : ProviderErrorKind.networkError,
          sw.elapsedMilliseconds,
        );
      }
    }

    return lastFailure ??
        StreamProvider(playable: false, statusMSG: 'Unknown error occurred');
  }

  /// Resolves [query] and returns a structured [ProviderResult] for the best
  /// matching provider.
  Future<ProviderResult> resolveBest(SongQuery query) async {
    ProviderResult? lastFailure;

    for (final provider in providers) {
      final pid = provider.typedProviderId;
      if (providers.length > 1 &&
          !RuntimeHealthTracker.instance.shouldAttempt(pid)) {
        continue;
      }

      final result = await provider.resolveResult(query);
      if (result.isPlayable) {
        RuntimeHealthTracker.instance
            .recordSuccess(pid, result.latencyMs ?? 0);
        return result;
      }

      if (result.isError) {
        RuntimeHealthTracker.instance.recordFailure(
          pid,
          result.error?.kind ?? ProviderErrorKind.unknown,
          result.latencyMs,
        );
      } else {
        RuntimeHealthTracker.instance
            .recordMatchRejection(pid, result.latencyMs);
      }
      lastFailure = result;
    }

    return lastFailure ??
        ProviderResult.failure(
          providerId: '',
          error: const ProviderError(
            kind: ProviderErrorKind.noMatch,
            message: 'No provider could resolve the track',
          ),
        );
  }

  /// Resolves [videoId] against configured providers in bounded parallel
  /// batches (default concurrency: 3) and returns all playable results.
  ///
  /// Used by the download flow and source comparison sheet.
  Future<List<ProviderStreamResult>> fetchAll(
    String videoId, {
    SongQuery? song,
    int maxConcurrency = 3,
  }) async {
    final query = song ?? SongQuery(mediaId: videoId);
    final results = <ProviderStreamResult>[];

    // Bounded parallel execution: process providers in chunks of maxConcurrency
    for (var i = 0; i < providers.length; i += maxConcurrency) {
      final end = (i + maxConcurrency < providers.length)
          ? i + maxConcurrency
          : providers.length;
      final chunk = providers.sublist(i, end);

      final chunkResults = await Future.wait(
        chunk.map((provider) async {
          try {
            final resolved = await provider.resolve(query);
            if (resolved.playable) {
              return ProviderStreamResult(
                providerId: provider.id,
                stream: resolved.withProviderId(provider.id),
              );
            }
          } catch (_) {}
          return null;
        }),
      );

      for (final res in chunkResults) {
        if (res != null) results.add(res);
      }
    }

    return results;
  }

  /// Yields playable streams progressively as each provider completes its
  /// resolution attempt.
  Stream<ProviderStreamResult> fetchAllProgressive(
    String videoId, {
    SongQuery? song,
    int maxConcurrency = 3,
  }) async* {
    final query = song ?? SongQuery(mediaId: videoId);
    final controller = StreamController<ProviderStreamResult>();

    unawaited(() async {
      for (var i = 0; i < providers.length; i += maxConcurrency) {
        final end = (i + maxConcurrency < providers.length)
            ? i + maxConcurrency
            : providers.length;
        final chunk = providers.sublist(i, end);

        await Future.wait(
          chunk.map((provider) async {
            try {
              final resolved = await provider.resolve(query);
              if (resolved.playable && !controller.isClosed) {
                controller.add(ProviderStreamResult(
                  providerId: provider.id,
                  stream: resolved.withProviderId(provider.id),
                ));
              }
            } catch (_) {}
          }),
        );
      }
      if (!controller.isClosed) {
        await controller.close();
      }
    }());

    yield* controller.stream;
  }
}

/// One playable stream from one provider, as returned by
/// [StreamRouter.fetchAll].
class ProviderStreamResult {
  const ProviderStreamResult({
    required this.providerId,
    required this.stream,
  });

  /// Stable provider id, e.g. `qobuz`, `tidal`, `deezer`.
  final String providerId;

  /// The playable stream produced by that provider.
  final ResolvedStream stream;

  /// The single audio format of a lossless source (FLAC), or the best
  /// lossless/highest-quality format when the source has several.
  Audio? get flacAudio {
    for (final audio in stream.audioFormats) {
      if (audio.audioCodec == Codec.flac) return audio;
    }
    return stream.audioFormats.isEmpty ? null : stream.audioFormats.first;
  }
}
