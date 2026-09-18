import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../stream_service.dart' show Audio, Codec;
import 'audio_source_provider.dart';
import 'resolved_stream.dart';
import 'song_query.dart';

/// Client candidate definition for InnerTube player requests.
class _InnerTubeClientCandidate {
  final String name;
  final String clientName;
  final String clientVersion;
  final String clientNameHeader;
  final String userAgent;
  final Map<String, dynamic> clientContext;
  final bool isEmbedded;

  /// Whether this client requires the X-Goog-Visitor-Id header to return
  /// playable streams (VISIONOS does; without it YouTube answers
  /// LOGIN_REQUIRED).
  final bool needsVisitorId;

  /// Whether the resolved stream URLs need the client User-Agent header to
  /// be playable. VISIONOS URLs are served without any headers, so they are
  /// handed to the player bare.
  final bool includeStreamHeaders;

  const _InnerTubeClientCandidate({
    required this.name,
    required this.clientName,
    required this.clientVersion,
    required this.clientNameHeader,
    required this.userAgent,
    required this.clientContext,
    this.isEmbedded = false,
    this.needsVisitorId = false,
    this.includeStreamHeaders = true,
  });
}

/// Streams audio directly from YouTube / YouTube Music using multi-client
/// InnerTube racing, Piped fallback, and YoutubeExplode fallback.
class YouTubeAudioProvider extends AudioSourceProvider {
  const YouTubeAudioProvider({this.visitorId = ''});

  /// YouTube visitor data ("X-Goog-Visitor-Id") from the app's cached
  /// visitorId. Required by the VISIONOS client.
  final String visitorId;

  static const String providerId = 'youtube_music';

  @override
  String get id => providerId;

  static String? _resolvedVisitorId;

