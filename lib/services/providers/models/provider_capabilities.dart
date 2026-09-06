/// Provider capabilities declaration — providers declare what they support
/// so routing decisions can be made by the router, not scattered in
/// provider-specific conditionals.
library;

import '../../stream_service.dart' show Codec;
import 'provider_id.dart';

/// Immutable declaration of what a provider can do.
class ProviderCapabilities {
  /// Whether this provider can serve lossless (FLAC/ALAC) streams.
  final bool supportsLossless;

  /// Whether this provider can serve Hi-Res (>16bit/44.1kHz) streams.
  final bool supportsHiRes;

  /// Codecs this provider can produce.
  final Set<Codec> supportedCodecs;

  /// Whether this provider supports searching by ISRC.
  final bool supportsIsrcSearch;

  /// Whether this provider can verify an exact ISRC match (not just search).
  final bool supportsExactIsrcVerification;

  /// Whether this provider reports track duration.
  final bool supportsDuration;

  /// Whether this provider returns full metadata (title, artist, album).
  final bool supportsMetadata;

  /// Whether this provider can supply album artwork.
  final bool supportsArtwork;

  /// Whether streams from this provider can be downloaded.
  final bool supportsDownloads;

  /// Whether this provider supports regional availability filtering.
  final bool supportsRegionalAvailability;

  /// Whether this provider requires authentication.
  final bool supportsAuthentication;

  /// Whether this provider can confirm it has the exact same recording
  /// (by ISRC or provider track ID).
  final bool supportsExactRecordingVerification;

  /// Whether this provider uses its own track IDs for matching.
  final bool supportsProviderTrackId;

  /// Whether this provider can detect preview/partial streams.
  final bool supportsPreviewDetection;

  const ProviderCapabilities({
    this.supportsLossless = false,
    this.supportsHiRes = false,
    this.supportedCodecs = const {Codec.opus, Codec.mp4a},
    this.supportsIsrcSearch = false,
    this.supportsExactIsrcVerification = false,
    this.supportsDuration = true,
    this.supportsMetadata = true,
    this.supportsArtwork = true,
    this.supportsDownloads = true,
    this.supportsRegionalAvailability = false,
    this.supportsAuthentication = false,
    this.supportsExactRecordingVerification = false,
    this.supportsProviderTrackId = false,
    this.supportsPreviewDetection = false,
  });

  /// Standard capabilities for lossless catalog providers (Qobuz, Tidal, …).
  static const ProviderCapabilities losslessCatalog = ProviderCapabilities(
    supportsLossless: true,
    supportsHiRes: true,
    supportedCodecs: {Codec.flac, Codec.mp4a, Codec.mp3},
    supportsIsrcSearch: true,
    supportsExactIsrcVerification: true,
    supportsDuration: true,
    supportsMetadata: true,
    supportsArtwork: true,
    supportsDownloads: true,
    supportsRegionalAvailability: true,
    supportsExactRecordingVerification: true,
    supportsProviderTrackId: true,
    supportsPreviewDetection: true,
  );

  /// Standard capabilities for YouTube Music.
  static const ProviderCapabilities youtubeMusic = ProviderCapabilities(
    supportsLossless: false,
    supportsHiRes: false,
    supportedCodecs: {Codec.opus, Codec.mp4a},
    supportsIsrcSearch: false,
    supportsExactIsrcVerification: false,
    supportsDuration: true,
    supportsMetadata: true,
    supportsArtwork: true,
    supportsDownloads: true,
    supportsRegionalAvailability: false,
    supportsExactRecordingVerification: true,  // exact video ID
    supportsProviderTrackId: true,
    supportsPreviewDetection: false,
  );

  /// Standard capabilities for SoundCloud.
  static const ProviderCapabilities soundcloud = ProviderCapabilities(
    supportsLossless: false,
    supportsHiRes: false,
    supportedCodecs: {Codec.opus, Codec.mp3},
    supportsIsrcSearch: false,
    supportsExactIsrcVerification: false,
    supportsDuration: true,
    supportsMetadata: true,
    supportsArtwork: true,
    supportsDownloads: true,
    supportsRegionalAvailability: false,
    supportsExactRecordingVerification: false,
    supportsProviderTrackId: true,
    supportsPreviewDetection: false,
  );

  /// Standard capabilities for Internet Archive.
  static const ProviderCapabilities internetArchive = ProviderCapabilities(
    supportsLossless: true,
    supportsHiRes: false,
    supportedCodecs: {Codec.flac, Codec.mp3},
    supportsIsrcSearch: false,
    supportsExactIsrcVerification: false,
    supportsDuration: true,
    supportsMetadata: true,
    supportsArtwork: false,
    supportsDownloads: true,
    supportsRegionalAvailability: false,
    supportsExactRecordingVerification: false,
    supportsProviderTrackId: true,
    supportsPreviewDetection: false,
  );

  /// Standard capabilities for Instagram.
  static const ProviderCapabilities instagram = ProviderCapabilities(
    supportsLossless: false,
    supportsHiRes: false,
    supportedCodecs: {Codec.mp4a},
    supportsIsrcSearch: false,
    supportsExactIsrcVerification: false,
    supportsDuration: false,
    supportsMetadata: false,
    supportsArtwork: false,
    supportsDownloads: true,
    supportsRegionalAvailability: false,
    supportsAuthentication: true,
    supportsExactRecordingVerification: false,
    supportsProviderTrackId: false,
    supportsPreviewDetection: false,
  );

  /// Resolves the declared capabilities for a given [ProviderId].
  static ProviderCapabilities forProvider(ProviderId id) => switch (id) {
        ProviderId.qobuz ||
        ProviderId.tidal ||
        ProviderId.deezer ||
        ProviderId.apple ||
        ProviderId.amazon =>
          losslessCatalog,
        ProviderId.youtubeMusic => youtubeMusic,
        ProviderId.soundcloud => soundcloud,
        ProviderId.internetArchive => internetArchive,
        ProviderId.instagram => instagram,
      };

  @override
  String toString() => 'ProviderCapabilities('
      'lossless=$supportsLossless, hiRes=$supportsHiRes, '
      'isrc=$supportsIsrcSearch, codecs=$supportedCodecs)';
}
