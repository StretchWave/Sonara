/// Scoring and matching engine for evaluating cross-catalog candidates against
/// requested recordings.
library;

import '../models/match_decision.dart';
import '../models/routing_policy.dart';
import '../song_query.dart';
import 'artist_matcher.dart';
import 'duration_policy.dart';
import 'isrc.dart';
import 'text_normalizer.dart';
import 'track_candidate.dart';

/// Sentinel score meaning "this candidate is not acceptable at all".
const int rejectScore = -1000000;

/// Minimum score (without an exact ISRC match) to accept a candidate.
const int minAcceptableScore = 260;

/// Evaluates [candidate] against [query] and produces a structured,
/// explainable [MatchDecision].
MatchDecision evaluateCandidate({
  required TrackCandidate candidate,
  required SongQuery query,
  DurationTolerancePolicy tolerancePolicy = DurationTolerancePolicy.standard,
}) {
  final wantedTitle = normalizeForMatch(query.title);
  final wantedAlbum = normalizeForMatch(query.album);
  final wantedIsrc = normalizeIsrc(query.isrc) ?? '';
  final wantedTokens = significantTokens(wantedTitle);

  final candidateTitle = normalizeForMatch(candidate.title);
  final candidateAlbum = normalizeForMatch(candidate.album);
  final candidateIsrc = normalizeIsrc(candidate.isrc) ?? '';

  if (wantedTitle.isEmpty) {
    return MatchDecision.rejected('Requested track title is empty',
        rawScore: rejectScore);
  }

  // 1. Version gate: compare full title + album strings with VersionClassifier
  final rawWanted = '${query.title} ${query.album ?? ''}'.toLowerCase();
  final rawCandidate =
      '${candidate.title} ${candidate.album ?? ''}'.toLowerCase();
  final queryHasVersion = containsVersionDescriptor(rawWanted);

  final versionMismatch = hasVersionMismatch(rawWanted, rawCandidate);
  if (versionMismatch) {
    return MatchDecision.rejected(
      'Version mismatch: candidate carries version descriptor not in query',
      rawScore: rejectScore,
      breakdown: const {'version': -1000000},
    );
  }

  final isrcExact = wantedIsrc.isNotEmpty && candidateIsrc == wantedIsrc;
  final breakdown = <String, int>{};
  final reasons = <String>[];
  final warnings = <String>[];
  var score = 0;

  if (isrcExact) {
    score += 1000;
    breakdown['isrc'] = 1000;
    reasons.add('Exact ISRC match ($candidateIsrc)');
  }

  // 2. Title agreement
  var titleScore = 0;
  if (wantedTitle.isNotEmpty) {
    if (candidateTitle == wantedTitle) {
      titleScore = 320;
      reasons.add('Exact title match');
    } else if (candidateTitle.contains(wantedTitle) ||
        wantedTitle.contains(candidateTitle)) {
      titleScore = 130;
      reasons.add('Title substring match');
    } else if (wordsOverlap(wantedTitle, candidateTitle) >= 2) {
      titleScore = 60;
      reasons.add('Title word overlap');
    } else {
      titleScore = -80;
      warnings.add('Low title similarity');
    }
  }
  score += titleScore;
  breakdown['title'] = titleScore;

  // 3. Token overlap
  var tokenScore = 0;
  if (wantedTokens.isNotEmpty) {
    final candidateTokens = significantTokens(candidateTitle);
    final matched = wantedTokens.where(candidateTokens.contains).length;
    if (matched == wantedTokens.length) {
      tokenScore = 120;
    } else if (matched >= wantedTokens.length - 1) {
      tokenScore = 40;
    } else if (wantedTokens.length <= 2) {
      tokenScore = -160;
    } else {
      tokenScore = -60;
    }
  }
  score += tokenScore;
  breakdown['tokens'] = tokenScore;

  // 4. Album agreement
  var albumScore = 0;
  if (wantedAlbum.isNotEmpty && candidateAlbum.isNotEmpty) {
    if (candidateAlbum == wantedAlbum) {
      albumScore = 180;
      reasons.add('Exact album match');
    } else if (candidateAlbum.contains(wantedAlbum) ||
        wantedAlbum.contains(candidateAlbum)) {
      albumScore = 80;
    } else if (wordsOverlap(wantedAlbum, candidateAlbum) >= 2) {
      albumScore = 35;
    } else {
      albumScore = -35;
    }
  }
  score += albumScore;
  breakdown['album'] = albumScore;

  // 5. Artist agreement using intelligent artist matcher
  final artistResult = matchArtists(
    wantedArtists: query.artists,
    candidateArtists: candidate.artists,
  );

  if (!artistResult.isCompatible) {
    return MatchDecision.rejected(
      artistResult.description,
      rawScore: rejectScore,
      breakdown: {...breakdown, 'artist': rejectScore},
    );
  }

  score += artistResult.scoreContribution;
  breakdown['artist'] = artistResult.scoreContribution;
  if (artistResult.primaryMatches) {
    reasons.add(artistResult.description);
  }

  // 6. Duration gate and evaluation
  final isLive = classifyVersion(query.title, query.album) == VersionType.live;
  final durationResult = evaluateDuration(
    expectedMs: query.durationMs,
    candidateMs: candidate.durationMs,
    policy: tolerancePolicy,
    isLiveRecording: isLive,
    isrcExact: isrcExact,
  );

  if (!durationResult.isAcceptable && !isrcExact) {
    return MatchDecision.rejected(
      durationResult.description,
      rawScore: rejectScore,
      breakdown: {...breakdown, 'duration': rejectScore},
    );
  }

  score += durationResult.scoreContribution;
  breakdown['duration'] = durationResult.scoreContribution;
  if (durationResult.diffMs != null) {
    final diffSec = (durationResult.diffMs!.abs() / 1000).toStringAsFixed(1);
    reasons.add('Duration within ${diffSec}s');
  }

  // 7. Version preference bonus
  var versionScore = 0;
  if (!queryHasVersion && !containsVersionDescriptor(rawCandidate)) {
    versionScore = 25;
    score += versionScore;
  }
  breakdown['version'] = versionScore;

  // 8. Quality / HiRes bonus
  var hiresScore = 0;
  if (candidate.hires) {
    hiresScore = 15;
    score += hiresScore;
    reasons.add('Hi-Res audio available');
  }
  breakdown['hires'] = hiresScore;

  return MatchDecision.fromScore(
    score: score,
    isrcMatch: isrcExact,
    breakdown: breakdown,
    reasons: reasons,
    warnings: warnings,
    durationDiffMs: durationResult.diffMs,
    versionCompatible: true,
    artistCompatible: true,
    method: isrcExact ? MatchMethod.isrcExact : MatchMethod.fuzzyMetadata,
    rejectScore: rejectScore,
    minAcceptable: minAcceptableScore,
  );
}

