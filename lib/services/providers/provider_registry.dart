/// Central registry for audio source providers and their capabilities.
library;

import 'amazon/amazon_provider.dart';
import 'apple/apple_provider.dart';
import 'audio_source_provider.dart';
import 'deezer/deezer_provider.dart';
import 'instagram/instagram_provider.dart';
import 'internet_archive_provider.dart';
import 'models/provider_capabilities.dart';
import 'models/provider_id.dart';
import 'qobuz/qobuz_provider.dart';
import 'soundcloud/soundcloud_audio_provider.dart';
import 'stream_route_config.dart';
import 'tidal/tidal_provider.dart';
import 'youtube_audio_provider.dart';

/// Factory signature for creating an [AudioSourceProvider] from configuration.
typedef ProviderFactory = AudioSourceProvider? Function(StreamRouteConfig config);

/// Descriptor for a registered provider.
class ProviderDescriptor {
  final ProviderId id;
  final ProviderCapabilities capabilities;
  final ProviderFactory factory;

  const ProviderDescriptor({
    required this.id,
    required this.capabilities,
    required this.factory,
  });
}

/// Central registry managing all available audio source providers.
class ProviderRegistry {
  ProviderRegistry._() {
    _registerDefaults();
  }

  static final ProviderRegistry instance = ProviderRegistry._();

  final Map<ProviderId, ProviderDescriptor> _descriptors = {};

  /// Registers a provider descriptor.
  void register(ProviderDescriptor descriptor) {
    _descriptors[descriptor.id] = descriptor;
  }

  /// Retrieves the descriptor for [id], or null if not registered.
  ProviderDescriptor? getDescriptor(ProviderId id) => _descriptors[id];

  /// Capabilities of [id], or a minimal default if unregistered.
  ProviderCapabilities getCapabilities(ProviderId id) {
    return _descriptors[id]?.capabilities ?? const ProviderCapabilities();
  }

  /// All registered provider descriptors.
  List<ProviderDescriptor> get allDescriptors => _descriptors.values.toList();

  /// Builds all enabled providers in the order specified by [config.providerOrder].
  ///
  /// If [forceProviderId] is given, only that provider is returned (if enabled and configured).
  List<AudioSourceProvider> buildProviderChain(
    StreamRouteConfig config, {
    String? forceProviderId,
  }) {
    final available = <ProviderId, AudioSourceProvider>{};

    for (final descriptor in _descriptors.values) {
      final provider = descriptor.factory(config);
      if (provider != null) {
        available[descriptor.id] = provider;
      }
    }

    if (forceProviderId != null) {
      final forcedId = ProviderId.fromStableId(forceProviderId);
      final forced = forcedId != null ? available[forcedId] : null;
      if (forced != null) {
        return [forced];
      }
      return const [];
    }

    final ordered = <AudioSourceProvider>[];
    final order = config.providerOrder;

    for (final rawId in order) {
      final providerId = ProviderId.fromStableId(rawId);
      if (providerId != null) {
        final provider = available.remove(providerId);
        if (provider != null) {
          ordered.add(provider);
        }
      }
    }

    // Append any remaining available providers not in configured order
    ordered.addAll(available.values);
    return ordered;
  }

  void _registerDefaults() {
    register(ProviderDescriptor(
      id: ProviderId.qobuz,
      capabilities: ProviderCapabilities.losslessCatalog,
      factory: (config) {
        if (!config.qobuzEnabled || config.qobuzInstances.isEmpty) return null;
        return QobuzProvider(
          instances: config.qobuzInstances,
          country: config.qobuzCountry,
          qualityCode: config.qobuzQuality,
          matchOverrides: config.matchOverrides,
        );
      },
    ));

    register(ProviderDescriptor(
      id: ProviderId.tidal,
      capabilities: ProviderCapabilities.losslessCatalog,
      factory: (config) {
        if (!config.tidalEnabled || config.tidalEndpoints.isEmpty) return null;
        return TidalProvider(
          endpoints: config.tidalEndpoints,
          quality: config.tidalQuality,
          matchOverrides: config.matchOverrides,
        );
      },
    ));

    register(ProviderDescriptor(
      id: ProviderId.deezer,
      capabilities: ProviderCapabilities.losslessCatalog,
      factory: (config) {
        if (!config.deezerEnabled) return null;
        return DeezerProvider(
          endpoints: config.deezerEndpoints,
          quality: config.deezerQuality,
          matchOverrides: config.matchOverrides,
        );
      },
    ));

    register(ProviderDescriptor(
      id: ProviderId.apple,
      capabilities: ProviderCapabilities.losslessCatalog,
      factory: (config) {
        if (!config.appleEnabled) return null;
        return AppleProvider(
          endpoints: config.appleEndpoints,
          matchOverrides: config.matchOverrides,
        );
      },
    ));

    register(ProviderDescriptor(
      id: ProviderId.amazon,
      capabilities: ProviderCapabilities.losslessCatalog,
      factory: (config) {
        if (!config.amazonEnabled) return null;
        return AmazonProvider(
          endpoints: config.amazonEndpoints,
          quality: config.amazonQuality,
          matchOverrides: config.matchOverrides,
        );
      },
    ));

    register(ProviderDescriptor(
      id: ProviderId.youtubeMusic,
      capabilities: ProviderCapabilities.youtubeMusic,
      factory: (config) {
        return YouTubeAudioProvider(visitorId: config.visitorId);
      },
    ));

    register(ProviderDescriptor(
      id: ProviderId.soundcloud,
      capabilities: ProviderCapabilities.soundcloud,
      factory: (config) {
        if (!config.soundcloudEnabled) return null;
        return const SoundCloudAudioProvider();
      },
    ));

    register(ProviderDescriptor(
      id: ProviderId.internetArchive,
      capabilities: ProviderCapabilities.internetArchive,
      factory: (config) {
        if (!config.internetArchiveEnabled) return null;
        return const InternetArchiveProvider();
      },
    ));

    register(ProviderDescriptor(
      id: ProviderId.instagram,
      capabilities: ProviderCapabilities.instagram,
      factory: (config) {
        if (!config.instagramEnabled || config.instagramCookie.isEmpty) {
          return null;
        }
        return InstagramProvider(
          sessionCookie: config.instagramCookie,
          matchOverrides: config.matchOverrides,
        );
      },
    ));
  }
}
