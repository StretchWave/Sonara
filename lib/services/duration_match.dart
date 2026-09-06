/// Playback sanity check for cross-catalog sources.
///
/// When a non-YouTube source (Qobuz/Tidal/Deezer/...) plays a copy whose
/// real length is far shorter than the song's known length, it is almost
/// always a preview or the wrong recording. The player then falls back to
/// the YouTube source, whose length is the reference.
library;

/// The minimum expected length (ms) below which a song is not validated.
const int kMinExpectedDurationForCheckMs = 60000;

/// A source is considered "too short" — and therefore wrong — when it is
/// under 60% of the expected length with a gap of at least 20 seconds.
const double kMaxExpectedFraction = 0.6;
const int kMinGapMs = 20000;

/// Whether [actualMs] is so much shorter than [expectedMs] that the source
/// is probably not the real song.
///
/// Returns false when there is no expected length, the song is too short to
/// bother validating, or the source is YouTube (the reference itself).
bool isDurationMismatch(int? expectedMs, int actualMs, String source) {
  if (expectedMs == null || expectedMs < kMinExpectedDurationForCheckMs) {
    return false;
  }
  if (source.isEmpty || source == 'youtube_music') return false;
  return actualMs < expectedMs * kMaxExpectedFraction &&
      (expectedMs - actualMs) > kMinGapMs;
}
