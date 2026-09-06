/// Resolves a *trusted* ISRC for a track from a public catalog, so stream
/// providers can match the **exact recording** instead of fuzzy title/artist
/// scoring.
///
/// Ported from MetroFuse's `IsrcResolver`: a cover, remix or slowed/reverb
/// upload has a different ISRC than the original, so ISRC-keyed matching
/// excludes wrong versions by construction.  Resolution order:
///
///  1. A caller-supplied candidate ISRC (local tag / cached metadata) —
///     normalized + validated shape only, no network.
///  2. Deezer's public catalog, searched by song + artist; the best-scoring
///     result (via the shared match scorer, so a cover/remix is rejected)
///     supplies the ISRC.
///
/// Results are cached in-memory keyed by (song, artist, duration) so repeat
/// plays never re-hit the network.
library;

import '../deezer/deezer_api.dart';
import '../song_query.dart';
import 'isrc.dart';
import 'track_candidate.dart';
import 'track_scorer.dart';

class IsrcResolver {
  IsrcResolver({DeezerApi? deezerApi}) : _deezer = deezerApi ?? DeezerApi();

  final DeezerApi _deezer;

  /// Cache of resolved ISRCs keyed by song/artist/duration. An empty string
  /// means "resolution attempted and failed" (distinct from absent).
  final Map<String, String> _cache = {};

  static const String _negative = '';

  /// Returns a normalized, structurally valid ISRC for the track, or null
  /// when none could be resolved. Never throws — failures degrade to null
  /// so callers fall through to lower-confidence matching.
  Future<String?> resolve({
    String? candidateIsrc,
    required String song,
    required String artist,
    int? durationMs,
  }) async {
    final validated = normalizeIsrc(candidateIsrc);
    if (validated != null) return validated;

    if (song.trim().isEmpty || artist.trim().isEmpty) return null;

    final key = '${song.trim().toLowerCase()}::${artist.trim().toLowerCase()}'
        '::$durationMs';
    final cached = _cache[key];
    if (cached != null) return cached.isEmpty ? null : cached;

    final resolved = await _resolveViaDeezer(song, artist, durationMs);
    _cache[key] = resolved ?? _negative;
    return resolved;
  }

  /// Searches Deezer's public catalog and returns the ISRC of the
  /// best-scoring track that actually matches [song]/[artist]/[duration].
  Future<String?> _resolveViaDeezer(
    String song,
    String artist,
    int? durationMs,
  ) async {
    try {
      final items = await _deezer.searchTracks('$artist - $song', limit: 12);
      if (items.isEmpty) return null;
      final candidates = <TrackCandidate>[];
      for (final item in items) {
        final title = item['title']?.toString();
        if (title == null || title.isEmpty) continue;
        candidates.add(TrackCandidate(
          trackId: item['id']?.toString() ?? '',
          title: title,
          artists: _artistNames(item),
          album: item['album'] is Map
              ? (item['album'] as Map)['title']?.toString()
              : null,
          isrc: normalizeIsrc(item['isrc']?.toString()),
          durationMs: item['duration'] is num
              ? ((item['duration'] as num) * 1000).round()
              : null,
        ));
      }
      final query = SongQuery(
        mediaId: '',
        title: song,
        artists: [artist],
        durationMs: durationMs,
      );
      final best = pickBestMatch(candidates, query);
      if (best == null) return null;
      return normalizeIsrc(best.isrc);
    } catch (_) {
      return null;
    }
  }

  List<String> _artistNames(Map<String, dynamic> item) {
    final names = <String>[];
    void addName(Object? name) {
      final value = name?.toString();
      if (value != null && value.isNotEmpty && !names.contains(value)) {
        names.add(value);
      }
    }

    final artist = item['artist'];
    if (artist is Map) addName(artist['name']);
    final contributors = item['contributors'];
    if (contributors is List) {
      for (final entry in contributors) {
        if (entry is Map) addName(entry['name']);
      }
    }
    return names;
  }
}
