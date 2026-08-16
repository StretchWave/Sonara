import '../../stream_service.dart' show Audio, Codec;
import '../audio_source_provider.dart';
import '../matching/search_terms.dart';
import '../matching/track_candidate.dart';
import '../matching/track_scorer.dart';
import '../race.dart';
import '../resolved_stream.dart';
import '../song_query.dart';
import 'qobuz_api.dart';

/// Qobuz provider — streams FLAC/MP3 through user-configured Kenny-style
/// resolver instances. No credentials live in the app.
class QobuzProvider extends AudioSourceProvider {
  QobuzProvider({
    required List<String> instances,
    this.country = 'US',
    this.qualityCode = 27,
    this.matchOverrides = const {},
    QobuzApi? api,
  })  : _api = api ?? QobuzApi(),
        instances = normalizeInstances(instances);

  static const String providerId = 'qobuz';

  /// Normalized resolver base URLs, tried in parallel (first success wins).
  final List<String> instances;

  final String country;

  /// Desired quality code; falls back down the ladder when unavailable.
  final int qualityCode;

  /// Remembered manual match corrections: `qobuz::mediaId` → trackId.
  final Map<String, String> matchOverrides;

  final QobuzApi _api;

  static const int _mp3Quality = 5;
  static const int _minFullLossyBitrateBps = 96000;
  static const int _minFullLosslessBitrateBps = 400000;
  static const int _minDurationForPreviewCheckMs = 75000;
  static const Duration _streamCacheDuration = Duration(minutes: 5);

  final Map<String, TrackCandidate> _trackCache = {};
  final Map<String, _CachedStream> _streamCache = {};

  @override
  String get id => providerId;

  /// Normalizes raw instance entries into absolute base URLs, deduped.
  static List<String> normalizeInstances(Iterable<String> raw) {
    final out = <String>[];
    for (final token in raw) {
      var candidate = token.trim();
      if (candidate.isEmpty) continue;
      if (!candidate.contains('://')) candidate = 'https://$candidate';
      final uri = Uri.tryParse(candidate);
      if (uri == null || !uri.hasAuthority || uri.host.isEmpty) continue;
      final host = uri.host.toLowerCase();
      if (!host.contains('.') && host != 'localhost') continue;
      final normalized =
          uri.toString().replaceAll(RegExp(r'/+$'), '');
      if (normalized.isNotEmpty && !out.contains(normalized)) {
        out.add(normalized);
      }
    }
    return out;
  }

  @override
  Future<ResolvedStream> resolve(SongQuery query) async {
    if (instances.isEmpty) {
      return const ResolvedStream(
        playable: false,
        statusMSG: 'Qobuz not configured',
      );
    }

    final track = await _matchTrack(query);
    if (track == null) {
      return ResolvedStream(
        playable: false,
        statusMSG: 'Qobuz match not found for ${query.title}',
      );
    }

    String? lastError;
    for (final quality in _qualityFallbackOrder(qualityCode)) {
      final stream = await _requestStream(track, quality, query);
      if (stream != null) return stream;
      lastError = 'Qobuz stream not found for ${query.title}';
    }
    return ResolvedStream(
      playable: false,
      statusMSG: lastError ?? 'Qobuz stream not found',
    );
  }

  Future<TrackCandidate?> _matchTrack(SongQuery query) async {
    final directTrackId = _toQobuzTrackId(query.mediaId);
    if (directTrackId != null) {
      return TrackCandidate(
        trackId: directTrackId,
        title: query.title,
        artists: query.artists,
        album: query.album,
        durationMs: query.durationMs,
      );
    }
    final overrideTrackId = matchOverrides['$providerId::${query.mediaId}'];
    if (overrideTrackId != null && overrideTrackId.isNotEmpty) {
      return TrackCandidate(
        trackId: overrideTrackId,
        title: query.title,
        artists: query.artists,
        album: query.album,
        durationMs: query.durationMs,
      );
    }
    final cached = _trackCache[query.mediaId];
    if (cached != null) return cached;
    final matched = await _findBestTrack(query);
    if (matched != null) _trackCache[query.mediaId] = matched;
    return matched;
  }

  Future<TrackCandidate?> _findBestTrack(SongQuery query) async {
    for (final term in buildSearchTerms(query)) {
      final best = await raceFirstNotNull(instances.map((base) async {
        final items = await _api.searchTracks(base, term, country);
        if (items.isEmpty) return null;
        return _pickBest(items, query);
      }).toList());
      if (best != null) return best;
    }
    return null;
  }

