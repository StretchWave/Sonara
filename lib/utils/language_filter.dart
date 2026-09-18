import '../ui/screens/Onboarding/language_selection_step.dart';

/// Set of language codes that represent Indian regional languages.
const Set<String> indianLanguageCodes = {
  'hi',
  'ml',
  'ta',
  'te',
  'kn',
  'bn',
  'pa',
  'mr',
  'gu',
  'or',
  'ur',
};

/// Script regexes mapping Unicode ranges to language codes.
final Map<String, RegExp> _scriptRegexes = {
  'hi': RegExp(r'[\u0900-\u097F]'), // Devanagari (Hindi, Marathi, Nepali)
  'mr': RegExp(r'[\u0900-\u097F]'),
  'bn': RegExp(r'[\u0980-\u09FF]'), // Bengali / Assamese
  'pa': RegExp(r'[\u0A00-\u0A7F]'), // Gurmukhi (Punjabi)
  'gu': RegExp(r'[\u0A80-\u0AFF]'), // Gujarati
  'or': RegExp(r'[\u0B00-\u0B7F]'), // Odia
  'ta': RegExp(r'[\u0B80-\u0BFF]'), // Tamil
  'te': RegExp(r'[\u0C00-\u0C7F]'), // Telugu
  'kn': RegExp(r'[\u0C80-\u0CFF]'), // Kannada
  'ml': RegExp(r'[\u0D00-\u0D7F]'), // Malayalam
  'ur': RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]'), // Arabic / Urdu
  'ar': RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]'),
  'fa': RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]'),
  'ko': RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF]'), // Korean
  'ja': RegExp(r'[\u3040-\u30FF\u4E00-\u9FAF]'), // Japanese
  'zh': RegExp(r'[\u4E00-\u9FFF]'), // Chinese
  'ru': RegExp(r'[\u0400-\u04FF]'), // Cyrillic (Russian)
  'th': RegExp(r'[\u0E00-\u0E7F]'), // Thai
};

/// Keywords that indicate Indian regional music content.
final List<String> _indianRegionalKeywords = [
  'bollywood',
  'tollywood',
  'kollywood',
  'mollywood',
  'sandalwood',
  'ghazal',
  'qawwali',
  'sufi',
  'bhangra',
  'punjabi',
  'desi',
  'hindi',
  'tamil',
  'telugu',
  'kannada',
  'malayalam',
  'marathi',
  'bhojpuri',
  'gujarati',
  'bengali',
  'odia',
  'bhajan',
  'aarti',
  'kirtan',
  'indie india',
  'indian indie',
  'indian pop',
  'india pop',
  'sukoon ke pal',
  'uncut bollywood',
  'coffee brew',
  'lo-fi bollywood',
  'bollywood lo-fi',
  'old is gold',
  'wali vide',
];

/// Prominent playback artists who sing almost exclusively in Indian regional languages.
final List<String> _prominentIndianArtists = [
  'arijit singh',
  'neha kakkar',
  'jubin nautiyal',
  'shreya ghoshal',
  'vishal mishra',
  'parampara tandon',
  'sachet tandon',
  'sachet-parampara',
  'b praak',
  'badshah',
  'diljit dosanjh',
  'sidhu moose wala',
  'guru randhawa',
  'ap dhillon',
  'pritam',
  'kumar sanu',
  'alka yagnik',
  'udit narayan',
  'sonu nigam',
  'lata mangeshkar',
  'kishore kumar',
  'jagjit singh',
  'mohammed rafi',
  'anuv jain',
  'darshan raval',
  'stebin ben',
  'armaan malik',
  'sunidhi chauhan',
  'sid sriram',
  'anirudh ravichander',
  'devi sri prasad',
  'gv prakash',
  'g.v. prakash',
  'ilaiyaraaja',
  'ilayaraja',
  'sp balasubrahmanyam',
  's. p. balasubrahmanyam',
  'k.j. yesudas',
  'k. j. yesudas',
  'atif aslam',
  'rahat fateh ali khan',
  'yo yo honey singh',
  'honey singh',
  'himesh reshammiya',
  'mika singh',
  'jasleen royal',
  'dhvani bhanushali',
  'tulsi kumar',
  'monali thakur',
  'harshdeep kaur',
  'kanika kapoor',
  'shankar mahadevan',
  'hariharan',
  'kavita krishnamurthy',
  'anuradha paudwal',
  'shaan',
  'kk',
  'pankaj udhas',
  'mithoon',
  'tanishk bagchi',
];

