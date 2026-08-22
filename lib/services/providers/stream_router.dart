import '../stream_service.dart' show StreamProvider;
import 'audio_source_provider.dart';
import 'amazon/amazon_provider.dart';
import 'apple/apple_provider.dart';
import 'deezer/deezer_provider.dart';
import 'instagram/instagram_provider.dart';
import 'internet_archive_provider.dart';
import 'qobuz/qobuz_provider.dart';
import 'soundcloud/soundcloud_audio_provider.dart';
import 'song_query.dart';
import 'stream_route_config.dart';
import 'tidal/tidal_provider.dart';
import 'youtube_audio_provider.dart';

/// Routes stream requests through the configured providers in priority
/// order. The first provider that returns a playable stream wins; if every
/// provider fails, the last failure (with its status message) is returned.
class StreamRouter {
  StreamRouter({List<AudioSourceProvider>? providers})
      : providers = List.unmodifiable(providers ??
            const [YouTubeAudioProvider(), SoundCloudAudioProvider()]);

  /// The ordered list of providers, highest priority first.
  final List<AudioSourceProvider> providers;

  static final StreamRouter instance = StreamRouter();

  /// Builds a router for [config]: the enabled/configured providers sorted
  /// by [StreamRouteConfig.providerOrder] (highest priority first).
  static StreamRouter build(StreamRouteConfig config) {
    final available = <String, AudioSourceProvider>{
      if (config.qobuzEnabled && config.qobuzInstances.isNotEmpty)
        'qobuz': QobuzProvider(
          instances: config.qobuzInstances,
          country: config.qobuzCountry,
          qualityCode: config.qobuzQuality,
          matchOverrides: config.matchOverrides,
        ),
      if (config.tidalEnabled && config.tidalEndpoints.isNotEmpty)
        'tidal': TidalProvider(
          endpoints: config.tidalEndpoints,
          quality: config.tidalQuality,
          matchOverrides: config.matchOverrides,
        ),
      if (config.deezerEnabled)
        'deezer': DeezerProvider(
          endpoints: config.deezerEndpoints,
          quality: config.deezerQuality,
          matchOverrides: config.matchOverrides,
        ),
      if (config.appleEnabled)
        'apple': AppleProvider(
          endpoints: config.appleEndpoints,
          matchOverrides: config.matchOverrides,
        ),
      if (config.amazonEnabled)
        'amazon': AmazonProvider(
          endpoints: config.amazonEndpoints,
          quality: config.amazonQuality,
          matchOverrides: config.matchOverrides,
        ),
      'youtube_music': YouTubeAudioProvider(visitorId: config.visitorId),
      if (config.soundcloudEnabled)
        'soundcloud': const SoundCloudAudioProvider(),
      if (config.internetArchiveEnabled)
        'internet_archive': const InternetArchiveProvider(),
      if (config.instagramEnabled && config.instagramCookie.isNotEmpty)
        'instagram': InstagramProvider(
          sessionCookie: config.instagramCookie,
          matchOverrides: config.matchOverrides,
        ),
    };

    // Sort enabled providers by the configured priority order.  Providers
    // that are not listed in [providerOrder] keep their insertion order at
    // the end.
    final ordered = <AudioSourceProvider>[];
    for (final id in config.providerOrder) {
      final provider = available.remove(id);
      if (provider != null) ordered.add(provider);
    }
    ordered.addAll(available.values);
    return StreamRouter(providers: ordered);
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
