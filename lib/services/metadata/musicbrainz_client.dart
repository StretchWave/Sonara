import 'package:dio/dio.dart';

import '/services/spotify/track_normalizer.dart';

/// Raised when MusicBrainz rate-limits (503 with Retry-After, or 429).
class MusicBrainzRateLimited implements Exception {
  final Duration retryAfter;
  MusicBrainzRateLimited(this.retryAfter);
  @override
  String toString() => 'MusicBrainz rate limit — retry in ${retryAfter.inSeconds}s';
}

/// A recording candidate found via the MusicBrainz search API.
class MusicBrainzRecording {
  final String mbid;
  final String title;
  final List<String> artists;

  /// Recording length in milliseconds (may be unknown).
  final int? lengthMs;

  /// International Standard Recording Codes for this recording.
  final List<String> isrcs;

  /// Earliest release date found among the recording's releases.
  final String? releaseDate;

  const MusicBrainzRecording({
    required this.mbid,
    required this.title,
    required this.artists,
    this.lengthMs,
    this.isrcs = const [],
    this.releaseDate,
  });
}

/// MusicBrainz is a *music identity* resolver — it identifies recordings and
/// exposes ISRCs — not a Spotify playlist scraper. It is used AFTER track
/// metadata has been acquired, to enrich tracks that lack an ISRC so the
/// matcher can use its strongest signal.
class MusicBrainzClient {
  final Dio _dio;

  MusicBrainzClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://musicbrainz.org/ws/2',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: {
                'User-Agent':
                    'Sonara/2.0 (https://github.com/anandnet/Harmony-Music)',
                'Accept': 'application/json',
              },
            ));

  /// Searches recordings by title + artist (+ album), scores the candidates
  /// on title/artist/duration and returns the best one that is sufficiently
  /// confident. Returns null when nothing matches well enough.
  Future<MusicBrainzRecording?> findRecording({
    required String title,
    required String artist,
    String? album,
    int? durationMs,
  }) async {
    final parts = <String>[
      'recording:"${_escapeQuery(title)}"',
      'artist:"${_escapeQuery(artist)}"',
      if (album != null && album.isNotEmpty)
        'release:"${_escapeQuery(album)}"',
    ];
    try {
      final res = await _dio.get('/recording/', queryParameters: {
        'query': parts.join(' AND '),
        'fmt': 'json',
        'limit': 10,
      });
      final list = ((res.data as Map?)?['recordings'] as List?) ?? const [];
      final candidates = list
          .whereType<Map>()
          .map(_parseRecording)
          .where((r) => r != null)
          .cast<MusicBrainzRecording>()
          .toList();
      return _pickBest(candidates, title, artist, durationMs);
    } on DioException catch (e) {
      if (e.response?.statusCode == 429 || e.response?.statusCode == 503) {
        throw MusicBrainzRateLimited(_retryAfter(e));
      }
      rethrow;
    }
  }

  String _escapeQuery(String s) =>
      s.replaceAll('"', '\\"').replaceAll('(', '').replaceAll(')', '');

  MusicBrainzRecording? _parseRecording(Map raw) {
    final isrcs = (raw['isrcs'] as List?)
            ?.whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    final artists = ((raw['artist-credit'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => (e['name'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toList();

    // Earliest release date across releases.
    String? releaseDate;
    final releases = (raw['releases'] as List?) ?? const [];
    for (final release in releases.whereType<Map>()) {
      final date = release['date'] as String?;
      if (date == null || date.isEmpty) continue;
      if (releaseDate == null || date.compareTo(releaseDate) < 0) {
        releaseDate = date;
      }
    }

    return MusicBrainzRecording(
      mbid: (raw['id'] as String?) ?? '',
      title: (raw['title'] as String?) ?? '',
      artists: artists,
      lengthMs: (raw['length'] as num?)?.toInt(),
      isrcs: isrcs,
      releaseDate: releaseDate,
    );
  }

  /// Weights: title 0.6, artist 0.25, duration 0.15. Candidates whose title
  /// does not clearly match are rejected so we never attach a wrong ISRC.
  MusicBrainzRecording? _pickBest(
      List<MusicBrainzRecording> candidates,
      String title,
      String artist,
      int? durationMs) {
    final normTitle = normalizeTitleForComparison(title);
    final normArtist = normalizeNameForComparison(artist);
    MusicBrainzRecording? best;
    var bestScore = 0.0;
    for (final c in candidates) {
      final titleSim = textSimilarity(
          normTitle, normalizeTitleForComparison(c.title));
      if (titleSim < 0.6) continue; // wrong recording — never attach its ISRC
      final artistSim = textSimilarity(normArtist,
          normalizeNameForComparison(c.artists.join(' ')));
      var durationSim = 1.0;
      if (durationMs != null && durationMs > 0 && c.lengthMs != null) {
        final diff = (durationMs - c.lengthMs!).abs();
        durationSim = diff <= 5000
            ? 1.0
            : diff <= 15000
                ? 0.7
                : diff <= 30000
                    ? 0.4
                    : 0.1;
      }
      final score =
          titleSim * 0.6 + artistSim * 0.25 + durationSim * 0.15;
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  Duration _retryAfter(DioException e) {
    final header = e.response?.headers.value('retry-after');
    final seconds = int.tryParse(header ?? '');
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds);
    }
    return const Duration(seconds: 5);
  }
}
