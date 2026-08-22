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
import 'deezer_api.dart';

/// Deezer provider — streams FLAC/MP3 through user-configured resolver
/// endpoints.  No credentials live in the app.
///
/// Adapted from MetroFuse's `DeezerAudioProvider` (GPL-3.0, see repo
/// attribution).  Uses the public Deezer search API for catalog lookups
/// and community/self-hosted resolver instances for stream URLs.
class DeezerProvider extends AudioSourceProvider {
  DeezerProvider({
    List<String>? endpoints,
    this.quality = 'FLAC',
    this.matchOverrides = const {},
    DeezerApi? api,
  })  : _api = api ?? DeezerApi(),
        endpoints = normalizeEndpoints(endpoints ?? defaultEndpoints);

  static const String providerId = 'deezer';

  /// MetroFuse's shipped default resolver endpoints (used when the user has
  /// not configured their own).  Both are hosted by the community — no
  /// hosting needed by the user.
  static const List<String> defaultEndpoints = [
    'https://yesitworkssomehow-funny-deeza-api-and-yeah.hf.space/get_url',
    'https://dzmedia-metrofuse.onrender.com/get_url',
  ];

  /// Normalized resolver base URLs, tried in parallel (first success wins).
  final List<String> endpoints;

  /// Desired quality: FLAC, MP3_320, or MP3_128.
  final String quality;

  /// Remembered manual match corrections: `deezer::mediaId` → trackId.
  final Map<String, String> matchOverrides;