  /// Retrieves cached visitor ID or dynamically fetches a fresh one from YouTube.
  static Future<String?> getOrFetchVisitorId({
    String? currentVisitorId,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      if (currentVisitorId != null && currentVisitorId.isNotEmpty) {
        _resolvedVisitorId = currentVisitorId;
        return currentVisitorId;
      }
      if (_resolvedVisitorId != null && _resolvedVisitorId!.isNotEmpty) {
        return _resolvedVisitorId;
      }
      try {
        if (Hive.isBoxOpen('AppPrefs')) {
          final prefs = Hive.box('AppPrefs');
          final vData = prefs.get('visitorId');
          if (vData is Map &&
              vData['id'] is String &&
              (vData['id'] as String).isNotEmpty) {
            _resolvedVisitorId = vData['id'] as String;
            return _resolvedVisitorId;
          }
        }
      } catch (_) {}
    }

    // Fetch directly from YouTube Music
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(Uri.parse('https://music.youtube.com/'));
      req.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0');
      req.headers.set('Cookie', 'CONSENT=YES+1; PREF=gl=US&hl=en');
      final res = await req.close().timeout(const Duration(seconds: 4));
      final body = await utf8.decoder.bind(res).join();
      client.close();

      String? newId;
      final match =
          RegExp(r'ytcfg\.set\s*\(\s*({.+?})\s*\)\s*;').firstMatch(body);
      if (match != null) {
        final ytcfg = jsonDecode(match.group(1)!);
        if (ytcfg is Map && ytcfg['VISITOR_DATA'] is String) {
          newId = ytcfg['VISITOR_DATA'] as String;
        }
      }
      if (newId == null || newId.isEmpty) {
        final m2 =
            RegExp(r'"VISITOR_DATA"\s*:\s*"([^"]+)"').firstMatch(body);
        if (m2 != null) {
          newId = m2.group(1);
        }
      }
      if (newId != null && newId.isNotEmpty) {
        _resolvedVisitorId = newId;
        try {
          if (Hive.isBoxOpen('AppPrefs')) {
            final prefs = Hive.box('AppPrefs');
            prefs.put('visitorId', {
              'id': newId,
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2592000,
            });
          }
        } catch (_) {}
        return newId;
      }
    } catch (_) {}
    return _resolvedVisitorId;
  }

  static const _ipadUserAgent =
      'com.google.ios.youtube/21.03.3 (iPad7,6; U; CPU iPadOS 17_7_10 like Mac OS X; en-US)';

  static final List<_InnerTubeClientCandidate> _candidates = [
    // VISIONOS (yt-dlp's current primary client). Its stream URLs are NOT
    // range-gated (unlike IOS URLs, which only ever serve the first 1 MiB
    // and therefore cannot be streamed by mpv/ExoPlayer), so it must be
    // tried first.
    const _InnerTubeClientCandidate(
      name: 'VISIONOS',
      clientName: 'VISIONOS',
      clientVersion: '1.02',
      clientNameHeader: '101',
      userAgent:
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
      clientContext: {
        'client': {
          'clientName': 'VISIONOS',
          'clientVersion': '1.02',
          'deviceMake': 'Apple',
          'deviceModel': 'RealityDevice17,1',
          'osName': 'visionOS',
          'osVersion': '26.5.23O471',
          'gl': 'US',
          'hl': 'en',
        }
      },
      needsVisitorId: true,
      includeStreamHeaders: false,
    ),
    const _InnerTubeClientCandidate(
      name: 'TVHTML5_EMBEDDED',
      clientName: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
      clientVersion: '2.0',
      clientNameHeader: '85',
      userAgent:
          'Mozilla/5.0 (PlayStation; PlayStation 4/12.02) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15',
      clientContext: {
        'client': {
          'clientName': 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
          'clientVersion': '2.0',
          'gl': 'US',
          'hl': 'en',
        }
      },
      isEmbedded: true,
    ),
  ];

  static const List<String> _pipedInstances = [
    'https://pipedapi.kavin.rocks',
    'https://api.piped.privacydev.net',
    'https://pipedapi.tokhmi.xyz',
    'https://piped-api.garudalinux.org',
  ];

  @override
  Future<ResolvedStream> resolve(SongQuery query) async {
    final videoId = query.mediaId;

    // 1. Try InnerTube multi-client racing (visionOS / TV embedded)
    try {
      final innerTubeResult = await _resolveInnerTube(videoId);
      if (innerTubeResult != null && innerTubeResult.playable) {
        return innerTubeResult;
      }
    } catch (_) {
      // Continue to next fallback
    }

    // 2. Try Piped instances fallback
    try {
      final pipedResult = await _resolvePiped(videoId);
      if (pipedResult != null && pipedResult.playable) {
        return pipedResult;
      }
    } catch (_) {
      // Continue to next fallback
    }

    // 3. Fallback to YoutubeExplode
    return _resolveYoutubeExplode(videoId);
  }

  Future<ResolvedStream?> _resolveInnerTube(String videoId) async {
    String? activeVisitorId =
        await getOrFetchVisitorId(currentVisitorId: visitorId);

    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);

    try {
      for (final candidate in _candidates) {
        if (candidate.needsVisitorId &&
            (activeVisitorId == null || activeVisitorId.isEmpty)) {
          activeVisitorId = await getOrFetchVisitorId(forceRefresh: true);
          if (activeVisitorId == null || activeVisitorId.isEmpty) {
            continue;
          }
        }

        ResolvedStream? streamResult = await _queryCandidate(
          httpClient,
          candidate,
          videoId,
          activeVisitorId,
        );

        // If candidate failed with missing/expired visitor data, refresh and retry once
        if (streamResult == null && candidate.needsVisitorId) {
          activeVisitorId = await getOrFetchVisitorId(forceRefresh: true);
          if (activeVisitorId != null && activeVisitorId.isNotEmpty) {
            streamResult = await _queryCandidate(
              httpClient,
              candidate,
              videoId,
              activeVisitorId,
            );
          }
        }

        if (streamResult != null && streamResult.playable) {
          return streamResult;
        }
      }
      return null;
    } finally {
      httpClient.close();
    }
  }

  Future<ResolvedStream?> _queryCandidate(
    HttpClient httpClient,
    _InnerTubeClientCandidate candidate,
    String videoId,
    String? visitorToken,
  ) async {
    try {
      final uri = Uri.parse(
          'https://music.youtube.com/youtubei/v1/player?prettyPrint=false');
      final req = await httpClient.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('User-Agent', candidate.userAgent);
      req.headers.set('X-YouTube-Client-Name', candidate.clientNameHeader);
      req.headers.set('X-YouTube-Client-Version', candidate.clientVersion);
      req.headers.set('Origin', 'https://music.youtube.com');
      if (candidate.needsVisitorId &&
          visitorToken != null &&
          visitorToken.isNotEmpty) {
        req.headers.set('X-Goog-Visitor-Id', visitorToken);
      }
      final context = Map<String, dynamic>.from(candidate.clientContext);
      if (candidate.needsVisitorId &&
          visitorToken != null &&
          visitorToken.isNotEmpty) {
        final clientMap = Map<String, dynamic>.from(context['client'] as Map);
        clientMap['visitorData'] = visitorToken;
        context['client'] = clientMap;
      }
      if (candidate.isEmbedded) {
        context['thirdParty'] = {
          'embedUrl': 'https://www.youtube.com/watch?v=$videoId'
        };
      }

      final bodyBytes = utf8.encode(jsonEncode({
        'context': context,
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      }));
      req.add(bodyBytes);

      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return null;

      final resBody = await utf8.decoder.bind(res).join();
      final json = jsonDecode(resBody);

      final playability = json['playabilityStatus'];
      if (playability != null && playability['status'] != 'OK') {
        return null;
      }

      final streamingData = json['streamingData'];
      if (streamingData == null) return null;

      final formatsRaw = (streamingData['adaptiveFormats'] as List? ?? [])
          .where((f) => (f['mimeType'] as String? ?? '').startsWith('audio/'))
          .toList();

      if (formatsRaw.isEmpty) return null;

      final formats = <Audio>[];
      for (final f in formatsRaw) {
        final url = f['url'] as String?;
        if (url == null || url.isEmpty) continue;
        // Never serve range-gated iOS URLs that return 403 past 1MB
        if (url.contains('c=IOS') || url.contains('c=ios')) continue;

        final itag = (f['itag'] as num?)?.toInt() ?? 140;
        final mimeType = (f['mimeType'] as String? ?? 'audio/mp4');
        final bitrate = (f['bitrate'] as num?)?.toInt() ?? 128000;
        final approxDurationMs =
            int.tryParse('${f['approxDurationMs']}') ?? 0;
        final contentLength = int.tryParse('${f['contentLength']}') ?? 0;
        final loudnessDb = (f['loudnessDb'] as num?)?.toDouble() ?? 0.0;

        final isOpus = mimeType.contains('opus') ||
            mimeType.contains('webm') ||
            itag == 251 ||
            itag == 250 ||
            itag == 249;

        formats.add(Audio(
          itag: itag,
          audioCodec: isOpus ? Codec.opus : Codec.mp4a,
          bitrate: bitrate,
          duration: approxDurationMs,
          loudnessDb: loudnessDb,
          url: url,
          size: contentLength,
          mimeType: mimeType.split(';').first.trim(),
          headers: candidate.includeStreamHeaders
              ? {
                  'User-Agent': candidate.userAgent,
                }
              : null,
        ));
      }

      if (formats.isNotEmpty) {
        formats.sort((a, b) => b.bitrate.compareTo(a.bitrate));
        return ResolvedStream(
          playable: true,
          statusMSG: 'OK',
          audioFormats: formats,
        );
      }
    } catch (_) {}
    return null;
  }

  Future<ResolvedStream?> _resolvePiped(String videoId) async {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);

    try {
      for (final instance in _pipedInstances) {
        try {
          final uri = Uri.parse('$instance/streams/$videoId');
          final req = await httpClient.getUrl(uri);
          req.headers.set('User-Agent', _ipadUserAgent);
          final res = await req.close().timeout(const Duration(seconds: 4));
          if (res.statusCode != 200) continue;

          final resBody = await utf8.decoder.bind(res).join();
          final json = jsonDecode(resBody);
          final audioStreams = json['audioStreams'] as List? ?? [];
          if (audioStreams.isEmpty) continue;

          final formats = <Audio>[];
          for (final s in audioStreams) {
            final url = s['url'] as String?;
            if (url == null || url.isEmpty) continue;

            final itag = (s['itag'] as num?)?.toInt() ?? 140;
            final mimeType = (s['mimeType'] as String? ?? 'audio/mp4');
            final bitrate = (s['bitrate'] as num?)?.toInt() ?? 128000;
            final isOpus = mimeType.contains('opus') ||
                mimeType.contains('webm') ||
                itag == 251 ||
                itag == 250;

            formats.add(Audio(
              itag: itag,
              audioCodec: isOpus ? Codec.opus : Codec.mp4a,
              bitrate: bitrate,
              duration: 0,
              loudnessDb: 0.0,
              url: url,
              size: (s['contentLength'] as num?)?.toInt() ?? 0,
              mimeType: mimeType,
              headers: {
                'User-Agent': _ipadUserAgent,
              },
            ));
          }

          if (formats.isNotEmpty) {
            formats.sort((a, b) => b.bitrate.compareTo(a.bitrate));
            return ResolvedStream(
              playable: true,
              statusMSG: 'OK',
              audioFormats: formats,
            );
          }
        } catch (_) {
          continue;
        }
      }
      return null;
    } finally {
      httpClient.close();
    }
  }

  Future<ResolvedStream> _resolveYoutubeExplode(String videoId) async {
    final yt = YoutubeExplode();
    try {
      StreamManifest? res;
      Object? lastError;
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          res = await yt.videos.streamsClient.getManifest(videoId);
          break;
        } catch (e) {
          lastError = e;
          if (attempt < 1) {
            await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
          }
        }
      }
      if (res == null) {
        throw lastError ?? Exception('Could not fetch stream manifest');
      }
      final audio = res.audioOnly;
      return ResolvedStream(
        playable: true,
        statusMSG: 'OK',
        audioFormats: audio
            .map((e) => Audio(
                itag: e.tag,
                audioCodec:
                    e.audioCodec.contains('mp') ? Codec.mp4a : Codec.opus,
                bitrate: e.bitrate.bitsPerSecond,
                duration: e.duration ?? 0,
                loudnessDb: e.loudnessDb,
                url: e.url.toString(),
                size: e.size.totalBytes,
                headers: {
                  'User-Agent': _ipadUserAgent,
                }))
            .toList(),
      );
    } catch (e) {
      if (e is SocketException) {
        return const ResolvedStream(playable: false, statusMSG: 'networkError');
      } else if (e is VideoUnplayableException) {
        return ResolvedStream(
          playable: false,
          statusMSG: e.reason ?? 'Song is unplayable',
        );
      } else if (e is VideoRequiresPurchaseException) {
        return const ResolvedStream(
          playable: false,
          statusMSG: 'Song requires purchase',
        );
      } else if (e is VideoUnavailableException) {
        return const ResolvedStream(
          playable: false,
          statusMSG: 'Song is unavailable',
        );
      } else if (e is YoutubeExplodeException) {
        return ResolvedStream(playable: false, statusMSG: e.message);
      } else {
        return const ResolvedStream(
          playable: false,
          statusMSG: 'Unknown error occurred',
        );
      }
    } finally {
      yt.close();
    }
  }
}
