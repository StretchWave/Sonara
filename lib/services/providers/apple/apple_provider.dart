import 'dart:convert';
import 'dart:io';

import '../../stream_service.dart' show Audio, Codec;
import '../audio_source_provider.dart';
import '../matching/track_candidate.dart';
import '../matching/track_scorer.dart';
import '../resolved_stream.dart';
import '../song_query.dart';

/// Apple Music provider — streams AAC/ALAC through MetroFuse's hosted
/// resolver endpoints.  No credentials live in the app.
///
/// Adapted from MetroFuse's `AppleAudioProvider` + `AppleMusicCanvasProvider`
/// (GPL-3.0, see repo attribution).  The pipeline:
///   1. fetch a short-lived JWT from a public hosted token service,
///   2. look up the Apple Music song URL via the AMP catalog API (ISRC first,
///      text search fallback),
///   3. ask a hosted gamdl resolver to transcode/stream that URL
///      (`?url=<appleUrl>&codec=<codec>`), which returns the audio directly.
class AppleProvider extends AudioSourceProvider {
  AppleProvider({
    List<String>? endpoints,
    this.quality = 'AAC_WEB',
    this.matchOverrides = const {},
  }) : endpoints = normalizeEndpoints(endpoints ?? defaultEndpoints);

  static const String providerId = 'apple';

  /// MetroFuse's hosted gamdl stream resolver (no hosting needed by the user).
  static const List<String> defaultEndpoints = [
    'https://yesitworkssomehow-funi-lyric-api.hf.space/stream',
  ];

  /// MetroFuse's hosted Apple Music JWT token service.
  static const String defaultTokenUrl =
      'https://yesitworkssomehow-funny-deeza-api-and-yeah.hf.space/apple/token';

  static const String _ampBase = 'https://amp-api.music.apple.com';
  static const String _storefront = 'us';

  /// Normalized resolver base URLs, tried in order (first success wins).
  final List<String> endpoints;

  /// Desired quality; falls back down the ladder when unavailable.
  final String quality;

  /// Remembered manual match corrections: `apple::mediaId` → isrc.
  final Map<String, String> matchOverrides;

  static const String _browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/135.0.0.0 Mobile Safari/537.36';

  /// MetroFuse's fallback chain (gamdl SongCodec names).
  static const List<String> _qualityLadder = [
    'atmos',
    'ac3',
    'aac',
    'aac-web',
  ];

  static const Duration _tokenTtl = Duration(minutes: 30);
  static const Duration _streamCacheDuration = Duration(minutes: 5);

  static String? _token;
  static DateTime? _tokenFetchedAt;

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
    final token = await _getToken();
    if (token == null) {
      return const ResolvedStream(
        playable: false,
        statusMSG: 'Apple Music token service unreachable',
      );
    }

    final appleUrl = await _findAppleUrl(query, token);
    if (appleUrl == null) {
      return ResolvedStream(
        playable: false,
        statusMSG: 'Apple Music match not found for ${query.title}',
      );
    }

