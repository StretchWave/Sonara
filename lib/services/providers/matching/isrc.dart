/// ISRC (International Standard Recording Code) helpers.
library;

final RegExp _isrcPattern = RegExp(r'^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$');

/// Finds an ISRC embedded in text (e.g. "Song (USUM71703861)") — the
/// ISRC must be delimited by non-alphanumerics so prefix letters don't
/// produce false matches.
final RegExp _isrcInText =
    RegExp(r'(^|[^A-Z0-9])([A-Z]{2}[A-Z0-9]{3}[0-9]{7})([^A-Z0-9]|$)');

/// Extracts and normalizes an ISRC from [value], or returns null when none
/// is present. The canonical form is 12 characters: two-letter country
/// code, three-char registrant code, two-digit year, five-digit
/// designation. Separators (hyphens, spaces, ...) are tolerated.
String? normalizeIsrc(String? value) {
  if (value == null) return null;
  final upper = value.toUpperCase();
  final compact = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (compact.isEmpty) return null;
  if (_isrcPattern.hasMatch(compact)) return compact;
  return _isrcInText.firstMatch(upper)?.group(2);
}

/// True when [mediaId] is itself an ISRC (some catalogs use ISRCs as
/// track ids).
bool isIsrcMediaId(String mediaId) => normalizeIsrc(mediaId) != null;