/// Helper class for determining language compatibility and filtering out
/// unwanted regional content based on the user's explicit language preferences.
class LanguageFilter {
  /// Detects whether [text] contains any non-Latin script associated with
  /// a specific language code.
  static String? detectScriptLanguage(String text) {
    if (text.isEmpty) return null;
    for (final entry in _scriptRegexes.entries) {
      if (entry.value.hasMatch(text)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Checks whether [text] matches known regional Indian keywords or playback artists.
  static bool matchesIndianRegionalMarkers(String text) {
    if (text.isEmpty) return false;
    final lower = text.toLowerCase();
    for (final kw in _indianRegionalKeywords) {
      if (lower.contains(kw)) return true;
    }
    for (final artist in _prominentIndianArtists) {
      if (lower.contains(artist)) return true;
    }
    return false;
  }

  /// Tests whether a given [title] and [artist] are compatible with [allowedLanguages].
  ///
  /// If [allowedLanguages] is empty, returns `true` (all languages allowed).
  /// If the user has favorited the artist (in [favoriteArtistNames]), the item
  /// is always allowed regardless of language.
  static bool isSongAllowed({
    required String title,
    required String artist,
    required List<String> allowedLanguages,
    Set<String>? favoriteArtistNames,
  }) {
    if (allowedLanguages.isEmpty) return true;

    final artistLower = artist.toLowerCase().trim();
    if (favoriteArtistNames != null && favoriteArtistNames.isNotEmpty) {
      for (final fav in favoriteArtistNames) {
        if (fav.isNotEmpty &&
            (artistLower.contains(fav) || fav.contains(artistLower))) {
          return true;
        }
      }
    }

    final combinedText = '$title $artist';

    // 1. Check non-Latin script detection
    final scriptLang = detectScriptLanguage(combinedText);
    if (scriptLang != null) {
      if (!allowedLanguages.contains(scriptLang)) {
        return false;
      }
    }

    // 2. Check Indian regional markers if no Indian language is in allowedLanguages
    final hasIndianLanguage =
        allowedLanguages.any((lang) => indianLanguageCodes.contains(lang));
    if (!hasIndianLanguage) {
      if (matchesIndianRegionalMarkers(combinedText)) {
        return false;
      }
    }

    return true;
  }

  /// Tests whether a playlist or album item is compatible with [allowedLanguages].
  static bool isContentAllowed({
    required String title,
    String? subtitle,
    required List<String> allowedLanguages,
    Set<String>? favoriteArtistNames,
  }) {
    return isSongAllowed(
      title: title,
      artist: subtitle ?? '',
      allowedLanguages: allowedLanguages,
      favoriteArtistNames: favoriteArtistNames,
    );
  }

  /// Determines whether [text] matches a specific [langCode].
  ///
  /// Handles Latin script for English ('en') and other European languages,
  /// as well as script/keyword matching for non-Latin languages.
  static bool matchesLanguage(String text, String langCode) {
    if (text.isEmpty) return false;
    final lower = text.toLowerCase();

    // Direct language name check (e.g. "English", "Hindi")
    final langName = musicLanguageMap[langCode]?.toLowerCase();
    if (langName != null && lower.contains(langName)) return true;

    // Script regex match
    final regex = _scriptRegexes[langCode];
    if (regex != null && regex.hasMatch(text)) return true;

    // English detection: Latin alphabet characters without disallowed regional markers
    if (langCode == 'en') {
      final hasLatin = RegExp(r'[a-zA-Z]').hasMatch(text);
      final hasNonLatinScript = detectScriptLanguage(text) != null;
      final isRegional = matchesIndianRegionalMarkers(text);
      return hasLatin && !hasNonLatinScript && !isRegional;
    }

    return false;
  }
}
