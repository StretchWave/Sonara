import '../song_query.dart';
import 'isrc.dart';

/// Ordered search queries to try against a provider catalog, from most to
/// least specific: ISRC first, then title+artist+album combinations.
List<String> buildSearchTerms(SongQuery query) {
  final title = query.title.trim();
  final artists = query.artists.map((a) => a.trim()).toList();
  final artistPart = artists.take(3).join(' ');
  final album = query.album?.trim() ?? '';
  final terms = <String>{};

  final isrc = normalizeIsrc(query.isrc);
  if (isrc != null && isrc.isNotEmpty) terms.add(isrc);

  final parts = <String>[
    if (title.isNotEmpty) title,
    if (artists.isNotEmpty) artists.first,
    if (album.isNotEmpty) album,
  ];
  if (parts.isNotEmpty) terms.add(parts.join(' '));

  final partsAll = <String>[
    if (title.isNotEmpty) title,
    if (artistPart.isNotEmpty) artistPart,
    if (album.isNotEmpty) album,
  ];
  if (partsAll.isNotEmpty) terms.add(partsAll.join(' '));

  if (title.isNotEmpty && artists.isNotEmpty) {
    terms.add('$title ${artists.first}');
  }
  if (title.isNotEmpty && artistPart.isNotEmpty) {
    terms.add('$title $artistPart');
  }
  if (title.isNotEmpty && album.isNotEmpty) terms.add('$title $album');
  if (title.isNotEmpty) terms.add(title);
  return terms.toList();
}
