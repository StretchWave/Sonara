/// Scoring engine for choosing the best cross-catalog match, ported from
/// MetroFuse's Qobuz/Tidal matching logic (GPL-3.0, see repo attribution).
///
/// Scores are weighted so ISRC equality dominates, then exact title,
/// artist and album agreement, with strict rejection rules for wrong
/// artists, wrong versions and implausible durations.
library;

import '../song_query.dart';
import 'isrc.dart';
import 'text_normalizer.dart';
import 'track_candidate.dart';

/// Sentinel score meaning "this candidate is not acceptable at all".
const int rejectScore = -1000000;

/// Minimum score (without an exact ISRC match) to accept a candidate.
const int minAcceptableScore = 260;

/// Scores [candidate] against [query]. Returns [rejectScore] when the
/// candidate cannot be the requested track, otherwise a positive score.
int scoreCandidate({
  required TrackCandidate candidate,
  required SongQuery query,
}) {
  final wantedTitle = normalizeForMatch(query.title);
  final wantedArtists =
      query.artists.map(normalizeForMatch).where((a) => a.isNotEmpty).toList();
  final wantedAlbum = normalizeForMatch(query.album);
  final wantedIsrc = normalizeIsrc(query.isrc) ?? '';
  final wantedDurationSec =
      query.durationMs == null ? null : (query.durationMs! / 1000).round();
  final wantedTokens = significantTokens(wantedTitle);

  final candidateTitle = normalizeForMatch(candidate.title);
  final candidateAlbum = normalizeForMatch(candidate.album);
  final candidateIsrc = normalizeIsrc(candidate.isrc) ?? '';
  final candidateArtists = candidate.artists
      .map(normalizeForMatch)
      .where((a) => a.isNotEmpty)
      .toList();
  final candidateDurationSec = candidate.durationMs == null
      ? null
      : (candidate.durationMs! / 1000).round();

  if (wantedTitle.isEmpty) return rejectScore;

  // Check versions on the raw titles (parens intact), since candidates
  // carry versions like "Song (Remix)" inside the title — normalization
  // strips them and would hide the mismatch.
  final rawWanted = '${query.title} ${query.album ?? ''}'.toLowerCase();
  final rawCandidate = candidate.title.toLowerCase();
  if (hasVersionMismatch(rawWanted, rawCandidate)) {
    return rejectScore;
  }

  final isrcExact = wantedIsrc.isNotEmpty && candidateIsrc == wantedIsrc;
  var score = 0;
  if (isrcExact) score += 1000;

  // Title agreement.
  if (wantedTitle.isNotEmpty) {
    if (candidateTitle == wantedTitle) {
      score += 320;
    } else if (candidateTitle.contains(wantedTitle) ||
        wantedTitle.contains(candidateTitle)) {
      score += 130;
    } else if (wordsOverlap(wantedTitle, candidateTitle) >= 2) {
      score += 60;
    } else {
      score -= 80;
    }
  }

  // Token overlap.
  if (wantedTokens.isNotEmpty) {
    final candidateTokens = significantTokens(candidateTitle);
    final matched = wantedTokens.where(candidateTokens.contains).length;
    if (matched == wantedTokens.length) {
      score += 120;
    } else if (matched >= wantedTokens.length - 1) {
      score += 40;
    } else if (wantedTokens.length <= 2) {
      score -= 160;
    } else {
      score -= 60;
    }
  }

  // Album agreement.
  if (wantedAlbum.isNotEmpty && candidateAlbum.isNotEmpty) {
    if (candidateAlbum == wantedAlbum) {
      score += 180;
    } else if (candidateAlbum.contains(wantedAlbum) ||
        wantedAlbum.contains(candidateAlbum)) {
      score += 80;
    } else if (wordsOverlap(wantedAlbum, candidateAlbum) >= 2) {
      score += 35;
    } else {
      score -= 35;
    }
  }

  // Artist agreement — a mismatch is fatal.
  if (wantedArtists.isNotEmpty) {
    final exactMatches = wantedArtists.where(candidateArtists.contains).length;
    final partial = wantedArtists.any((wanted) => candidateArtists
        .any((candidate) => candidate.contains(wanted) || wanted.contains(candidate)));
    if (exactMatches > 0) {
      score += 220 + (exactMatches - 1) * 50;
    } else if (partial) {
      score += 90;
    } else {
      return rejectScore;
    }
  }

  // Duration plausibility.
  if (wantedDurationSec != null && candidateDurationSec != null) {
    final diff = (wantedDurationSec - candidateDurationSec).abs();
    if (diff <= 2) {
      score += 160;
    } else if (diff <= 5) {
      score += 100;
    } else if (diff <= 10) {
      score += 45;
    } else if (diff >= 30) {
      score -= 120;
    }
  }

  if (candidate.hires) score += 15;

  final acceptable =
      score > rejectScore && (score >= minAcceptableScore || isrcExact);
  return acceptable ? score : rejectScore;
}

/// Returns the best-scoring candidate above the acceptance threshold, or
/// null when nothing matches [query] confidently.
TrackCandidate? pickBestMatch(
  List<TrackCandidate> candidates,
  SongQuery query,
) {
  TrackCandidate? best;
  var bestScore = rejectScore;
  for (final candidate in candidates) {
    final score = scoreCandidate(candidate: candidate, query: query);
    if (score > bestScore) {
      best = candidate;
      bestScore = score;
    }
  }
  return best;
}
