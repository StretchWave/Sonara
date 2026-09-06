/// Intelligent artist matching that distinguishes primary artists from
/// featured artists, remixers, and contributors.
library;

import 'text_normalizer.dart';

/// Result of evaluating artist compatibility between a query and a candidate.
class ArtistMatchResult {
  /// Whether the primary artists are compatible (i.e. not completely different).
  final bool primaryMatches;

  /// Overall compatibility (false means fatal mismatch, must reject).
  final bool isCompatible;

  /// Count of artists that match exactly (after normalization).
  final int exactMatchesCount;

  /// Whether there is at least a partial match between artist names.
  final bool partialMatch;

  /// Recommended score contribution (+/-).
  final int scoreContribution;

  /// Explanatory message for matching breakdown or debugging.
  final String description;

  const ArtistMatchResult({
    required this.primaryMatches,
    required this.isCompatible,
    required this.exactMatchesCount,
    required this.partialMatch,
    required this.scoreContribution,
    required this.description,
  });

  /// Fatal mismatch result.
  factory ArtistMatchResult.rejected(String reason) => ArtistMatchResult(
        primaryMatches: false,
        isCompatible: false,
        exactMatchesCount: 0,
        partialMatch: false,
        scoreContribution: -500,
        description: reason,
      );
}

/// Parsed artist representation separating primary and featured artists.
class ParsedArtistList {
  final List<String> primaryArtists;
  final List<String> featuredArtists;

  const ParsedArtistList({
    required this.primaryArtists,
    required this.featuredArtists,
  });

  List<String> get allArtists => [...primaryArtists, ...featuredArtists];

  /// Parses raw artist strings (e.g. "Eminem feat. Rihanna", "Drake & 21 Savage").
  factory ParsedArtistList.parse(List<String> rawArtists) {
    final primary = <String>[];
    final featured = <String>[];

    for (final raw in rawArtists) {
      if (raw.trim().isEmpty) continue;
      final parts = _splitFeatured(raw);
      primary.addAll(parts.primary);
      featured.addAll(parts.featured);
    }

    return ParsedArtistList(
      primaryArtists: primary.toSet().toList(),
      featuredArtists: featured.toSet().toList(),
    );
  }

  static ({List<String> primary, List<String> featured}) _splitFeatured(
      String text) {
    // Check for "feat.", "ft.", "featuring", "with"
    final featRegex = RegExp(
      r'[\(\[\s](?:feat\.?|ft\.?|featuring|with)\s+([^\)\]]+)[\)\]]?',
      caseSensitive: false,
    );

    final featMatches = featRegex.allMatches(text);
    final featured = <String>[];
    var primaryText = text;

    for (final match in featMatches) {
      final featGroup = match.group(1);
      if (featGroup != null) {
        featured.addAll(_splitDelimiters(featGroup));
      }
      primaryText = primaryText.replaceAll(match.group(0)!, ' ');
    }

    final primary = _splitDelimiters(primaryText);
    return (primary: primary, featured: featured);
  }

  static List<String> _splitDelimiters(String text) {
    // Split by comma, &, +, x (collaboration), "and"
    final delimiters = RegExp(
      r'\s*(?:,|&|\+|\sand\s|\sx\s|\svs\.?\s)\s*',
      caseSensitive: false,
    );
    return text
        .split(delimiters)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}

/// Evaluates whether the artists on [candidate] match the artists requested in [query].
ArtistMatchResult matchArtists({
  required List<String> wantedArtists,
  required List<String> candidateArtists,
}) {
  if (wantedArtists.isEmpty) {
    return const ArtistMatchResult(
      primaryMatches: true,
      isCompatible: true,
      exactMatchesCount: 0,
      partialMatch: false,
      scoreContribution: 0,
      description: 'No artists specified in query',
    );
  }

  if (candidateArtists.isEmpty) {
    return const ArtistMatchResult(
      primaryMatches: false,
      isCompatible: false,
      exactMatchesCount: 0,
      partialMatch: false,
      scoreContribution: -200,
      description: 'Candidate has no artist information',
    );
  }

  final parsedWanted = ParsedArtistList.parse(wantedArtists);
  final parsedCandidate = ParsedArtistList.parse(candidateArtists);

  final normWantedPrimary =
      parsedWanted.primaryArtists.map(normalizeForMatch).toSet();
  final normCandidatePrimary =
      parsedCandidate.primaryArtists.map(normalizeForMatch).toSet();

  final normWantedAll = parsedWanted.allArtists.map(normalizeForMatch).toSet();
  final normCandidateAll =
      parsedCandidate.allArtists.map(normalizeForMatch).toSet();

  // 1. Check exact primary artist overlap
  final primaryExactMatches =
      normWantedPrimary.intersection(normCandidatePrimary).length;
  final allExactMatches = normWantedAll.intersection(normCandidateAll).length;

  if (primaryExactMatches > 0) {
    final bonus = 220 + (allExactMatches - 1) * 50;
    return ArtistMatchResult(
      primaryMatches: true,
      isCompatible: true,
      exactMatchesCount: allExactMatches,
      partialMatch: true,
      scoreContribution: bonus,
      description: 'Primary artist matched exactly ($primaryExactMatches found)',
    );
  }

  // 2. Check if primary artist is matched in all candidate artists (maybe candidate swapped order)
  final primaryInCandidateAll =
      normWantedPrimary.intersection(normCandidateAll).length;
  if (primaryInCandidateAll > 0) {
    return ArtistMatchResult(
      primaryMatches: true,
      isCompatible: true,
      exactMatchesCount: primaryInCandidateAll,
      partialMatch: true,
      scoreContribution: 160,
      description: 'Primary artist found in candidate artist list',
    );
  }

  // 3. Partial / substring matching across normalized strings
  var partialMatchesCount = 0;
  for (final w in normWantedAll) {
    if (w.isEmpty) continue;
    for (final c in normCandidateAll) {
      if (c.isEmpty) continue;
      if (w == c || w.contains(c) || c.contains(w)) {
        partialMatchesCount++;
        break;
      }
    }
  }

  if (partialMatchesCount > 0) {
    // E.g. "The Weeknd" vs "Weeknd"
    return const ArtistMatchResult(
      primaryMatches: true,
      isCompatible: true,
      exactMatchesCount: 0,
      partialMatch: true,
      scoreContribution: 90,
      description: 'Partial artist name match found',
    );
  }

  // 4. Fallback check on raw normalized inputs (unparsed) in case parsing altered structure
  final simpleWanted = wantedArtists.map(normalizeForMatch).toSet();
  final simpleCandidate = candidateArtists.map(normalizeForMatch).toSet();

  final simpleExact = simpleWanted.intersection(simpleCandidate).length;
  if (simpleExact > 0) {
    return ArtistMatchResult(
      primaryMatches: true,
      isCompatible: true,
      exactMatchesCount: simpleExact,
      partialMatch: true,
      scoreContribution: 220,
      description: 'Artist matched without separator parsing',
    );
  }

  final simplePartial = simpleWanted.any((w) =>
      simpleCandidate.any((c) => w.contains(c) || c.contains(w)));
  if (simplePartial) {
    return const ArtistMatchResult(
      primaryMatches: true,
      isCompatible: true,
      exactMatchesCount: 0,
      partialMatch: true,
      scoreContribution: 90,
      description: 'Partial artist match on full string',
    );
  }

  // Fatal artist mismatch
  return ArtistMatchResult.rejected(
    'Artist mismatch: wanted [${wantedArtists.join(", ")}], '
    'candidate has [${candidateArtists.join(", ")}]',
  );
}
