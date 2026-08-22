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

/// Amazon Music provider — streams FLAC/AAC through user-configured
/// resolver endpoints.  No credentials live in the app.
///
/// Adapted from MetroFuse's `AmazonAudioProvider` (GPL-3.0, see repo
/// attribution).  Uses the Amazon Music public web API for search
/// lookups and community/self-hosted resolver instances for stream URLs.
class AmazonProvider extends AudioSourceProvider {
  AmazonProvider({
    List<String>? endpoints,
    this.quality = 'HI_RES',
    this.matchOverrides = const {},
  }) : endpoints = normalizeEndpoints(endpoints ?? defaultEndpoints);

  static const String providerId = 'amazon';

  /// MetroFuse's shipped default resolver endpoint (used when the user has
  /// not configured their own).  Hosted by the community — no hosting needed.
  static const List<String> defaultEndpoints = [
    'https://t2tunes.site/api/amazon-music/media-from-asin',
  ];

  /// Normalized resolver base URLs, tried in parallel (first success wins).
  final List<String> endpoints;

  /// Desired quality: HI_RES, LOSSLESS, or HIGH.
  final String quality;

  /// Remembered manual match corrections: `amazon::mediaId` → asin.
  final Map<String, String> matchOverrides;

  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36';

  static const String _searchApiUrl =
      'https://na.web.skill.music.a2z.com/api/showSearch';
  static const String _musicBaseUrl = 'https://music.amazon.com';

  static const List<String> _qualityLadder = ['HI_RES', 'LOSSLESS', 'HIGH'];

  static const Duration _streamCacheDuration = Duration(minutes: 30);

  final Map<String, TrackCandidate> _trackCache = {};
  final Map<String, _CachedStream> _streamCache = {};

