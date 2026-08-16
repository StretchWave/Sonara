import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';

import 'spotify_source_track.dart';
import 'track_normalizer.dart';

/// Confidence bands for a normalized match score (0.0 - 1.0).
enum MatchConfidence {
  high,
  medium,
  low,
  unmatched;

  static MatchConfidence fromScore(double score) {
    if (score >= MatchThresholds.high) return high;
    if (score >= MatchThresholds.medium) return medium;
    if (score >= MatchThresholds.low) return low;
    return unmatched;
  }
}

/// Configurable scoring thresholds.
abstract final class MatchThresholds {
  static const double high = 0.90;
  static const double medium = 0.75;
  static const double low = 0.60;
}

/// Configurable matching weights. ISRC identifies a specific recording, so
/// it dominates; the remaining signals refine the decision.
abstract final class MatchWeights {
  static const double isrc = 0.50;
  static const double title = 0.20;
  static const double artist = 0.15;
  static const double duration = 0.10;
  static const double album = 0.05;

  /// Applied to the title similarity when exactly one side carries a version
  /// marker (Live / Acoustic / Remix / Radio Edit / ...).
  static const double versionMismatchFactor = 0.75;

  /// Extra penalty for cover/tribute versions: a cover is a fundamentally
  /// different recording even when the title matches.
  static const double coverMismatchFactor = 0.5;

  /// Subtracted from the final score when both sides advertise their
  /// explicit/clean state and they disagree.
  static const double explicitMismatchPenalty = 0.05;
}

/// A scored candidate found on a provider.
class TrackCandidate {
  final MusicProvider provider;
  final MediaItem track;
  final double score;
  final MatchConfidence confidence;

  const TrackCandidate({
    required this.provider,
    required this.track,
    required this.score,
    required this.confidence,
  });
}

/// Providers the app can resolve music from, in quality/preference order.
/// Only providers with a concrete resolver are listed; adding a provider
/// means adding an entry here plus a resolver in provider_track_resolver.dart.
enum MusicProvider {
  youtubeMusic('YouTube Music');

  final String displayName;
  const MusicProvider(this.displayName);
}

/// Ordered provider preference. A provider earlier in the list is preferred
/// when two candidates have equal scores.
const List<MusicProvider> providerPriority = [
  MusicProvider.youtubeMusic,
];

/// Candidate ISRC, when the provider exposes it (YouTube Music does not).
String? candidateIsrc(MediaItem candidate) {
  final isrc = candidate.extras?['isrc'];
  return isrc is String && isrc.isNotEmpty ? isrc : null;
}

