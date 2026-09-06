/// Resolves an ISRC for a track from metadata or a public catalog (Deezer),
/// tracking resolution provenance and enforcing timeouts.
library;

import 'dart:async';

import '../deezer/deezer_api.dart';
import '../song_query.dart';
import 'isrc.dart';
import 'track_candidate.dart';
import 'track_scorer.dart';

/// Provenance of an ISRC resolution.
enum IsrcProvenance {
  /// Provided directly by caller or track metadata (e.g. tags).
  provided,

  /// Resolved via public catalog (Deezer) search and verified by matching engine.
  catalogSearch,

  /// Retrieved from memory cache.
  cached,

  /// No ISRC could be established.
  none,
}

/// Detailed result of an ISRC resolution attempt.
class IsrcResolutionResult {
  final String? isrc;
  final IsrcProvenance provenance;
  final DateTime resolvedAt;
  final String? note;

  const IsrcResolutionResult({
    this.isrc,
    required this.provenance,
    required this.resolvedAt,
    this.note,
  });

  bool get isFound => isrc != null && isrc!.isNotEmpty;

  factory IsrcResolutionResult.none([String? note]) => IsrcResolutionResult(
        isrc: null,
        provenance: IsrcProvenance.none,
        resolvedAt: DateTime.now(),
        note: note,
      );

  factory IsrcResolutionResult.provided(String isrc) => IsrcResolutionResult(
        isrc: isrc,
        provenance: IsrcProvenance.provided,
        resolvedAt: DateTime.now(),
        note: 'Provided in source metadata',
      );

  factory IsrcResolutionResult.cached(String isrc) => IsrcResolutionResult(
        isrc: isrc,
        provenance: IsrcProvenance.cached,
        resolvedAt: DateTime.now(),
        note: 'Loaded from cache',
      );

  factory IsrcResolutionResult.catalog(String isrc) => IsrcResolutionResult(
        isrc: isrc,
        provenance: IsrcProvenance.catalogSearch,
        resolvedAt: DateTime.now(),
        note: 'Resolved via Deezer catalog search',
      );
}

class IsrcResolver {
  IsrcResolver({
    DeezerApi? deezerApi,
    Duration defaultTimeout = const Duration(seconds: 5),
  })  : _deezer = deezerApi ?? DeezerApi(),
        _timeout = defaultTimeout;

  final DeezerApi _deezer;
  final Duration _timeout;

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
    final result = await resolveWithProvenance(
      candidateIsrc: candidateIsrc,
      song: song,
      artist: artist,
      durationMs: durationMs,
    );
    return result.isrc;
  }

  /// Resolves an ISRC with provenance details.
  Future<IsrcResolutionResult> resolveWithProvenance({
    String? candidateIsrc,
    required String song,
    required String artist,
    int? durationMs,
  }) async {
    // 1. Caller-supplied ISRC — validate format first, no network needed
    final validated = normalizeIsrc(candidateIsrc);
    if (validated != null) {
      return IsrcResolutionResult.provided(validated);
    }

    if (song.trim().isEmpty || artist.trim().isEmpty) {
      return IsrcResolutionResult.none('Song title or artist is empty');
    }

    // 2. Cache lookup
    final key = '${song.trim().toLowerCase()}::${artist.trim().toLowerCase()}'
        '::$durationMs';
    final cached = _cache[key];
    if (cached != null) {
      if (cached.isEmpty) {
        return IsrcResolutionResult.none('Negative cache hit');
      }
      return IsrcResolutionResult.cached(cached);
    }

    // 3. Network lookup via Deezer catalog with timeout
    try {
      final resolved = await _resolveViaDeezer(song, artist, durationMs)
          .timeout(_timeout);
      _cache[key] = resolved ?? _negative;
      if (resolved != null) {
        return IsrcResolutionResult.catalog(resolved);
      }
      return IsrcResolutionResult.none('No matching catalog track with valid ISRC');
    } on TimeoutException {
      return IsrcResolutionResult.none('ISRC resolution timed out after ${_timeout.inSeconds}s');
    } catch (e) {
      return IsrcResolutionResult.none('ISRC resolution error: $e');
    }
  }

  /// Resolves ISRC for a [SongQuery]. If the query already has an ISRC,
  /// uses it directly without network call.
  Future<String?> resolveForQuery(SongQuery query) {
    return resolve(
      candidateIsrc: query.isrc,
      song: query.title,
      artist: query.artists.isNotEmpty ? query.artists.first : '',
      durationMs: query.durationMs,
    );
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
