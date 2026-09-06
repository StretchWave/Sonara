/// Version classification for recordings, using word boundaries and phrase
/// recognition instead of endlessly expanding keyword lists.
library;

/// A recording version type, used to distinguish recordings that share a
/// title but represent materially different performances or edits.
enum VersionType {
  original,
  albumVersion,
  radioEdit,
  extended,
  live,
  acoustic,
  remix,
  remaster,
  instrumental,
  karaoke,
  cover,
  medley,
  mashup,
  slowed,
  spedUp,
  reverb,
  choppedScrewed,
  orchestral,
  tribute,
  remake,
  nightcore,
  bassBoosted,
  acapella,
  unknown;

  /// Human-readable label for display.
  String get label => switch (this) {
        original => 'Original',
        albumVersion => 'Album Version',
        radioEdit => 'Radio Edit',
        extended => 'Extended',
        live => 'Live',
        acoustic => 'Acoustic',
        remix => 'Remix',
        remaster => 'Remastered',
        instrumental => 'Instrumental',
        karaoke => 'Karaoke',
        cover => 'Cover',
        medley => 'Medley',
        mashup => 'Mashup',
        slowed => 'Slowed',
        spedUp => 'Sped Up',
        reverb => 'Reverb',
        choppedScrewed => 'Chopped & Screwed',
        orchestral => 'Orchestral',
        tribute => 'Tribute',
        remake => 'Remake',
        nightcore => 'Nightcore',
        bassBoosted => 'Bass Boosted',
        acapella => 'A Cappella',
        unknown => 'Unknown',
      };

  /// Whether this version type represents the standard/original recording.
  bool get isStandardVersion =>
      this == original || this == albumVersion || this == remaster;

  /// Whether this version is a fundamentally different performance/recording.
  bool get isDifferentRecording =>
      this != original &&
      this != albumVersion &&
      this != remaster &&
      this != unknown;
}

/// Classifies the version type of a track from its title and album metadata.
///
/// Uses word boundaries and multi-word phrase detection to avoid false
/// positives from ordinary words (e.g. "Undercover" should NOT match "cover").
class VersionClassifier {
  const VersionClassifier._();

  /// Multi-word phrases checked first (order matters — more specific first).
  static const List<(String, VersionType)> _phrases = [
    ('slowed and reverb', VersionType.slowed),
    ('slowed + reverb', VersionType.slowed),
    ('slowed reverb', VersionType.slowed),
    ('chopped and screwed', VersionType.choppedScrewed),
    ('chopped screwed', VersionType.choppedScrewed),
    ('sped up', VersionType.spedUp),
    ('bass boosted', VersionType.bassBoosted),
    ('radio edit', VersionType.radioEdit),
    ('radio version', VersionType.radioEdit),
    ('album version', VersionType.albumVersion),
    ('original mix', VersionType.original),
    ('original version', VersionType.original),
    ('a cappella', VersionType.acapella),
  ];

  /// Single-word tokens checked with word boundaries.
  static const List<(String, VersionType)> _words = [
    ('remix', VersionType.remix),
    ('remixed', VersionType.remix),
    ('remixes', VersionType.remix),
    ('live', VersionType.live),
    ('acoustic', VersionType.acoustic),
    ('instrumental', VersionType.instrumental),
    ('karaoke', VersionType.karaoke),
    ('cover', VersionType.cover),
    ('covers', VersionType.cover),
    ('remaster', VersionType.remaster),
    ('remastered', VersionType.remaster),
    ('extended', VersionType.extended),
    ('mashup', VersionType.mashup),
    ('medley', VersionType.medley),
    ('tribute', VersionType.tribute),
    ('remake', VersionType.remake),
    ('reverb', VersionType.reverb),
    ('reverbed', VersionType.reverb),
    ('nightcore', VersionType.nightcore),
    ('orchestral', VersionType.orchestral),
    ('acapella', VersionType.acapella),
    ('slowed', VersionType.slowed),
    ('chopped', VersionType.choppedScrewed),
    ('screwed', VersionType.choppedScrewed),
    ('edit', VersionType.radioEdit),
    ('mix', VersionType.remix),
    ('mixed', VersionType.remix),
    ('mixes', VersionType.remix),
  ];

  /// Classifies the version type from combined title + album text.
  ///
  /// Returns [VersionType.original] when the text explicitly marks itself
  /// as the original, and [VersionType.unknown] when no version descriptor
  /// is found.
  static VersionType classify(String title, [String? album]) {
    final text = '$title ${album ?? ''}'.toLowerCase();

    // Check multi-word phrases first (more specific).
    for (final (phrase, type) in _phrases) {
      if (text.contains(phrase)) {
        // "Original Mix" / "Original Version" means standard version.
        if (type == VersionType.original) return VersionType.original;
        return type;
      }
    }

    // Check single-word tokens with word boundaries.
    for (final (word, type) in _words) {
      if (_containsWholeWord(text, word)) {
        return type;
      }
    }

    return VersionType.unknown;
  }

  /// Whether [text] contains any version descriptor at all.
  static bool hasVersionDescriptor(String title, [String? album]) {
    final type = classify(title, album);
    return type != VersionType.unknown && type != VersionType.original;
  }

  /// Whether two texts have a version mismatch — one has a version
  /// descriptor and the other does not, suggesting different recordings.
  ///
  /// A candidate labeled "Original Mix" or "Original Version" is NOT
  /// considered a mismatch (it IS the standard version).
  static bool hasVersionMismatch(
    String wantedTitle,
    String? wantedAlbum,
    String candidateTitle,
    String? candidateAlbum,
  ) {
    final wantedType = classify(wantedTitle, wantedAlbum);
    final candidateType = classify(candidateTitle, candidateAlbum);

    // If the wanted track has a specific version, the candidate must match.
    if (wantedType.isDifferentRecording && candidateType.isDifferentRecording) {
      return wantedType != candidateType;
    }

    // Wanted is standard/unknown, candidate has a version → mismatch.
    if (!wantedType.isDifferentRecording && candidateType.isDifferentRecording) {
      return true;
    }

    // Wanted has a version, candidate is standard → mismatch.
    if (wantedType.isDifferentRecording && !candidateType.isDifferentRecording) {
      return true;
    }

    return false;
  }

  static bool _containsWholeWord(String text, String word) {
    final escaped = RegExp.escape(word);
    return RegExp('(?:^|[^a-z0-9])$escaped(?:[^a-z0-9]|\$)').hasMatch(text);
  }
}
