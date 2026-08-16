/// A candidate match found in a provider's catalog, ready for scoring
/// against a [SongQuery].
class TrackCandidate {
  final String trackId;

  final String title;

  final List<String> artists;

  final String? album;

  final String? isrc;

  final int? durationMs;

  final bool hires;

  final int? bitDepth;

  final double? samplingRateKhz;

  /// Short human-readable quality description for the match-correction UI,
  /// e.g. "Hi-Res FLAC", "FLAC" or "AAC".
  final String? qualityLabel;

  const TrackCandidate({
    required this.trackId,
    required this.title,
    this.artists = const [],
    this.album,
    this.isrc,
    this.durationMs,
    this.hires = false,
    this.bitDepth,
    this.samplingRateKhz,
    this.qualityLabel,
  });
}