  TrackCandidate? _pickBest(
    List<Map<String, dynamic>> items,
    SongQuery query,
  ) {
    final candidates = <TrackCandidate>[];
    for (final item in items) {
      final candidate = _toCandidate(item);
      if (candidate != null) candidates.add(candidate);
    }
    return pickBestMatch(candidates, query);
  }

  @override
  Future<List<TrackCandidate>> searchCandidates(
    SongQuery query, {
    int limit = 10,
  }) async {
    if (instances.isEmpty) return const [];
    final seen = <String>{};
    final out = <TrackCandidate>[];
    for (final term in buildSearchTerms(query).take(2)) {
      final items = await raceFirstNotNull(instances.map((base) async {
        final found = await _api.searchTracks(base, term, country);
        return found.isEmpty ? null : found;
      }).toList());
      if (items == null) continue;
      for (final item in items) {
        final candidate = _toCandidate(item);
        if (candidate != null && seen.add(candidate.trackId)) {
          out.add(candidate);
        }
        if (out.length >= limit) return out;
      }
    }
    return out;
  }

  TrackCandidate? _toCandidate(Map<String, dynamic> item) {
    if (item['downloadable'] != true && item['streamable'] != true) {
      return null;
    }
    final id = item['id']?.toString();
    final title = item['title']?.toString();
    if (id == null || title == null) return null;
    final version = item['version']?.toString();
    final combinedTitle =
        (version == null || version.isEmpty) ? title : '$title $version';
    final album = item['album'];
    final duration = _parseInt(item['duration']);
    final hires = item['hires'] == true;
    return TrackCandidate(
      trackId: id,
      title: combinedTitle,
      artists: _artistNames(item),
      album: album is Map ? album['title']?.toString() : null,
      isrc: item['isrc']?.toString(),
      durationMs: duration == null ? null : duration * 1000,
      hires: hires,
      bitDepth: _parseInt(item['maximum_bit_depth']),
      samplingRateKhz: _parseDouble(item['maximum_sampling_rate']),
      qualityLabel: hires ? 'Hi-Res FLAC' : 'FLAC',
    );
  }