  final DeezerApi _api;

  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) '
      'Gecko/20100101 Firefox/140.0';

  static const List<String> _qualityLadder = [
    'FLAC',
    'MP3_320',
    'MP3_128',
  ];

  static const Duration _streamCacheDuration = Duration(minutes: 45);

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
    return out.isEmpty ? List.of(defaultEndpoints) : out;
  }

  @override
  Future<ResolvedStream> resolve(SongQuery query) async {
    if (endpoints.isEmpty) {
      return const ResolvedStream(
        playable: false,
        statusMSG: 'Deezer not configured',
      );
    }

    final track = await _matchTrack(query);
    if (track == null) {
      return ResolvedStream(
        playable: false,
        statusMSG: 'Deezer match not found for ${query.title}',
      );
    }

    String? lastError;
    for (final q in _qualityFallbackOrder(quality)) {
      final stream = await _requestStream(track, q, query);
      if (stream != null) return stream;
      lastError = 'Deezer stream not found for ${query.title}';
    }
    return ResolvedStream(
      playable: false,
      statusMSG: lastError ?? 'Deezer stream not found',
    );
  }

  Future<TrackCandidate?> _matchTrack(SongQuery query) async {
    final directTrackId = _toDeezerTrackId(query.mediaId);
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
    // Try ISRC first if available
    final isrc = query.isrc?.trim().toUpperCase();
    if (isrc != null &&
        isrc.length == 12 &&
        RegExp(r'^[A-Z]{2}[A-Z0-9]{10}$').hasMatch(isrc)) {
      final isrcResult = await _api.lookupIsrc(isrc);
      if (isrcResult != null) {
        final candidate = _toCandidate(isrcResult);
        if (candidate != null) {
          final score = scoreCandidate(candidate: candidate, query: query);
          if (score > rejectScore) return candidate;
        }
      }
    }

    for (final term in buildSearchTerms(query)) {
      final items = await _api.searchTracks(term, limit: 12);
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
      final items = await _api.searchTracks(term, limit: 8);
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
    final duration =
        item['duration'] is num ? (item['duration'] as num).toInt() : null;
    final isrc = item['isrc']?.toString();

    return TrackCandidate(
      trackId: id,
      title: title,
      artists: _artistNames(item),
      album: album is Map ? album['title']?.toString() : null,
      isrc: isrc,
      durationMs: duration == null ? null : duration * 1000,
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
        final data = await _requestResolverStream(base, track.trackId, quality);
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

  /// Sends a POST to the resolver endpoint to get a playable stream URL.
  Future<Map<String, dynamic>> _requestResolverStream(
    String baseUrl,
    String trackId,
    String quality,
  ) async {
    final resolverUrl = _normalizeResolverUrl(baseUrl);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse(resolverUrl);
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Accept', 'application/json');
      req.headers.set('User-Agent', _browserUserAgent);

      final body = jsonEncode({
        'formats': [quality],
        'ids': [int.tryParse(trackId) ?? trackId],
      });
      req.add(utf8.encode(body));

      final res = await req.close().timeout(const Duration(seconds: 15));
      final responseBody = await utf8.decoder.bind(res).join();

      if (res.statusCode != 200) {
        final snippet = responseBody.substring(0, responseBody.length.clamp(0, 200));
        throw Exception('Resolver HTTP ${res.statusCode}: $snippet');
      }

      final json = jsonDecode(responseBody);
      return json as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  String _normalizeResolverUrl(String base) {
    var url = base.trim();
    if (!url.contains('://')) url = 'https://$url';
    if (!url.endsWith('/get_url')) {
      url = url.replaceAll(RegExp(r'/+$'), '') + '/get_url';
    }
    return url;
  }

  Future<ResolvedStream?> _buildStream(
    TrackCandidate track,
    String quality,
    Map<String, dynamic> data,
  ) async {
    // Parse the resolver response
    final dataList = data['data'];
    if (dataList is List && dataList.isNotEmpty) {
      final first = dataList[0];
      if (first is Map<String, dynamic>) {
        final mediaList = first['media'];
        if (mediaList is List && mediaList.isNotEmpty) {
          final media = mediaList.firstWhere(
            (m) => m is Map && m['format']?.toString().toUpperCase() == quality,
            orElse: () => mediaList.first,
          );
          if (media is Map<String, dynamic>) {
            final sources = media['sources'];
            String? streamUrl;
            if (sources is List && sources.isNotEmpty) {
              final source = sources.lastOrNull ?? sources.first;
              if (source is Map) {
                streamUrl = source['url']?.toString();
              }
            }
            if (streamUrl == null || streamUrl.isEmpty) return null;

            // Check for preview
            if (media['assetPresentation']?.toString().toUpperCase() ==
                'PREVIEW') {
              return null;
            }

            final isLossless = quality == 'FLAC';
            final mimeType = isLossless ? 'audio/flac' : 'audio/mpeg';
            final label =
                isLossless ? 'Deezer FLAC' : 'Deezer $quality';
            final bitrate = isLossless ? 1411000 : (quality == 'MP3_320' ? 320000 : 128000);

            return ResolvedStream(
              playable: true,
              statusMSG: 'OK',
              label: label,
              mimeType: mimeType,
              sampleRate: isLossless ? 44100 : null,
              bitDepth: isLossless ? 16 : null,
              audioFormats: [
                Audio(
                  itag: _qualityLadder.indexOf(quality).clamp(0, 3),
                  audioCodec: isLossless ? Codec.flac : Codec.mp3,
                  bitrate: bitrate,
                  duration: track.durationMs ?? 0,
                  loudnessDb: 0,
                  url: streamUrl,
                  size: 0,
                  label: label,
                  mimeType: mimeType,
                  sampleRate: isLossless ? 44100 : null,
                  bitDepth: isLossless ? 16 : null,
                ),
              ],
            );
          }
        }
      }
    }

    // Try direct URL field (simpler resolver format)
    final url = data['url']?.toString();
    if (url != null && url.isNotEmpty) {
      final isLossless = quality == 'FLAC';
      final mimeType = isLossless ? 'audio/flac' : 'audio/mpeg';
      final label = isLossless ? 'Deezer FLAC' : 'Deezer $quality';
      final bitrate = isLossless ? 1411000 : (quality == 'MP3_320' ? 320000 : 128000);

      return ResolvedStream(
        playable: true,
        statusMSG: 'OK',
        label: label,
        mimeType: mimeType,
        sampleRate: isLossless ? 44100 : null,
        bitDepth: isLossless ? 16 : null,
        audioFormats: [
          Audio(
            itag: _qualityLadder.indexOf(quality).clamp(0, 3),
            audioCodec: isLossless ? Codec.flac : Codec.mp3,
            bitrate: bitrate,
            duration: track.durationMs ?? 0,
            loudnessDb: 0,
            url: url,
            size: 0,
            label: label,
            mimeType: mimeType,
            sampleRate: isLossless ? 44100 : null,
            bitDepth: isLossless ? 16 : null,
          ),
        ],
      );
    }

    return null;
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
    final contributors = item['contributors'];
    if (contributors is List) {
      for (final entry in contributors) {
        if (entry is Map) addName(entry['name']);
      }
    }
    return names;
  }

  static String? _toDeezerTrackId(String mediaId) {
    final trimmed = mediaId.trim();
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;
    final prefixed = RegExp(r'^deezer:track:(\d+)$', caseSensitive: false)
        .firstMatch(trimmed);
    if (prefixed != null) return prefixed.group(1);
    final urlMatch = RegExp(r'deezer\.com/(?:[a-z]{2}/)?track/(\d+)',
            caseSensitive: false)
        .firstMatch(trimmed);
    if (urlMatch != null) return urlMatch.group(1);
    return null;
  }
}

class _CachedStream {
  _CachedStream(this.stream, this.expiresAt);

  final ResolvedStream stream;
  final DateTime expiresAt;
}
