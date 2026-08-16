import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../stream_service.dart' show Audio, Codec;
import 'audio_source_provider.dart';
import 'resolved_stream.dart';
import 'song_query.dart';

/// Streams audio directly from YouTube / YouTube Music — the universal,
/// login-free, last-resort fallback source.
class YouTubeAudioProvider extends AudioSourceProvider {
  const YouTubeAudioProvider();

  static const String providerId = 'youtube_music';

  @override
  String get id => providerId;

  @override
  Future<ResolvedStream> resolve(SongQuery query) async {
    final videoId = query.mediaId;
    final yt = YoutubeExplode();

    try {
      // The manifest endpoint is flaky (intermittent null crashes inside the
      // client) — retry a couple of times before giving up.
      StreamManifest? res;
      Object? lastError;
      for (int attempt = 0; attempt < 3; attempt++) {
        try {
          res = await yt.videos.streamsClient.getManifest(videoId);
          break;
        } catch (e) {
          lastError = e;
          if (attempt < 2) {
            await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
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
                size: e.size.totalBytes))
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
    }
  }
}