    String? lastError;
    for (final codec in _qualityFallbackOrder(quality)) {
      final stream = await _requestStream(appleUrl, codec, query);
      if (stream != null) return stream;
      lastError = 'Apple Music stream not found for ${query.title}';
    }
    return ResolvedStream(
      playable: false,
      statusMSG: lastError ?? 'Apple Music stream not found',
    );
  }

  /// Resolves the Apple Music song URL for [query] via the AMP catalog API.
  Future<String?> _findAppleUrl(SongQuery query, String token) async {
    final isrc = query.isrc?.trim().toUpperCase();
    if (isrc != null &&
        isrc.length == 12 &&
        RegExp(r'^[A-Z]{2}[A-Z0-9]{10}$').hasMatch(isrc)) {
      final byIsrc = await _ampSearchByIsrc(isrc, token);
      if (byIsrc != null) return byIsrc;
    }
    return _ampSearchByText(query, token);
  }

  Future<String?> _getToken() async {
    final now = DateTime.now();
    if (_token != null &&
        _tokenFetchedAt != null &&
        now.difference(_tokenFetchedAt!) < _tokenTtl) {
      return _token;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(defaultTokenUrl));
      req.headers.set('User-Agent', _browserUserAgent);
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) return _token;
      final body = await utf8.decoder.bind(res).join();
      final json = jsonDecode(body);
      final token = json is Map ? json['token']?.toString() : null;
      if (token != null && token.isNotEmpty) {
        _token = token;
        _tokenFetchedAt = now;
      }
      return _token;
    } catch (_) {
      return _token;
    } finally {
      client.close();
    }
  }

  Future<String?> _ampSearchByIsrc(String isrc, String token) async {
    final uri = Uri.parse('$_ampBase/v1/catalog/$_storefront/songs')
        .replace(queryParameters: {'filter[isrc]': isrc});
    try {
      final json = await _ampGet(uri, token);
      final data = json['data'];
      if (data is List && data.isNotEmpty) {
        for (final item in data) {
          if (item is Map) {
            final attributes = item['attributes'];
            if (attributes is Map) {
              final url = attributes['url']?.toString();
              if (url != null && url.isNotEmpty) return url;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _ampSearchByText(SongQuery query, String token) async {
    final term = [
      query.title,
      query.artists.firstOrNull,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    if (term.isEmpty) return null;
    final uri = Uri.parse('$_ampBase/v1/catalog/$_storefront/search')
        .replace(queryParameters: {
      'term': term,
      'types': 'songs',
      'limit': '8',
    });
    try {
      final json = await _ampGet(uri, token);
      final results = json['results'];
      final songs = results is Map ? results['songs'] : null;
      final data = songs is Map ? songs['data'] : null;
      if (data is! List || data.isEmpty) return null;

      final candidates = <TrackCandidate>[];
      for (final item in data) {
        if (item is! Map) continue;
        final attributes = item['attributes'];
        if (attributes is! Map) continue;
        final url = attributes['url']?.toString();
        final title = attributes['name']?.toString();
        if (url == null || url.isEmpty || title == null) continue;
        final artistName = attributes['artistName']?.toString();
        final durationMs =
            attributes['durationInMillis'] is num
                ? (attributes['durationInMillis'] as num).toInt()
                : null;
        candidates.add(TrackCandidate(
          trackId: url,
          title: title,
          artists: artistName == null ? const [] : [artistName],
          isrc: attributes['isrc']?.toString(),
          durationMs: durationMs,
        ));
      }
      final best = pickBestMatch(candidates, query);
      return best?.trackId;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _ampGet(Uri uri, String token) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(uri);
      req.headers.set('Authorization', 'Bearer $token');
      req.headers.set('Origin', 'https://music.apple.com');
      req.headers.set('Referer', 'https://music.apple.com/');
      req.headers.set('User-Agent', _browserUserAgent);
      req.headers.set('Accept', 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw HttpException('AMP HTTP ${res.statusCode}');
      }
      final body = await utf8.decoder.bind(res).join();
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('AMP returned no JSON object');
      }
      return json;
    } finally {
      client.close();
    }
  }

  /// Asks a gamdl resolver to stream [appleUrl] at [codec].  The resolver
  /// serves the audio directly, so the playable URL is the resolver URL
  /// itself (mirrors MetroFuse).  The request is only used to confirm the
  /// resolver answers; the body is not read here.
  Future<ResolvedStream?> _requestStream(
    String appleUrl,
    String codec,
    SongQuery query,
  ) async {
    final cacheKey = '${query.mediaId}::$codec';
    final cached = _streamCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.stream;
    }

    for (final base in endpoints) {
      try {
        final uri = Uri.parse(base).replace(queryParameters: {
          'url': appleUrl,
          'codec': codec,
        });
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 12);
        try {
          final req = await client.getUrl(uri);
          req.headers.set('User-Agent', _browserUserAgent);
          final res = await req.close().timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) continue;
          // Close without reading the body — the player will do the real
          // request against this same URL.
          await res.drain<void>().catchError((_) {});
          final isLossless = codec == 'alac';
          final label = 'Apple Music ${codec.toUpperCase()}';
          final resolved = ResolvedStream(
            playable: true,
            statusMSG: 'OK',
            label: label,
            mimeType: 'audio/mp4',
            audioFormats: [
              Audio(
                itag: _qualityLadder.indexOf(codec).clamp(0, 3),
                audioCodec: isLossless ? Codec.flac : Codec.mp4a,
                bitrate: _bitrateFor(codec),
                duration: query.durationMs ?? 0,
                loudnessDb: 0,
                url: uri.toString(),
                size: 0,
                label: label,
                mimeType: 'audio/mp4',
              ),
            ],
          );
          _streamCache[cacheKey] = _CachedStream(
            resolved,
            DateTime.now().add(_streamCacheDuration),
          );
          return resolved;
        } finally {
          client.close();
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  @override
  Future<List<TrackCandidate>> searchCandidates(
    SongQuery query, {
    int limit = 10,
  }) async {
    final token = await _getToken();
    if (token == null) return const [];
    final term = [
      query.title,
      query.artists.firstOrNull,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    if (term.isEmpty) return const [];
    final uri = Uri.parse('$_ampBase/v1/catalog/$_storefront/search')
        .replace(queryParameters: {
      'term': term,
      'types': 'songs',
      'limit': limit.toString(),
    });
    try {
      final json = await _ampGet(uri, token);
      final results = json['results'];
      final songs = results is Map ? results['songs'] : null;
      final data = songs is Map ? songs['data'] : null;
      if (data is! List) return const [];
      final out = <TrackCandidate>[];
      for (final item in data) {
        if (item is! Map) continue;
        final attributes = item['attributes'];
        if (attributes is! Map) continue;
        final url = attributes['url']?.toString();
        final title = attributes['name']?.toString();
        if (url == null || url.isEmpty || title == null) continue;
        final durationMs =
            attributes['durationInMillis'] is num
                ? (attributes['durationInMillis'] as num).toInt()
                : null;
        out.add(TrackCandidate(
          trackId: url,
          title: title,
          artists: [
            if (attributes['artistName']?.toString().isNotEmpty ?? false)
              attributes['artistName']!.toString(),
          ],
          isrc: attributes['isrc']?.toString(),
          durationMs: durationMs,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  void invalidate(String mediaId) {
    _trackCache.remove(mediaId);
    _streamCache.removeWhere((key, _) => key.startsWith('$mediaId::'));
  }

  static List<String> _qualityFallbackOrder(String requested) {
    // Config values use underscores (AAC_WEB); gamdl codecs use hyphens
    // (aac-web).  Normalize before matching the ladder.
    final normalized =
        requested.toLowerCase().replaceAll('_', '-');
    final startIndex = _qualityLadder.indexOf(normalized);
    if (startIndex < 0) return [normalized];
    return _qualityLadder.sublist(startIndex);
  }

  static int _bitrateFor(String codec) => switch (codec) {
        'atmos' => 768000,
        'ac3' => 384000,
        'aac' => 256000,
        'aac-web' => 256000,
        'aac-he' => 64000,
        _ => 256000,
      };
}

class _CachedStream {
  _CachedStream(this.stream, this.expiresAt);

  final ResolvedStream stream;
  final DateTime expiresAt;
}