  // Session state for Amazon web API
  String? _deviceId;
  String? _sessionId;
  String _csrfToken = '';
  String _csrfTs = '';
  String _csrfRnd = '';
  String _appVersion = '1.0.10905.0';
  bool _isInitialized = false;
  DateTime? _sessionFetchedAt;

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
        statusMSG: 'Amazon Music not configured',
      );
    }

    final track = await _matchTrack(query);
    if (track == null) {
      return ResolvedStream(
        playable: false,
        statusMSG: 'Amazon Music match not found for ${query.title}',
      );
    }

    String? lastError;
    for (final q in _qualityFallbackOrder(quality)) {
      final stream = await _requestStream(track, q, query);
      if (stream != null) return stream;
      lastError = 'Amazon Music stream not found for ${query.title}';
    }
    return ResolvedStream(
      playable: false,
      statusMSG: lastError ?? 'Amazon Music stream not found',
    );
  }

  Future<TrackCandidate?> _matchTrack(SongQuery query) async {
    final directAsin = _toAmazonAsin(query.mediaId);
    if (directAsin != null) {
      return TrackCandidate(
        trackId: directAsin,
        title: query.title,
        artists: query.artists,
        album: query.album,
        durationMs: query.durationMs,
      );
    }
    final overrideAsin = matchOverrides['$providerId::${query.mediaId}'];
    if (overrideAsin != null && overrideAsin.isNotEmpty) {
      return TrackCandidate(
        trackId: overrideAsin,
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
    // Search using Amazon's web search API
    final terms = buildSearchTerms(query);
    for (final term in terms) {
      final items = await _searchTracks(term);
      if (items.isEmpty) continue;
      final best = _pickBest(items, query);
      if (best != null) return best;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _searchTracks(String term) async {
    _ensureSession();

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final pageUrl = '$_musicBaseUrl/search/${Uri.encodeComponent(term)}';
        final headers = _buildHeaders(pageUrl);

        final bodyObj = {
          'filter': jsonEncode({'IsLibrary': ['false']}),
          'keyword': jsonEncode({
            'interface':
                'Web.TemplatesInterface.v1_0.Touch.SearchTemplateInterface.SearchKeywordClientInformation',
            'keyword': term,
          }),
          'suggestedKeyword': term,
          'userHash': jsonEncode({'level': 'LIBRARY_MEMBER'}),
          'headers': jsonEncode(headers),
        };

        final req = await client.postUrl(Uri.parse(_searchApiUrl));
        req.headers.set('User-Agent', _browserUserAgent);
        req.headers.set('Accept', '*/*');
        req.headers.set('Origin', _musicBaseUrl);
        req.headers.set('Referer', pageUrl);
        req.headers.set('Content-Type', 'text/plain;charset=UTF-8');
        headers.forEach((k, v) => req.headers.set(k, v));

        req.add(utf8.encode(jsonEncode(bodyObj)));
        final res = await req.close().timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) return const [];

        final body = await utf8.decoder.bind(res).join();
        return _parseSearchResults(body);
      } finally {
        client.close();
      }
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, dynamic>> _parseSearchResults(String responseBody) {
    try {
      final root = jsonDecode(responseBody);
      if (root is! Map<String, dynamic>) return const [];

      final results = <Map<String, dynamic>>[];

      // Walk the response tree looking for track items
      _walkForTracks(root, results, depth: 0);
      return results;
    } catch (_) {
      return const [];
    }
  }

  void _walkForTracks(
    dynamic element,
    List<Map<String, dynamic>> results, {
    int depth = 0,
  }) {
    if (depth > 15 || results.length >= 20) return;

    if (element is Map<String, dynamic>) {
      // Check if this is a track item
      final asin = element['asin']?.toString();
      final kind = element['kind']?.toString();
      if (asin != null &&
          asin.length == 10 &&
          (kind == null || kind == 'track')) {
        final title = element['title']?.toString();
        if (title != null && title.isNotEmpty) {
          final artists = <String>[];
          final artistsArr = element['artists'];
          if (artistsArr is List) {
            for (final a in artistsArr) {
              if (a is Map) {
                final name = a['name']?.toString();
                if (name != null && name.isNotEmpty) artists.add(name);
              }
            }
          }
          results.add({
            'asin': asin,
            'title': title,
            'artists': artists,
            'album': element['album']?.toString(),
            'durationMs': element['durationMs'],
          });
          return;
        }
      }

      // Recurse into children
      for (final value in element.values) {
        if (value is Map || value is List) {
          _walkForTracks(value, results, depth: depth + 1);
        }
      }
    } else if (element is List) {
      for (final item in element) {
        if (item is Map || item is List) {
          _walkForTracks(item, results, depth: depth + 1);
        }
      }
    }
  }

  TrackCandidate? _pickBest(
    List<Map<String, dynamic>> items,
    SongQuery query,
  ) {
    final candidates = <TrackCandidate>[];
    for (final item in items) {
      final asin = item['asin']?.toString();
      final title = item['title']?.toString();
      if (asin == null || title == null) continue;

      final artists = <String>[];
      final artistsArr = item['artists'];
      if (artistsArr is List) {
        for (final a in artistsArr) {
          if (a is Map) {
            final name = a['name']?.toString();
            if (name != null && name.isNotEmpty) artists.add(name);
          }
        }
      }

      candidates.add(TrackCandidate(
        trackId: asin,
        title: title,
        artists: artists,
        album: item['album']?.toString(),
        durationMs: item['durationMs'] is int ? item['durationMs'] as int : null,
      ));
    }
    return pickBestMatch(candidates, query);
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
        final data = await _resolveAsin(base, track.trackId, quality);
        return _buildStream(track, quality, data);
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

  Future<Map<String, dynamic>> _resolveAsin(
    String baseUrl,
    String asin,
    String quality,
  ) async {
    final codec = quality == 'HI_RES' ? 'flac' : 'flac';
    final url = Uri.parse(baseUrl).replace(queryParameters: {
      'asin': asin,
      'country': 'US',
      'codec': codec,
    });

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(url);
      req.headers.set('User-Agent', _browserUserAgent);
      req.headers.set('Accept', 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        throw Exception('Resolution failed with HTTP ${res.statusCode}');
      }
      final body = await utf8.decoder.bind(res).join();

      // Try parsing as JSON array first, then as JSON object
      try {
        final json = jsonDecode(body);
        if (json is List) {
          return json.isNotEmpty ? json[0] as Map<String, dynamic> : {};
        }
        return json as Map<String, dynamic>;
      } catch (_) {
        return {};
      }
    } finally {
      client.close();
    }
  }

  ResolvedStream? _buildStream(
    TrackCandidate track,
    String quality,
    Map<String, dynamic> data,
  ) {
    // Look for stream URL in various response formats
    String? streamUrl;
    streamUrl ??= data['streamUrl']?.toString();
    streamUrl ??= data['url']?.toString();

    final streamInfo = data['streamInfo'];
    if (streamInfo is Map) {
      streamUrl ??= streamInfo['streamUrl']?.toString();
      streamUrl ??= streamInfo['url']?.toString();
    }

    final dataObj = data['data'];
    if (dataObj is Map) {
      streamUrl ??= dataObj['streamUrl']?.toString();
      streamUrl ??= dataObj['url']?.toString();
    }

    if (streamUrl == null || streamUrl.isEmpty) return null;

    final isHiRes = quality == 'HI_RES';
    final mimeType = 'audio/mp4';
    final label = isHiRes ? 'Amazon Music Hi-Res' : 'Amazon Music';
    final bitrate = isHiRes ? 0 : 256000; // 0 for lossless means unknown

    return ResolvedStream(
      playable: true,
      statusMSG: 'OK',
      label: label,
      mimeType: mimeType,
      sampleRate: isHiRes ? 48000 : 44100,
      bitDepth: isHiRes ? 24 : 16,
      audioFormats: [
        Audio(
          itag: _qualityLadder.indexOf(quality).clamp(0, 2),
          audioCodec: Codec.flac,
          bitrate: bitrate,
          duration: track.durationMs ?? 0,
          loudnessDb: 0,
          url: streamUrl,
          size: 0,
          label: label,
          mimeType: mimeType,
          sampleRate: isHiRes ? 48000 : 44100,
          bitDepth: isHiRes ? 24 : 16,
        ),
      ],
    );
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

  static String? _toAmazonAsin(String mediaId) {
    final trimmed = mediaId.trim();
    if (RegExp(r'^[A-Z0-9]{10}$').hasMatch(trimmed)) return trimmed;
    final prefixed = RegExp(r'^amazon:track:([A-Z0-9]{10})$', caseSensitive: false)
        .firstMatch(trimmed);
    if (prefixed != null) return prefixed.group(1);
    return null;
  }

  void _ensureSession() {
    if (_isInitialized &&
        _sessionFetchedAt != null &&
        DateTime.now().difference(_sessionFetchedAt!) <
            const Duration(minutes: 30)) {
      return;
    }

    // Generate fallback session data
    _deviceId = (DateTime.now().millisecondsSinceEpoch % 10000000000000000)
        .toString();
    _sessionId =
        '${DateTime.now().millisecondsSinceEpoch % 999}-${DateTime.now().millisecondsSinceEpoch % 9999999}-${DateTime.now().millisecondsSinceEpoch % 9999999}';
    _csrfTs = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    _csrfRnd = (DateTime.now().millisecondsSinceEpoch % 2000000000).toString();
    _isInitialized = true;
    _sessionFetchedAt = DateTime.now();

    // Try to fetch real session from Amazon
    _fetchRealSession();
  }

  Future<void> _fetchRealSession() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.getUrl(Uri.parse('$_musicBaseUrl/config.json'));
        req.headers.set('User-Agent', _browserUserAgent);
        req.headers.set('Referer', _musicBaseUrl);
        final res = await req.close().timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final body = await utf8.decoder.bind(res).join();
          final json = jsonDecode(body) as Map<String, dynamic>;
          _deviceId = json['deviceId']?.toString() ?? _deviceId;
          _sessionId = json['sessionId']?.toString() ?? _sessionId;
          _appVersion = json['version']?.toString() ?? _appVersion;

          final csrf = json['csrf'];
          if (csrf is Map) {
            _csrfToken = csrf['token']?.toString() ?? '';
            _csrfTs = csrf['ts']?.toString() ?? _csrfTs;
            _csrfRnd = csrf['rnd']?.toString() ?? _csrfRnd;
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // Use fallback session
    }
  }

  Map<String, String> _buildHeaders(String pageUrl) {
    final requestId = _generateUuid();
    return {
      'x-amzn-authentication': jsonEncode({
        'interface':
            'ClientAuthenticationInterface.v1_0.ClientTokenElement',
        'accessToken': '',
      }),
      'x-amzn-device-model': 'WEBPLAYER',
      'x-amzn-device-id': _deviceId ?? '',
      'x-amzn-session-id': _sessionId ?? '',
      'x-amzn-device-family': 'WebPlayer',
      'x-amzn-device-width': '1920',
      'x-amzn-device-height': '1080',
      'x-amzn-device-request-id': requestId,
      'x-amzn-request-id': requestId,
      'x-amzn-device-language': 'en_US',
      'x-amzn-application-version': _appVersion,
      'x-amzn-csrf': jsonEncode({
        'interface':
            'CSRFInterface.v1_0.CSRFHeaderElement',
        'token': _csrfToken,
        'timestamp': _csrfTs,
        'rndNonce': _csrfRnd,
      }),
      'x-amzn-music-domain': 'music.amazon.com',
      'x-amzn-page-url': pageUrl,
      'x-amzn-timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      'x-amzn-os-version': '1.0',
      'x-amzn-device-type-id': 'A1PY8Q7986S686',
      'x-amzn-hardware-device-type-id': 'A1PY8Q7986S686',
      'x-amzn-currency-of-preference': 'USD',
    };
  }

  String _generateUuid() {
    final rng = DateTime.now().millisecondsSinceEpoch;
    return '${rng.toRadixString(16)}-${(rng * 7).toRadixString(16)}-${(rng * 13).toRadixString(16)}-${(rng * 23).toRadixString(16)}';
  }
}

class _CachedStream {
  _CachedStream(this.stream, this.expiresAt);

  final ResolvedStream stream;
  final DateTime expiresAt;
}
