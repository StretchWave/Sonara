import 'dart:convert';
import 'dart:io';

import '../../stream_service.dart' show Audio, Codec;
import '../audio_source_provider.dart';
import '../matching/search_terms.dart';
import '../matching/track_candidate.dart';
import '../matching/track_scorer.dart';
import '../race.dart';
import '../resolved_stream.dart';
import '../song_query.dart';
import 'tidal_api.dart';

/// Tidal provider — streams Hi-Res FLAC / FLAC / AAC through
/// user-configured resolver endpoints plus Tidal's public search API.
/// No credentials live in the app.
class TidalProvider extends AudioSourceProvider {
  TidalProvider({
    required List<String> endpoints,
    this.quality = 'LOSSLESS',
    this.matchOverrides = const {},
    TidalApi? api,
  })  : _api = api ?? TidalApi(),
        endpoints = normalizeEndpoints(endpoints);

  static const String providerId = 'tidal';

  /// Normalized resolver base URLs, tried in parallel (first success wins).
  final List<String> endpoints;

  /// Desired quality; falls back down the ladder when unavailable.
  final String quality;

  /// Remembered manual match corrections: `tidal::mediaId` → trackId.
  final Map<String, String> matchOverrides;

  final TidalApi _api;

  static const List<String> _qualityLadder = [
    'HI_RES_LOSSLESS',
    'LOSSLESS',
    'HIGH',
    'LOW',
  ];
  static const Duration _streamCacheDuration = Duration(minutes: 5);

  final Map<String, TrackCandidate> _trackCache = {};
  final Map<String, _CachedStream> _streamCache = {};

  @override
  String get id => providerId;

  /// Normalizes raw endpoint entries into absolute base URLs, deduped.
  static List<String> normalizeEndpoints(Iterable<String> raw) {
    final out = <String>[];
    for (final token in raw) {
      var candidate = token.trim();
      if (candidate.isEmpty) continue;
      if (!candidate.contains('://')) candidate = 'https://$candidate';
      final uri = Uri.tryParse(candidate);
      if (uri == null || !uri.hasAuthority || uri.host.isEmpty) continue;
      final host = uri.host.toLowerCase();
      if (!host.contains('.') && host != 'localhost') continue;
      final normalized = uri.toString().replaceAll(RegExp(r'/+$'), '');
      if (normalized.isNotEmpty && !out.contains(normalized)) {
        out.add(normalized);
      }
    }
    return out;
  }

  @override
  Future<ResolvedStream> resolve(SongQuery query) async {
    if (endpoints.isEmpty) {
      return const ResolvedStream(
        playable: false,
        statusMSG: 'Tidal not configured',
      );
    }

    final track = await _matchTrack(query);
    if (track == null) {
      return ResolvedStream(
        playable: false,
        statusMSG: 'Tidal match not found for ${query.title}',
      );
    }

    String? lastError;
    for (final quality in _qualityFallbackOrder(this.quality)) {
      final stream = await _requestStream(track, quality, query);
      if (stream != null) return stream;
      lastError = 'Tidal stream not found for ${query.title}';
    }
    return ResolvedStream(
      playable: false,
      statusMSG: lastError ?? 'Tidal stream not found',
    );
  }

