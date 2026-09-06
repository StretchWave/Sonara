import '../stream_service.dart' show Audio, StreamProvider;

/// A playable stream produced by a provider, with optional quality
/// metadata used for display ("Qobuz Hi-Res FLAC 24bit/192kHz").
class ResolvedStream {
  final bool playable;

  /// Human-readable status message when [playable] is false.
  final String statusMSG;

  /// Audio formats of this stream (a single entry for lossless sources,
  /// the full manifest list for YouTube).
  final List<Audio> audioFormats;

  /// Human-readable format label, e.g. "Qobuz Hi-Res FLAC 24bit/192kHz".
  final String? label;

  final String? mimeType;

  final int? sampleRate;

  final int? bitDepth;

  final DateTime? expiresAt;

  /// Stable id of the provider that produced this stream
  /// (`qobuz`, `tidal`, `youtube_music`, ...). Filled in by the router.
  final String providerId;

  const ResolvedStream({
    required this.playable,
    this.statusMSG = '',
    this.audioFormats = const [],
    this.label,
    this.mimeType,
    this.sampleRate,
    this.bitDepth,
    this.expiresAt,
    this.providerId = '',
  });

  factory ResolvedStream.fromStreamProvider(StreamProvider provider) =>
      ResolvedStream(
        playable: provider.playable,
        statusMSG: provider.statusMSG,
        audioFormats: provider.audioFormats ?? const [],
        providerId: provider.providerId,
      );

  /// Copies this stream, stamping [id] as the producing provider.
  ResolvedStream withProviderId(String id) => ResolvedStream(
        playable: playable,
        statusMSG: statusMSG,
        audioFormats: audioFormats,
        label: label,
        mimeType: mimeType,
        sampleRate: sampleRate,
        bitDepth: bitDepth,
        expiresAt: expiresAt,
        providerId: id,
      );

  /// Converts back to the legacy transport model used by the rest of the
  /// app (playback, downloads, Hive caches).
  StreamProvider toStreamProvider() => StreamProvider(
        playable: playable,
        statusMSG: statusMSG,
        audioFormats: audioFormats,
        providerId: providerId,
      );
}
