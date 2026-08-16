/// Text utilities for matching track metadata across different catalogs.
library;

/// Normalizes a string for fuzzy comparison: lowercases, expands "&",
/// strips bracketed/parenthesized annotations and punctuation, and
/// collapses whitespace.
///
/// NFD diacritic folding is intentionally not performed yet — it requires
/// an extra dependency and can be added later if matching accuracy demands
/// it.
String normalizeForMatch(String? value) {
  final text = (value ?? '').trim().toLowerCase();
  return text
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'\([^)]*\)'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Words that carry no distinguishing signal for track matching.
const Set<String> _stopWords = {
  'a',
  'an',
  'and',
  'feat',
  'ft',
  'for',
  'of',
  'the',
  'with',
};

/// Significant, order-insensitive tokens of [value] for overlap matching.
Set<String> significantTokens(String value) => normalizeForMatch(value)
    .split(' ')
    .where((token) => token.length > 1 && !_stopWords.contains(token))
    .toSet();

/// Count of shared words between two normalized strings.
int wordsOverlap(String first, String second) {
  final firstTokens = first.split(' ').where((token) => token.length > 1).toSet();
  final secondTokens = second.split(' ').where((token) => token.length > 1).toSet();
  return firstTokens.intersection(secondTokens).length;
}

/// Version descriptors that indicate a different recording than the
/// original (remix, live cut, edit, ...).
const List<String> versionTokens = [
  'remix',
  'live',
  'edit',
  'acoustic',
  'instrumental',
  'karaoke',
  'remaster',
  'remastered',
  'sped up',
  'slowed',
];

/// Returns true when [candidate] carries a version descriptor that the
/// [wanted] query does not — a strong signal these are different
/// recordings and should not be matched.
bool hasVersionMismatch(String wanted, String candidate) {
  final queryHasVersion = versionTokens.any(wanted.contains);
  final candidateHasVersion = versionTokens.any(candidate.contains);
  return candidateHasVersion && !queryHasVersion;
}
