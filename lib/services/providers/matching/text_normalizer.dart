/// Text utilities for matching track metadata across different catalogs.
library;

import '../models/version_type.dart';
export '../models/version_type.dart' show VersionType, VersionClassifier;

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

/// Single-word version descriptors that indicate a different recording
/// than the original (remix, cover, live cut, ...). Matched as whole words
/// so ordinary words inside titles ("Undercover", "Deliverance") are not
/// false positives.
const List<String> versionWords = [
  'remix',
  'remixes',
  'live',
  'edit',
  'acoustic',
  'instrumental',
  'karaoke',
  'remaster',
  'remastered',
  'cover',
  'covers',
  'mix',
  'mixed',
  'mixes',
  'mashup',
  'medley',
  'tribute',
  'remake',
  'reverb',
  'reverbed',
  'nightcore',
  'chopped',
  'screwed',
  'orchestral',
  'acapella',
  'a cappella',
];

/// Multi-word version descriptors.
const List<String> versionPhrases = [
  'sped up',
  'bass boosted',
  'slowed reverb',
  'slowed and reverb',
  'chopped and screwed',
];

/// Words that mean "this is the original release", which neutralize a
/// version descriptor — e.g. "Original Mix" is the standard version of an
/// electronic track, not a remix.
const List<String> originalMarkers = ['original'];

/// Whether [text] carries any version descriptor (as a whole word/phrase).
bool containsVersionDescriptor(String text) {
  final lower = text.toLowerCase();
  for (final phrase in versionPhrases) {
    if (lower.contains(phrase)) return true;
  }
  for (final word in versionWords) {
    if (_containsWholeWord(lower, word)) return true;
  }
  return false;
}

/// Whether [text] explicitly marks itself as the original recording.
bool containsOriginalMarker(String text) {
  final lower = text.toLowerCase();
  return originalMarkers.any((word) => _containsWholeWord(lower, word));
}

/// Classifies the version of a track using structured phrase/word recognition.
VersionType classifyVersion(String title, [String? album]) {
  return VersionClassifier.classify(title, album);
}

/// Returns true when [candidate] carries a version descriptor that the
/// [wanted] query does not — a strong signal these are different
/// recordings and should not be matched.
bool hasVersionMismatch(String wanted, String candidate) {
  return VersionClassifier.hasVersionMismatch(wanted, null, candidate, null);
}

bool _containsWholeWord(String text, String word) {
  final escaped = RegExp.escape(word);
  return RegExp('(^|[^a-z0-9])$escaped([^a-z0-9]|\$)').hasMatch(text);
}
