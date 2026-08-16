import '../stream_service.dart' show StreamProvider;
import 'audio_source_provider.dart';
import 'qobuz/qobuz_provider.dart';
import 'song_query.dart';
import 'stream_route_config.dart';
import 'tidal/tidal_provider.dart';
import 'youtube_audio_provider.dart';

/// Routes stream requests through the configured providers in priority
/// order. The first provider that returns a playable stream wins; if every
/// provider fails, the last failure (with its status message) is returned.
///
/// The default router contains only [YouTubeAudioProvider], preserving the
/// app's current behavior. Additional providers are appended as they are
/// configured (see Settings → Sources).
class StreamRouter {
  StreamRouter({List<AudioSourceProvider>? providers})
      : providers =
            List.unmodifiable(providers ?? const [YouTubeAudioProvider()]);

  /// The ordered list of providers, highest priority first.
  final List<AudioSourceProvider> providers;

  static final StreamRouter instance = StreamRouter();

  /// Builds a router for [config]: configured providers in priority order
  /// followed by the YouTube fallback.
  static StreamRouter build(StreamRouteConfig config) {
    final providers = <AudioSourceProvider>[
      if (config.qobuzEnabled && config.qobuzInstances.isNotEmpty)
        QobuzProvider(
          instances: config.qobuzInstances,
          country: config.qobuzCountry,
          qualityCode: config.qobuzQuality,
          matchOverrides: config.matchOverrides,
        ),
      if (config.tidalEnabled && config.tidalEndpoints.isNotEmpty)
        TidalProvider(
          endpoints: config.tidalEndpoints,
          quality: config.tidalQuality,
          matchOverrides: config.matchOverrides,
        ),
      const YouTubeAudioProvider(),
    ];
    return StreamRouter(providers: providers);
  }

  /// Resolves a playable stream for [videoId], optionally using [song]
  /// metadata (title/artist/isrc/...) for cross-catalog matching.
  Future<StreamProvider> fetch(String videoId, {SongQuery? song}) async {
    final query = song ?? SongQuery(mediaId: videoId);
    StreamProvider? lastFailure;
    for (final provider in providers) {
      try {
        final resolved = await provider.resolve(query);
        if (resolved.playable) {
          return resolved.toStreamProvider();
        }
        lastFailure = resolved.toStreamProvider();
      } catch (_) {
        // Provider crashed — fall through to the next one.
      }
    }
    return lastFailure ??
        StreamProvider(playable: false, statusMSG: 'Unknown error occurred');
  }
}
