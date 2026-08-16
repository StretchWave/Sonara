/// Conservative text normalization used ONLY for matching, never for
/// rewriting what the user sees.
///
/// Design rules:
///  * Tags that never identify a different recording ("feat.", "Official
///    Audio", "(Remastered)") are removed from comparison keys.
///  * Version markers that CAN identify a different recording (Live,
///    Acoustic, Remix, Radio Edit, Extended Mix, ...) are kept inside the
///    comparison key, so "Song - Live" and "Song" never compare equal.
library;

final RegExp _featRegExp = RegExp(
    r'(?:\b(?:feat|ft|featuring|feat\.|ft\.)\s*\.?\s+[^(\[\-–—]+'
    r'|\s*[\(\[]\s*(?:feat|ft|featuring)\.?\s+[^\)\]]+[\)\]])',
    caseSensitive: false);

/// Tags that can be dropped from a comparison key because they describe the
/// format of the same recording rather than a different recording.
final RegExp _editorialTagRegExp = RegExp(
    r'[\(\[]\s*(?:official\s*(?:audio|video|music\s*video|lyric\s*video)?'
    r'|lyrics?|hd|4k|8k|audio|video|visualizer)\s*[\)\]]'
    r'|\b(?:official\s*(?:audio|video|lyrics?))\b'
    r'|\b(?:remaster(?:ed)?(?:\s+\d{4})?|\d{4}\s+remaster(?:ed)?)\b'
    r'|(?:\s|^)(?:hd|4k|8k)(?=\s|$)',
    caseSensitive: false);

/// Version markers that signal a DIFFERENT performance/edit of the track.
/// These are preserved in comparison keys so they never collapse into the
/// studio original.
final List<String> versionMarkers = [
  'live',
  'acoustic',
  'remix',
  'radio edit',
  'extended mix',
  'extended',
  'instrumental',
  'demo',
  'karaoke',
  'sped up',
  'slowed',
  'reprise',
  'orchestral',
  'stripped',
  'unplugged',
  'piano version',
  'edit',
  'vip',
  'dub',
  'cover',
  'tribute',
  'nightcore',
  'live session',
  'from the vault',
];

/// Lowercases, trims and collapses whitespace. Does not strip version
/// markers or editorial tags — use [normalizeForComparison] for that.
String basicNormalize(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Produces a comparison key for a track title: editorial tags removed,
/// featuring sections removed, version markers preserved.
String normalizeTitleForComparison(String title) {
  var s = basicNormalize(title);
  s = s.replaceAll(_editorialTagRegExp, ' ');
  s = s.replaceAll(_featRegExp, ' ');
  s = s.replaceAll(RegExp(r'[^\w\s]'), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Produces a comparison key for an artist/album name.
String normalizeNameForComparison(String name) {
  var s = basicNormalize(name);
  s = s.replaceAll(RegExp(r'[^\w\s]'), ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// True when the title contains a version marker such as Live, Acoustic or
/// Remix. Used to penalize mismatches between a studio version and a
/// different performance/edit.
bool hasVersionMarker(String title) => versionMarkersOf(title).isNotEmpty;

/// Returns the version markers found in the title (Live, Remix, Cover, ...).
List<String> versionMarkersOf(String title) {
  final s = basicNormalize(title);
  return [
    for (final marker in versionMarkers)
      if (RegExp(r'\b' + RegExp.escape(marker) + r'\b').hasMatch(s)) marker,
  ];
}

/// Splits a normalized string into a set of significant tokens.
Set<String> tokenSet(String normalized) {
  return normalized
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toSet();
}

/// Similarity in [0, 1] between two comparison keys: exact match is 1.0,
/// containment (one key is a subset of the other) is high, otherwise the
/// Jaccard index over significant tokens.
double textSimilarity(String a, String b) {
  final na = basicNormalize(a);
  final nb = basicNormalize(b);
  if (na == nb) return 1.0;
  final ta = tokenSet(na);
  final tb = tokenSet(nb);
  if (ta.isEmpty || tb.isEmpty) return 0.0;
  final inter = ta.intersection(tb).length;
  if (inter == 0) return 0.0;
  final union = ta.union(tb).length;
  final jaccard = inter / union;
  if (ta.containsAll(tb) || tb.containsAll(ta)) {
    return 0.85 + 0.15 * jaccard;
  }
  return jaccard;
}

/// Removes the trailing "feat. Artist" part of a title for display purposes
/// (used only in generated search queries).
String stripFeaturing(String title) {
  return title.replaceAll(_featRegExp, ' ').replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Splits an artist display string on feature/duet/separator markers into
/// individual artist names, so "Artist A feat. Artist B", "Artist A & Artist
/// B" and "Artist A, Artist B" compare equal.
List<String> splitArtistList(String artistString) {
  return artistString
      .split(RegExp(
          r'\s+(?:feat|ft|featuring|with|&|and)\.?\s+|\s*[,\/;]\s*'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
