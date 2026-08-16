import 'package:dio/dio.dart';

import '/services/spotify/track_normalizer.dart';

/// Thrown when LRCLIB rate-limits the request; carries the suggested wait.
class LrcLibRateLimited implements Exception {
  final Duration retryAfter;
  LrcLibRateLimited(this.retryAfter);
  @override
  String toString() => 'LRCLIB rate limit — retry in ${retryAfter.inSeconds}s';
}

/// Lyrics for one track as returned by LRCLIB.
class LrcLyrics {
  final int? id;
  final String? syncedLyrics;
  final String? plainLyrics;
  final bool instrumental;
  final String? trackName;
  final String? artistName;
  final String? albumName;
  final int? duration;

  const LrcLyrics({
    this.id,
    this.syncedLyrics,
    this.plainLyrics,
    this.instrumental = false,
    this.trackName,
    this.artistName,
    this.albumName,
    this.duration,
  });

  bool get hasSynced => syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;
  bool get hasPlain => plainLyrics != null && plainLyrics!.trim().isNotEmpty;

  factory LrcLyrics.fromJson(Map<String, dynamic> json) => LrcLyrics(
        id: (json['id'] as num?)?.toInt(),
        syncedLyrics: json['syncedLyrics'] as String?,
        plainLyrics: json['plainLyrics'] as String?,
        instrumental: json['instrumental'] as bool? ?? false,
        trackName: json['trackName'] as String?,
        artistName: json['artistName'] as String?,
        albumName: json['albumName'] as String?,
        duration: (json['duration'] as num?)?.toInt(),
      );
}

/// Parsed LRC line: timestamp in milliseconds + text.
class LrcLine {
  final int timestampMs;
  final String text;
  const LrcLine(this.timestampMs, this.text);
}

final RegExp _lrcTimestampRegExp =
    RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

/// Extracts [mm:ss.xx] timestamps from an LRC string.
///
/// Returns null when the text contains no parseable timestamps or the
/// timestamps are not monotonically ordered (out-of-order lines indicate a
/// corrupt source and are rejected).
List<LrcLine>? parseLrc(String lrc) {
  final lines = lrc.split('\n');
  final result = <LrcLine>[];
  var last = -1;
  var sawTimestamp = false;
  for (final raw in lines) {
    final text = raw.trim();
    if (text.isEmpty) continue;
    final match = _lrcTimestampRegExp.firstMatch(text);
    if (match == null) continue;
    sawTimestamp = true;
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final fraction = match.group(3);
    final ms = fraction == null
        ? 0
        : int.parse(fraction.padRight(3, '0').substring(0, 3));
    final ts = minutes * 60000 + seconds * 1000 + ms;
    if (ts < last) return null; // out of order — corrupt
    last = ts;
    final lyricText =
        text.substring(match.end).replaceAll(RegExp(r'^\s*[-–—:]\s*'), '');
    if (lyricText.isNotEmpty) {
      result.add(LrcLine(ts, lyricText));
    }
  }
  if (!sawTimestamp) return null;
  return result.isEmpty ? null : result;
}

/// True when the timestamps are plausible for the track duration: the last
/// timestamp must not exceed the duration by more than 30 seconds.
bool timestampsPlausible(List<LrcLine> lines, int durationMs) {
  if (durationMs <= 0) return true;
  final last = lines.last.timestampMs;
  return last <= durationMs + 30000;
}

/// Scores an LRCLIB search result against the desired metadata (0..1).
double scoreLrcCandidate({
  required String trackName,
  required List<String> artists,
  String? albumName,
  int? durationMs,
  required LrcLyrics candidate,
}) {
  final signals = <(double, double)>[
    (
      0.45,
      textSimilarity(
          normalizeTitleForComparison(trackName),
          normalizeTitleForComparison(candidate.trackName ?? '')),
    ),
    (
      0.35,
      textSimilarity(
          normalizeNameForComparison(artists.join(' ')),
          normalizeNameForComparison(candidate.artistName ?? '')),
    ),
  ];
  if (albumName != null && candidate.albumName != null) {
    signals.add((
      0.10,
      textSimilarity(
          normalizeNameForComparison(albumName),
          normalizeNameForComparison(candidate.albumName!)),
    ));
  }
  if (durationMs != null && durationMs > 0 && candidate.duration != null) {
    final diff = (durationMs - candidate.duration! * 1000).abs().toDouble();
    final sim = diff <= 5000
        ? 1.0
        : diff <= 15000
            ? 0.8
            : diff <= 30000
                ? 0.5
                : 0.1;
    signals.add((0.10, sim));
  }
  final total = signals.fold<double>(0, (s, e) => s + e.$1);
  final weighted = signals.fold<double>(0, (s, e) => s + e.$1 * e.$2);
  return weighted / total;
}

/// Minimal LRCLIB client used by batch imports.
///
/// LRCLIB is free and key-less; requests are identified with a proper
/// User-Agent. 429 responses surface [LrcLibRateLimited] so the caller can
/// honor Retry-After instead of hammering the endpoint.
class LrcLibClient {
  final Dio _dio;

  LrcLibClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://lrclib.net/api',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: {
                'User-Agent':
                    'HarmonyMusic/2.0 (https://github.com/anandnet/Harmony-Music)',
                'Accept': 'application/json',
              },
            ));

  /// Primary lookup with the full metadata (duration is important to
  /// LRCLIB matching). Returns null on 404 (no lyrics for this exact
  /// combination).
  Future<LrcLyrics?> fetchByMetadata({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationMs,
  }) async {
    try {
      final res = await _dio.get('/get', queryParameters: {
        'track_name': trackName,
        'artist_name': artistName,
        if (albumName != null) 'album_name': albumName,
        if (durationMs != null && durationMs > 0)
          'duration': (durationMs / 1000).round(),
      });
      if (res.statusCode == 204) return null;
      return LrcLyrics.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      if (e.response?.statusCode == 429) {
        throw LrcLibRateLimited(_retryAfter(e));
      }
      rethrow;
    }
  }

  /// Secondary search used when the exact lookup 404s.
  Future<List<LrcLyrics>> search({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationMs,
  }) async {
    try {
      final res = await _dio.get('/search', queryParameters: {
        'track_name': trackName,
        'artist_name': artistName,
        if (albumName != null) 'album_name': albumName,
      });
      final list = res.data as List? ?? const [];
      return list
          .whereType<Map>()
          .map((e) => LrcLyrics.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw LrcLibRateLimited(_retryAfter(e));
      }
      rethrow;
    }
  }

  Duration _retryAfter(DioException e) {
    final header = e.response?.headers.value('retry-after');
    final seconds = int.tryParse(header ?? '');
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds);
    }
    return const Duration(seconds: 30);
  }

  /// Validates a synced-LRC payload: parseable, monotonic timestamps and
  /// non-empty text. Returns the parsed lines or null.
  static List<LrcLine>? validateSyncedLyrics(String? synced,
      {int? durationMs}) {
    if (synced == null || synced.trim().isEmpty) return null;
    final lines = parseLrc(synced);
    if (lines == null) return null;
    if (durationMs != null && durationMs > 0) {
      if (!timestampsPlausible(lines, durationMs)) return null;
    }
    return lines;
  }
}
