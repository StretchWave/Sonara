import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:sonara/services/lyrics_utils.dart';
import 'package:sonara/utils/helper.dart';
import 'package:hive/hive.dart';

class SyncedLyricsService {
  static Future<Map<String, dynamic>?> getSyncedLyrics(
      MediaItem song, int durInSec) async {
    final lyricsBox = await Hive.openBox("lyrics");
    // check if lyrics available in local database
    if (lyricsBox.containsKey(song.id)) {
      return Map<String, dynamic>.from(await lyricsBox.get(song.id));
    }

    final dur = song.duration?.inSeconds ?? durInSec;
    final url =
        'https://lrclib.net/api/get?artist_name=${song.artist?.replaceAll(" ", "+")}&track_name=${song.title.replaceAll(" ", "+")}&album_name=${song.album?.replaceAll(" ", "+")}&duration=$dur';
    try {
      final response = (await Dio().get(url)).data;
      if (response["syncedLyrics"] != null) {
        printINFO("Synced Available");
        final lyricsData = {
          "synced": response["syncedLyrics"],
          "plainLyrics": response["plainLyrics"]
        };
        await lyricsBox.put(song.id, lyricsData);
        return lyricsData;
      }
    } on DioException catch (e) {
      printERROR(e.response);
    }

    // Fallback: KuGou word-level karaoke lyrics (KRC)
    final kuGouLyrics = await getKuGouLyrics(song.title, song.artist, dur);
    if (kuGouLyrics != null) {
      printINFO("KuGou lyrics available");
      await lyricsBox.put(song.id, kuGouLyrics);
      return kuGouLyrics;
    }

    await lyricsBox.close();
    return null;
  }

  /// Fetches word-by-word karaoke lyrics from KuGou, decrypted and converted
  /// to the QRC format.
  static Future<Map<String, dynamic>?> getKuGouLyrics(
      String title, String? artist, int durInSec) async {
    try {
      final dio = Dio();
      final searchResponse = await dio.get(
        'https://lyrics.kugou.com/search',
        queryParameters: {
          'ver': 1,
          'man': 'yes',
          'client': 'pc',
          'keyword': "$title - ${artist ?? ''}",
          if (durInSec > 0) 'duration': durInSec,
        },
      );
      final candidates = (searchResponse.data['candidates'] as List?) ?? [];
      if (candidates.isEmpty) return null;

      // Prefer a candidate with an access key, preferring exact title match.
      candidates.sort((a, b) {
        final aExact = (a['song'] ?? '').toString().toLowerCase() ==
            title.toLowerCase();
        final bExact = (b['song'] ?? '').toString().toLowerCase() ==
            title.toLowerCase();
        if (aExact != bExact) return aExact ? -1 : 1;
        return 0;
      });
      dynamic candidate;
      for (final c in candidates) {
        if (c['accesskey'] != null) {
          candidate = c;
          break;
        }
      }
      if (candidate == null) return null;

      final downloadResponse = await dio.get(
        'https://lyrics.kugou.com/download',
        queryParameters: {
          'ver': 1,
          'client': 'pc',
          'fmt': 'krc',
          'id': candidate['id'],
          'accesskey': candidate['accesskey'],
        },
      );
      final content = downloadResponse.data['content']?.toString();
      if (content == null) return null;

      final krc = LyricsUtils.decryptKrc(content);
      if (krc == null) return null;
      final converted = LyricsUtils.krcToQrc(krc);
      if (converted == null) return null;

      return {
        "synced": converted['qrc'],
        "plainLyrics": converted['plain'],
        "format": "qrc",
      };
    } catch (e) {
      printERROR("KuGou lyrics fetch failed: $e");
      return null;
    }
  }
}
