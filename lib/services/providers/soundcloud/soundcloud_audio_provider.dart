import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../stream_service.dart' show Audio, Codec;
import '../audio_source_provider.dart';
import '../matching/track_candidate.dart';
import '../matching/track_scorer.dart';
import '../resolved_stream.dart';
import '../song_query.dart';

/// Audio provider that resolves streams from SoundCloud.
///
/// Adapted from MetroFuse's `SoundCloudAudioProvider`. Dynamically scrapes
/// client IDs from soundcloud.com script bundles, searches tracks by metadata,
/// matches candidates with fuzzy scoring, and resolves progressive / HLS streams.
class SoundCloudAudioProvider extends AudioSourceProvider {
  const SoundCloudAudioProvider();

  static const String providerId = 'soundcloud';

  @override
  String get id => providerId;

  static const String _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0';

  /// Picks the single search result that actually matches [query], or
  /// null when none is acceptable (covers, remixes, slowed/reverb uploads,
  /// wrong artists, implausible durations).
  ///
  /// Returns the raw SoundCloud track item so the caller can build a
  /// stream from it. Exposed for tests.
  @visibleForTesting
  static Map<String, dynamic>? pickBestMatchItem(
    List<dynamic> collection,
    SongQuery query,
  ) {
    dynamic bestTrack;
    var bestScore = rejectScore;
    for (final item in collection) {
      final trackId = '${item['id'] ?? ''}';
      final trackTitle = item['title'] as String? ?? '';
      final trackUser =
          item['user']?['username'] as String? ?? 'Unknown Artist';
      final trackDurationMs = (item['duration'] as num?)?.toInt();

      final candidate = TrackCandidate(
        trackId: trackId,
        title: trackTitle,
        artists: [trackUser],
        durationMs: trackDurationMs,
      );

      final score = scoreCandidate(
        candidate: candidate,
        query: query,
      );

      if (score > bestScore) {
        bestScore = score;
        bestTrack = item;
      }
    }
    return bestTrack as Map<String, dynamic>?;
  }

  static String? _cachedClientId;
  static DateTime? _clientIdExpiresAt;

  static final RegExp _scriptRegex =
      RegExp(r'https://[a-z0-9-]+\.sndcdn\.com/[^"<>\s!]+\.js');
  static final RegExp _clientIdRegex =
      RegExp(r'client_?id[:=]"([A-Za-z0-9]{20,})"', caseSensitive: false);

  /// Retrieves or scrapes a valid SoundCloud client ID.
  static Future<String?> getClientId({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedClientId != null &&
        _clientIdExpiresAt != null &&
        now.isBefore(_clientIdExpiresAt!)) {
      return _cachedClientId;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);

    try {
      final homeReq = await client.getUrl(Uri.parse('https://soundcloud.com'));
      homeReq.headers.set('User-Agent', _browserUserAgent);
      final homeRes = await homeReq.close().timeout(const Duration(seconds: 6));
      final homeHtml = await utf8.decoder.bind(homeRes).join();

      final scriptUrls = _scriptRegex
          .allMatches(homeHtml)
          .map((m) => m.group(0)!)
          .toSet()
          .toList();

      for (final scriptUrl in scriptUrls.reversed) {
        try {
          final sReq = await client.getUrl(Uri.parse(scriptUrl));
          sReq.headers.set('User-Agent', _browserUserAgent);
          final sRes =
              await sReq.close().timeout(const Duration(seconds: 5));
          if (sRes.statusCode == 200) {
            final js = await utf8.decoder.bind(sRes).join();
            final m = _clientIdRegex.firstMatch(js);
            if (m != null) {
              _cachedClientId = m.group(1);
              _clientIdExpiresAt = now.add(const Duration(hours: 12));
              return _cachedClientId;
            }
          }
        } catch (_) {
          continue;
        }
      }
      return _cachedClientId;
    } catch (_) {
      return _cachedClientId;
    } finally {
      client.close();
    }
  }

  @override
  Future<ResolvedStream> resolve(SongQuery query) async {
    final title = query.title.trim();
    final artist = query.artists.isNotEmpty ? query.artists.first.trim() : '';
    if (title.isEmpty) {
      return const ResolvedStream(
        playable: false,
        statusMSG: 'Song title required for SoundCloud resolution',
      );
    }

    final clientId = await getClientId();
    if (clientId == null || clientId.isEmpty) {
      return const ResolvedStream(
        playable: false,
        statusMSG: 'Failed to scrape SoundCloud client ID',
      );
    }

    final searchTerm = artist.isNotEmpty ? '$artist - $title' : title;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);