  Future<TrackCandidate?> _matchTrack(SongQuery query) async {
    final directTrackId = _toTidalTrackId(query.mediaId);
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
      final items = await _api.searchTracks(term);
      if (items.isEmpty) continue;
      final best = _pickBest(items, query);
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
    final seen = <String>{};
    final out = <TrackCandidate>[];
    for (final term in buildSearchTerms(query).take(2)) {
      final items = await _api.searchTracks(term);
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
    final id = item['id']?.toString();
    final title = item['title']?.toString();
    if (id == null || title == null) return null;
    final album = item['album'];
    final duration = _parseInt(item['duration']);
    final audioQuality = item['audioQuality']?.toString() ?? '';
    final hires = audioQuality.contains('LOSSLESS') ||
        audioQuality.contains('HI_RES');
    final qualityLabel = audioQuality.contains('HI_RES')
        ? 'Hi-Res FLAC'
        : audioQuality.contains('LOSSLESS')
            ? 'FLAC'
            : 'AAC';
    return TrackCandidate(
      trackId: id,
      title: title,
      artists: _artistNames(item),
      album: album is Map ? album['title']?.toString() : null,
      isrc: item['isrc']?.toString(),
      durationMs: duration == null ? null : duration * 1000,
      hires: hires,
      qualityLabel: qualityLabel,
    );
  }

  Future<ResolvedStream?> _requestStream(
    TrackCandidate track,
    String quality,
    SongQuery query,
  ) async {
    final cacheKey = '${query.mediaId}::${track.trackId}::$quality';
    final cached = _streamCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.stream;
    }
    final stream = await raceFirstNotNull(endpoints.map((base) async {
      try {
        final data = await _api.requestStream(base, track.trackId, quality);
        return await _buildStream(track, quality, data);
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
    String quality,
    Map<String, dynamic> data,
  ) async {
    if (data['assetPresentation']?.toString().toUpperCase() == 'PREVIEW') {
      // Resolver returned a 30s preview instead of the full track.
      return null;
    }

    final uri = await _playableManifestUri(track.trackId, quality, data);
    if (uri == null) return null;

    final audioQuality = data['audioQuality']?.toString() ?? quality;
    final isLossless =
        audioQuality.contains('LOSSLESS') || audioQuality.contains('HI_RES');
    final hires = audioQuality.contains('HI_RES') ||
        (data['bitDepth'] is int && (data['bitDepth'] as int) >= 24) ||
        (_sampleRateHz(data) ?? 0) > 48000;

    final mimeType = isLossless ? 'audio/flac' : 'audio/mp4';
    final label = isLossless
        ? (hires ? 'Tidal Hi-Res FLAC' : 'Tidal FLAC')
        : 'Tidal AAC';
    final bitrate = _normalizeBitrate(_parseInt(data['bitRate']));

    return ResolvedStream(
      playable: true,
      statusMSG: 'OK',
      label: label,
      mimeType: mimeType,
      sampleRate: _sampleRateHz(data),
      bitDepth: _parseInt(data['bitDepth']),
      audioFormats: [
        Audio(
          itag: _qualityLadder.indexOf(audioQuality).clamp(0, 3),
          audioCodec: isLossless ? Codec.flac : Codec.mp4a,
          bitrate: bitrate,
          duration: track.durationMs ?? 0,
          loudnessDb: 0,
          url: uri,
          size: 0,
          label: label,
          mimeType: mimeType,
          sampleRate: _sampleRateHz(data),
          bitDepth: _parseInt(data['bitDepth']),
        ),
      ],
    );
  }

  /// Turns a resolver's `manifest` payload into a playable URI.
  ///
  /// Supported shapes:
  /// - a direct http(s) manifest URL (DASH/HLS),
  /// - a base64 DASH MPD / HLS playlist (written to a temp file so players
  ///   can read it),
  /// - a base64 JSON progressive manifest with `urls` (best URL used).
  Future<String?> _playableManifestUri(
    String trackId,
    String quality,
    Map<String, dynamic> data,
  ) async {
    final manifest = data['manifest'] as String?;
    if (manifest == null || manifest.isEmpty) return null;
    if (manifest.startsWith('http://') || manifest.startsWith('https://')) {
      return manifest;
    }
    final mimeType =
        ((data['manifestMimeType'] as String?) ?? '').toLowerCase();
    String decoded;
    try {
      decoded = utf8.decode(base64Decode(base64.normalize(manifest)));
    } catch (_) {
      return null;
    }
    if (mimeType.contains('json')) {
      try {
        final json = jsonDecode(decoded);
        if (json is Map && json['urls'] is List) {
          final urls = (json['urls'] as List).whereType<String>().toList();
          if (urls.isNotEmpty) return urls.last;
        }
      } catch (_) {}
      return null;
    }
    final isDash = mimeType.contains('dash') || decoded.trimLeft().startsWith('<');
    final extension = isDash ? 'mpd' : 'm3u8';
    final dir = Directory.systemTemp;
    final file =
        File('${dir.path}${Platform.pathSeparator}tidal_${trackId}_$quality.$extension');
    try {
      await file.writeAsString(decoded);
      return file.uri.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  void invalidate(String mediaId) {
    _trackCache.remove(mediaId);
    _streamCache.removeWhere((key, _) => key.startsWith('$mediaId::'));
  }

  static List<String> _qualityFallbackOrder(String requested) {
    final startIndex = _qualityLadder.indexOf(requested);
    if (startIndex < 0) return [requested];
    return _qualityLadder.sublist(startIndex);
  }

  static List<String> _artistNames(Map<String, dynamic> item) {
    final names = <String>[];
    void addName(Object? name) {
      final value = name?.toString();
      if (value != null && value.isNotEmpty && !names.contains(value)) {
        names.add(value);
      }
    }

    final artist = item['artist'];
    if (artist is Map) addName(artist['name']);
    final artists = item['artists'];
    if (artists is List) {
      for (final entry in artists) {
        if (entry is Map) addName(entry['name']);
      }
    }
    return names;
  }

  static String? _toTidalTrackId(String mediaId) {
    final trimmed = mediaId.trim();
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;
    final prefixed = RegExp(r'^tidal:track:(\d+)$', caseSensitive: false)
        .firstMatch(trimmed);
    if (prefixed != null) return prefixed.group(1);
    return null;
  }

  static int? _sampleRateHz(Map<String, dynamic> data) {
    final value = data['sampleRate'];
    if (value is num) {
      return value > 1000 ? value.round() : (value * 1000).round();
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed == null) return null;
      return parsed > 1000 ? parsed.round() : (parsed * 1000).round();
    }
    return null;
  }

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
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