  Future<ResolvedStream?> _requestStream(
    TrackCandidate track,
    int quality,
    SongQuery query,
  ) async {
    final cacheKey = '${query.mediaId}::${track.trackId}::$quality::$country';
    final cached = _streamCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.stream;
    }
    final stream = await raceFirstNotNull(instances.map((base) async {
      try {
        final data = await _api.requestStream(base, track.trackId, quality);
        return await _buildStream(track, quality, data, query);
      } catch (_) {
        return null;
      }
    }).toList());
    if (stream != null) {
      _streamCache[cacheKey] = _CachedStream(
        stream,
        stream.expiresAt ?? DateTime.now().add(_streamCacheDuration),
      );
    }
    return stream;
  }

  Future<ResolvedStream?> _buildStream(
    TrackCandidate track,
    int quality,
    Map<String, dynamic> data,
    SongQuery query,
  ) async {
    final url = data['url'] as String;
    final formatId = _parseInt(data['format_id']) ?? quality;
    final mimeType = ((data['mime_type'] as String?) ??
            (formatId == _mp3Quality ? 'audio/mpeg' : 'audio/flac'))
        .toLowerCase();
    final bitDepth = _parseInt(data['bit_depth']);
    final samplingRateKhz = _parseDouble(data['sampling_rate']);
    final sampleRate = samplingRateKhz != null && samplingRateKhz > 0
        ? (samplingRateKhz * 1000).round()
        : null;
    final lossyBitrate = _parseInt(data['bitrate']) ?? _parseInt(data['bit_rate']);
    final averageBitrate = _parseInt(data['average_bitrate']);
    final isLossy = mimeType.contains('mpeg') ||
        mimeType.contains('mp3') ||
        mimeType.contains('aac') ||
        mimeType.contains('mp4');

    final durationMs = query.durationMs;
    int? contentLength;
    if (durationMs != null && durationMs >= _minDurationForPreviewCheckMs) {
      contentLength = await _api.fetchContentLength(url);
      if (contentLength != null && durationMs > 0) {
        final estimatedBitrate = (contentLength * 8 * 1000) / durationMs;
        final minimum =
            isLossy ? _minFullLossyBitrateBps : _minFullLosslessBitrateBps;
        if (estimatedBitrate < minimum) {
          // Likely a preview — reject so the caller tries the next quality.
          return null;
        }
      }
    }

    final hires = (bitDepth ?? 0) > 16 ||
        (samplingRateKhz ?? 0) > 44.1 ||
        formatId >= 7;
    final (label, codecs, codec, bitrate) = _formatInfo(
      mimeType,
      bitDepth,
      samplingRateKhz,
      hires,
      lossyBitrate,
      averageBitrate,
      contentLength,
      durationMs,
    );

    return ResolvedStream(
      playable: true,
      statusMSG: 'OK',
      label: label,
      mimeType: mimeType,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      expiresAt: _expiryFromUrl(url),
      audioFormats: [
        Audio(
          itag: quality,
          audioCodec: codec,
          bitrate: bitrate,
          duration: durationMs ?? 0,
          loudnessDb: 0,
          url: url,
          size: contentLength ?? 0,
          label: label,
          mimeType: mimeType,
          sampleRate: sampleRate,
          bitDepth: bitDepth,
        ),
      ],
    );
  }

  (String, String, Codec, int) _formatInfo(
    String mimeType,
    int? bitDepth,
    double? samplingRateKhz,
    bool hires,
    int? lossyBitrate,
    int? averageBitrate,
    int? contentLength,
    int? durationMs,
  ) {
    final normalizedLossy = _normalizeBitrate(lossyBitrate);
    if (mimeType.contains('mpeg') || mimeType.contains('mp3')) {
      return (
        'Qobuz MP3',
        'mp3',
        Codec.mp3,
        normalizedLossy > 0 ? normalizedLossy : 320000,
      );
    }
    if (mimeType.contains('aac') || mimeType.contains('mp4')) {
      return ('Qobuz AAC', 'mp4a.40.2', Codec.mp4a, normalizedLossy);
    }
    var lossless = _normalizeBitrate(averageBitrate);
    if (lossless <= 0 && contentLength != null && durationMs != null && durationMs > 0) {
      lossless = ((contentLength * 8 * 1000) / durationMs).round();
    }
    return (_flacLabel(hires, bitDepth, samplingRateKhz), 'flac', Codec.flac, lossless);
  }

  String _flacLabel(bool hires, int? bitDepth, double? samplingRateKhz) {
    final base = hires ? 'Qobuz Hi-Res FLAC' : 'Qobuz CD FLAC';
    if (bitDepth != null && samplingRateKhz != null) {
      final rate = samplingRateKhz % 1.0 == 0.0
          ? samplingRateKhz.toInt().toString()
          : samplingRateKhz.toString();
      return '$base $bitDepth-bit/$rate kHz';
    }
    return base;
  }

  @override
  void invalidate(String mediaId) {
    _trackCache.remove(mediaId);
    _streamCache.removeWhere((key, _) => key.startsWith('$mediaId::'));
  }

  static List<int> _qualityFallbackOrder(int qualityCode) {
    const ladder = [27, 7, 6, 5];
    final startIndex = ladder.indexOf(qualityCode);
    return startIndex >= 0 ? ladder.sublist(startIndex) : [qualityCode];
  }

  static List<String> _artistNames(Map<String, dynamic> item) {
    final names = <String>[];
    void addName(Object? name) {
      final value = name?.toString();
      if (value != null && value.isNotEmpty && !names.contains(value)) {
        names.add(value);
      }
    }

    final performer = item['performer'];
    if (performer is Map) addName(performer['name']);
    final album = item['album'];
    if (album is Map) {
      final artist = album['artist'];
      if (artist is Map) addName(artist['name']);
      final artists = album['artists'];
      if (artists is List) {
        for (final entry in artists) {
          if (entry is Map) addName(entry['name']);
        }
      }
    }
    return names;
  }

  static String? _toQobuzTrackId(String mediaId) {
    final trimmed = mediaId.trim();
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;
    final prefixed = RegExp(r'^qobuz:track:(\d+)$', caseSensitive: false)
        .firstMatch(trimmed);
    if (prefixed != null) return prefixed.group(1);
    return null;
  }

  static DateTime? _expiryFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final etsp = uri?.queryParameters['etsp'];
    final seconds = etsp == null ? null : int.tryParse(etsp);
    if (seconds != null && seconds > 0) {
      return DateTime.fromMillisecondsSinceEpoch(seconds * 1000 - 15000);
    }
    return null;
  }

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static double? _parseDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static int _normalizeBitrate(int? bitrate) {
    if (bitrate == null || bitrate <= 0) return 0;
    return bitrate < 10000 ? bitrate * 1000 : bitrate;
  }

}

class _CachedStream {
  _CachedStream(this.stream, this.expiresAt);

  final ResolvedStream stream;
  final DateTime expiresAt;
}