    try {
      final searchUri = Uri.parse(
          'https://api-v2.soundcloud.com/search/tracks?q=${Uri.encodeComponent(searchTerm)}&limit=8&client_id=$clientId&app_locale=en');
      final searchReq = await client.getUrl(searchUri);
      searchReq.headers.set('User-Agent', _browserUserAgent);
      final searchRes =
          await searchReq.close().timeout(const Duration(seconds: 6));

      if (searchRes.statusCode != 200) {
        return ResolvedStream(
          playable: false,
          statusMSG: 'SoundCloud search returned HTTP ${searchRes.statusCode}',
        );
      }

      final searchBody = await utf8.decoder.bind(searchRes).join();
      final searchJson = jsonDecode(searchBody);
      final collection = searchJson['collection'] as List? ?? [];
      if (collection.isEmpty) {
        return const ResolvedStream(
          playable: false,
          statusMSG: 'No matching tracks on SoundCloud',
        );
      }

      // Find best matching track candidate. SoundCloud is full of covers,
      // remixes and "slowed + reverb" uploads, so we only accept a result
      // that actually matches the requested song. When nothing does, we
      // fail here and let the router fall through to the next source
      // (YouTube) instead of playing SoundCloud's most popular upload,
      // which is often the wrong version.
      final bestTrack = pickBestMatchItem(collection, query);
      if (bestTrack == null) {
        return const ResolvedStream(
          playable: false,
          statusMSG: 'No acceptable match on SoundCloud',
        );
      }

      final media = bestTrack['media'];
      final transcodings = media?['transcodings'] as List? ?? [];
      if (transcodings.isEmpty) {
        return const ResolvedStream(
          playable: false,
          statusMSG: 'No stream transcodings found for SoundCloud track',
        );
      }

      // Sort transcodings: prefer progressive mp3, then hls mp3, then hls mp4
      transcodings.sort((a, b) {
        final aProtocol = a['format']?['protocol'] as String? ?? '';
        final bProtocol = b['format']?['protocol'] as String? ?? '';
        final aMime = a['format']?['mime_type'] as String? ?? '';
        final bMime = b['format']?['mime_type'] as String? ?? '';

        int rank(String protocol, String mime) {
          if (protocol == 'progressive' && mime.contains('mpeg')) return 3;
          if (protocol == 'hls' && mime.contains('mpeg')) return 2;
          if (protocol == 'hls' && (mime.contains('mp4') || mime.contains('aac'))) return 1;
          return 0;
        }

        return rank(bProtocol, bMime).compareTo(rank(aProtocol, aMime));
      });

      for (final t in transcodings) {
        final transcodingUrl = t['url'] as String?;
        if (transcodingUrl == null || transcodingUrl.isEmpty) continue;

        final format = t['format'];
        final protocol = format?['protocol'] as String? ?? '';
        final mimeType = (format?['mime_type'] as String? ?? 'audio/mpeg')
            .split(';')
            .first
            .trim();

        if (protocol != 'progressive' && protocol != 'hls') continue;

        try {
          final tUri = Uri.parse('$transcodingUrl?client_id=$clientId');
          final tReq = await client.getUrl(tUri);
          tReq.headers.set('User-Agent', _browserUserAgent);
          final tRes =
              await tReq.close().timeout(const Duration(seconds: 4));
          if (tRes.statusCode != 200) continue;

          final tBody = await utf8.decoder.bind(tRes).join();
          final tJson = jsonDecode(tBody);
          final streamUrl = tJson['url'] as String?;

          if (streamUrl != null && streamUrl.isNotEmpty) {
            final isAac = mimeType.contains('mp4') || mimeType.contains('aac');
            final isOpus = mimeType.contains('opus') || mimeType.contains('webm');
            final codec = isOpus
                ? Codec.opus
                : isAac
                    ? Codec.mp4a
                    : Codec.mp3;

            return ResolvedStream(
              playable: true,
              statusMSG: 'OK',
              label: 'SoundCloud ($protocol ${codec.name})',
              audioFormats: [
                Audio(
                  itag: 140,
                  audioCodec: codec,
                  bitrate: 128000,
                  duration: (bestTrack['duration'] as num?)?.toInt() ?? 0,
                  loudnessDb: 0.0,
                  url: streamUrl,
                  size: 0,
                  mimeType: mimeType,
                  headers: {
                    'User-Agent': _browserUserAgent,
                    'Referer': 'https://soundcloud.com/',
                  },
                ),
              ],
            );
          }
        } catch (_) {
          continue;
        }
      }

      return const ResolvedStream(
        playable: false,
        statusMSG: 'Could not resolve SoundCloud stream URL',
      );
    } catch (e) {
      return ResolvedStream(
        playable: false,
        statusMSG: 'SoundCloud resolution error: $e',
      );
    } finally {
      client.close();
    }
  }
}