/// Computes a numeric score for [candidate] against [query].
///
/// Returns [rejectScore] if the candidate fails verification, otherwise a
/// positive score representing match quality.
int scoreCandidate({
  required TrackCandidate candidate,
  required SongQuery query,
  DurationTolerancePolicy tolerancePolicy = DurationTolerancePolicy.standard,
}) {
  final decision = evaluateCandidate(
    candidate: candidate,
    query: query,
    tolerancePolicy: tolerancePolicy,
  );
  return decision.accepted ? decision.rawScore : rejectScore;
}

/// Returns the best-scoring candidate above the acceptance threshold, or
/// null when nothing matches [query] confidently.
TrackCandidate? pickBestMatch(
  List<TrackCandidate> candidates,
  SongQuery query, {
  DurationTolerancePolicy tolerancePolicy = DurationTolerancePolicy.standard,
}) {
  final result = pickBestMatchWithDecision(
    candidates,
    query,
    tolerancePolicy: tolerancePolicy,
  );
  return result?.candidate;
}

/// Returns the best match along with its structured [MatchDecision].
({TrackCandidate candidate, MatchDecision decision})? pickBestMatchWithDecision(
  List<TrackCandidate> candidates,
  SongQuery query, {
  DurationTolerancePolicy tolerancePolicy = DurationTolerancePolicy.standard,
}) {
  TrackCandidate? best;
  MatchDecision? bestDecision;
  var bestScore = rejectScore;

  for (final candidate in candidates) {
    final decision = evaluateCandidate(
      candidate: candidate,
      query: query,
      tolerancePolicy: tolerancePolicy,
    );
    if (decision.accepted && decision.rawScore > bestScore) {
      best = candidate;
      bestDecision = decision;
      bestScore = decision.rawScore;
    }
  }

  if (best != null && bestDecision != null) {
    return (candidate: best, decision: bestDecision);
  }
  return null;
}
