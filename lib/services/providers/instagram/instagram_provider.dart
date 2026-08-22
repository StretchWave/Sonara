import 'dart:convert';
import 'dart:io';

import '../../stream_service.dart' show Audio, Codec;
import '../audio_source_provider.dart';
import '../matching/track_candidate.dart';
import '../matching/track_scorer.dart';
import '../resolved_stream.dart';
import '../song_query.dart';

/// Instagram Music provider — streams audio clips from Instagram Reels
/// through Instagram's internal API.
///
/// Adapted from MetroFuse's `InstagramAudioProvider` (GPL-3.0, see repo
/// attribution).  Requires Instagram session cookies for authentication.
/// The provider uses Instagram's music search API to find tracks and
/// resolves their audio stream URLs.
class InstagramProvider extends AudioSourceProvider {
  InstagramProvider({
    this.sessionCookie = '',
    this.matchOverrides = const {},
  });

  static const String providerId = 'instagram';

  /// Instagram session cookie for authentication.
  final String sessionCookie;

  /// Remembered manual match corrections: `instagram::mediaId` → trackId.
  final Map<String, String> matchOverrides;

  static const String _defaultUserAgent =
      'Instagram 385.0.0.47.74 Android (26/8.0.0; 480dpi; 1080x1920; '
      'OnePlus; 6T Dev; devitron; qcom; en_US; 378906843)';

  static const String _apiBaseUrl = 'https://i.instagram.com/api/v1';

  static const Duration _streamCacheDuration = Duration(minutes: 20);
  static const int _maxSearchCandidates = 5;

  final Map<String, _CachedStream> _streamCache = {};

  @override
  String get id => providerId;

  bool get isConfigured => sessionCookie.isNotEmpty;

  @override
  Future<ResolvedStream> resolve(SongQuery query) async {
    if (!isConfigured) {
      return const ResolvedStream(
        playable: false,
        statusMSG: 'Instagram not configured (session cookie required)',
      );
    }

    if (query.title.isEmpty) {
      return const ResolvedStream(
        playable: false,
        statusMSG: 'Song title required for Instagram resolution',
      );
    }

    // Check cache
    final cacheKey = '${query.mediaId}::${query.title}';
    final cached = _streamCache[cacheKey];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return cached.stream;
    }