/// Scores a provider candidate against the Spotify source track.
///
/// Signals that are unavailable on either side (e.g. ISRC, duration, album)
/// are excluded from the weighted average so a missing signal never unfairly
/// drags the score down. The result is normalized to [0, 1].
double scoreTrack(SpotifySourceTrack source, MediaItem candidate) {
  final signals = <(double, double)>[];

  // ISRC — the strongest signal. Only comparable when both sides expose it.
  final sourceIsrc = source.isrc;
  final candIsrc = candidateIsrc(candidate);
  if (sourceIsrc != null && candIsrc != null) {
    signals.add((
      MatchWeights.isrc,
      sourceIsrc.toUpperCase() == candIsrc.toUpperCase() ? 1.0 : 0.0,
    ));
  }

  // Title — version markers may cap the similarity.
  var titleSim = textSimilarity(
      normalizeTitleForComparison(source.title),
      normalizeTitleForComparison(candidate.title));
  final markersDiffer = hasVersionMarker(source.title) !=
      hasVersionMarker(candidate.title);
  if (markersDiffer) {
    titleSim *= MatchWeights.versionMismatchFactor;
  }
  // Covers/tributes are fundamentally different recordings.
  final coverMismatch =
      versionMarkersOf(source.title).any(_isCoverMarker) !=
      versionMarkersOf(candidate.title).any(_isCoverMarker);
  if (coverMismatch) {
    titleSim *= MatchWeights.coverMismatchFactor;
  }
  signals.add((MatchWeights.title, titleSim));

  // Artist — compare the full source artist list against the candidate's
  // joined artist string and structured artist list when available.
  final candArtists = <String>[
    if (candidate.artist != null && candidate.artist!.isNotEmpty)
      candidate.artist!,
    ...?((candidate.extras?['artists'] as List?)?.map((e) =>
        e is Map ? (e['name']?.toString() ?? '') : e.toString())),
  ];
  final artistSim = _artistSimilarity(source.artists, candArtists);
  if (artistSim != null) {
    signals.add((MatchWeights.artist, artistSim));
  }

  // Duration — unknown durations are excluded.
  final candDurationMs = candidate.duration?.inMilliseconds;
  if (candDurationMs != null && source.durationMs > 0) {
    signals.add((MatchWeights.duration, _durationSimilarity(
      source.durationMs,
      candDurationMs,
    )));
  }

  // Album — only when both sides have one.
  final candAlbum = candidate.extras?['album'];
  final candAlbumName = candAlbum is Map ? candAlbum['name']?.toString() : null;
  final sourceAlbum = source.album;
  if (sourceAlbum != null && candAlbumName != null) {
    signals.add((
      MatchWeights.album,
      textSimilarity(
          normalizeNameForComparison(sourceAlbum),
          normalizeNameForComparison(candAlbumName)),
    ));
  }

  if (signals.isEmpty) return 0.0;

  final totalWeight =
      signals.fold<double>(0, (sum, s) => sum + s.$1);
  final weighted =
      signals.fold<double>(0, (sum, s) => sum + s.$1 * s.$2);
  var score = weighted / totalWeight;

  // Explicit/clean mismatch penalty when both states are known.
  final candExplicit = candidate.extras?['explicit'];
  if (candExplicit is bool &&
      candExplicit != source.explicit &&
      (source.explicit || candExplicit)) {
    score -= MatchWeights.explicitMismatchPenalty;
  }

  return score.clamp(0.0, 1.0);
}

bool _isCoverMarker(String marker) =>
    marker == 'cover' || marker == 'tribute';

/// Jaccard similarity over the token sets of both artist lists, or null when
/// either side is empty (excluded from scoring).
///
/// Artist strings are split on feat/&/with separators first so "Artist A
/// feat. Artist B" and "Artist A & Artist B" compare equal, while a
/// different artist ("Cover Band A") scores poorly.
double? _artistSimilarity(
    List<String> sourceArtists, List<String> candidateArtists) {
  final sa = sourceArtists
      .expand((a) => splitArtistList(a))
      .expand((a) => tokenSet(normalizeNameForComparison(a)))
      .toSet();
  final ca = candidateArtists
      .expand((a) => splitArtistList(a))
      .expand((a) => tokenSet(normalizeNameForComparison(a)))
      .toSet();
  if (sa.isEmpty || ca.isEmpty) return null;
  final inter = sa.intersection(ca).length;
  if (inter == 0) return 0.0;
  return inter / sa.union(ca).length;
}

/// Duration similarity bands: very strong within 2s, strong within 5s,
/// moderate within 10s, then a linear decay, with a severe penalty beyond
/// 30s (a different edit/version).
double _durationSimilarity(int sourceMs, int candidateMs) {
  final diff = (sourceMs - candidateMs).abs().toDouble();
  if (diff <= 2000) return 1.0;
  if (diff <= 5000) return 0.95;
  if (diff <= 10000) return 0.85;
  if (diff > 30000) return 0.10;
  return math.max(0.0, 0.85 - (diff - 10000) / 20000 * 0.75);
}

/// Ordered search strategies for a source track. Strategy 1 is tried first;
/// the resolver stops as soon as a strategy yields a high-confidence match.
List<String> generateSearchQueries(SpotifySourceTrack source) {
  final title = stripFeaturing(source.title);
  final artist = source.artists.isNotEmpty ? source.artists.first : '';
  final queries = <String>[];

  if (title.isNotEmpty && artist.isNotEmpty) {
    queries.add('"$title" "$artist"');
    if (source.album != null) {
      queries.add('"$title" "$artist" "${source.album}"');
    }
    queries.add('"$artist" "$title"');
  } else if (title.isNotEmpty) {
    queries.add('"$title"');
  }
  return queries;
}