    return _resolve(query);
  }

  Future<ResolvedStream> _resolve(SongQuery query) async {
    final searchQuery = _buildSearchQuery(query);

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      try {
        // Try multiple search endpoints
        final searchUrls = [
          '$_apiBaseUrl/music/audio_global_search/'
              '?query=${Uri.encodeComponent(searchQuery)}'
              '&count=$_maxSearchCandidates',
          '$_apiBaseUrl/music/search_v2/'
              '?query=${Uri.encodeComponent(searchQuery)}'
              '&surface=clips',
        ];

        for (final searchUrl in searchUrls) {
          final results = await _fetchSearchResults(client, searchUrl);
          if (results != null && results.isNotEmpty) {
            final bestResult = _selectBestResult(results, query);
            if (bestResult != null) {
              final streamUrl = bestResult['audioUrl']?.toString();
              if (streamUrl != null && streamUrl.isNotEmpty) {
                final resolved = ResolvedStream(
                  playable: true,
                  statusMSG: 'OK',
                  label: 'Instagram Music',
                  mimeType: 'audio/aac',
                  audioFormats: [
                    Audio(
                      itag: 0,
                      audioCodec: Codec.mp4a,
                      bitrate: 128000,
                      duration: query.durationMs ?? 0,
                      loudnessDb: 0,
                      url: streamUrl,
                      size: 0,
                      label: 'Instagram Music',
                      mimeType: 'audio/aac',
                      headers: {
                        'User-Agent': _defaultUserAgent,
                        'Cookie': sessionCookie,
                        'Referer': 'https://www.instagram.com/',
                      },
                    ),
                  ],
                );

                // Cache the result
                final cacheKey = '${query.mediaId}::${query.title}';
                _streamCache[cacheKey] = _CachedStream(
                  resolved,
                  DateTime.now().add(_streamCacheDuration),
                );

                return resolved;
              }
            }
          }
        }

        return const ResolvedStream(
          playable: false,
          statusMSG: 'No playable audio found on Instagram for this track',
        );
      } finally {
        client.close();
      }
    } catch (e) {
      return ResolvedStream(
        playable: false,
        statusMSG: 'Instagram resolution error: $e',
      );
    }
  }

  String _buildSearchQuery(SongQuery query) {
    final parts = <String>[
      if (query.title.isNotEmpty) query.title,
      if (query.artists.isNotEmpty) query.artists.first,
    ];
    return parts.join(' ');
  }

  Future<List<Map<String, dynamic>>?> _fetchSearchResults(
    HttpClient client,
    String url,
  ) async {
    try {
      final uri = Uri.parse(url);
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', _defaultUserAgent);
      req.headers.set('Accept', 'application/json');
      if (sessionCookie.isNotEmpty) {
        req.headers.set('Cookie', sessionCookie);
      }

      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final body = await utf8.decoder.bind(res).join();
      final json = jsonDecode(body);

      if (json is Map<String, dynamic>) {
        // Look for audio items in various response formats
        final audioItems = json['audio_items'] ??
            json['items'] ??
            json['results'];
        if (audioItems is List) {
          return audioItems.whereType<Map<String, dynamic>>().toList();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _selectBestResult(
    List<Map<String, dynamic>> results,
    SongQuery query,
  ) {
    if (results.isEmpty) return null;

    final candidates = <_InstagramCandidate>[];
    for (final result in results) {
      final title = result['display_title']?.toString() ??
          result['title']?.toString() ??
          result['name']?.toString() ??
          '';
      final artist = result['display_artist']?.toString() ??
          result['subtitle']?.toString() ??
          result['artist_name']?.toString() ??
          '';

      // Extract audio URL from various formats
      String? audioUrl;
      final audioAsset = result['audio_asset'];
      if (audioAsset is Map) {
        audioUrl = audioAsset['progressive_download_url']?.toString() ??
            audioAsset['download_url']?.toString();
      }
      audioUrl ??= result['audioUrl']?.toString();
      audioUrl ??= result['url']?.toString();

      if (audioUrl == null || audioUrl.isEmpty) continue;

      candidates.add(_InstagramCandidate(
        title: title,
        artist: artist,
        audioUrl: audioUrl,
        result: result,
      ));
    }

    if (candidates.isEmpty) return null;

    // Score candidates against the query
    _InstagramCandidate? bestCandidate;
    var bestScore = -1000000;

    for (final candidate in candidates) {
      final trackCandidate = TrackCandidate(
        trackId: candidate.audioUrl,
        title: candidate.title,
        artists: candidate.artist.isNotEmpty ? [candidate.artist] : [],
      );
      final score = scoreCandidate(
        candidate: trackCandidate,
        query: query,
      );
      if (score > bestScore) {
        bestScore = score;
        bestCandidate = candidate;
      }
    }

    if (bestCandidate == null || bestScore <= rejectScore) {
      return candidates.isNotEmpty ? candidates.first.result : null;
    }

    return bestCandidate.result;
  }

  @override
  void invalidate(String mediaId) {
    _streamCache.removeWhere((key, _) => key.startsWith('$mediaId::'));
  }
}

class _InstagramCandidate {
  final String title;
  final String artist;
  final String audioUrl;
  final Map<String, dynamic> result;

  _InstagramCandidate({
    required this.title,
    required this.artist,
    required this.audioUrl,
    required this.result,
  });
}

class _CachedStream {
  _CachedStream(this.stream, this.expiresAt);

  final ResolvedStream stream;
  final DateTime expiresAt;
}
