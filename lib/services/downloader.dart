import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:audiotags/audiotags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../ui/screens/Album/album_screen_controller.dart';
import '../ui/screens/Playlist/playlist_screen_controller.dart';
import '/services/providers/song_query.dart';
import '/services/providers/stream_route_config.dart';
import '/services/providers/stream_router.dart';
import '/services/stream_service.dart';
import '../ui/widgets/snackbar.dart';
import '/services/permission_service.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '/utils/helper.dart';
import '/models/media_Item_builder.dart';
import '../ui/screens/Library/library_controller.dart';
import 'music_service.dart';
//import '../models/thumbnail.dart' as th;

class Downloader extends GetxService {
  final _dio = Dio();
  MediaItem? currentSong;
  RxMap<String, List<MediaItem>> playlistQueue =
      <String, List<MediaItem>>{}.obs;
  final currentPlaylistId = "".obs;
  final songDownloadingProgress = 0.obs;
  final playlistDownloadingProgress = 0.obs;
  final isJobRunning = false.obs;

  RxList<MediaItem> songQueue = <MediaItem>[].obs;

  Future<bool> checkPermissionNDir() async {
    final settingsScreenController = Get.find<SettingsScreenController>();

    if (!settingsScreenController.isCurrentPathsupportDownDir &&
        !await PermissionService.getExtStoragePermission()) {
      return false;
    }

    final dirPath =
        Get.find<SettingsScreenController>().downloadLocationPath.string;
    final directory = Directory(dirPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return true;
  }

  Future<void> downloadPlaylist(
      String playlistId, List<MediaItem> songList) async {
    if (!(await checkPermissionNDir())) return;

    // for toggle between downloading request & cancelling
    if (playlistQueue.containsKey(playlistId)) {
      songQueue.removeWhere((element) => songList.contains(element));
      playlistQueue.remove(playlistId);
      return;
    }

    playlistQueue[playlistId] = songList;
    songQueue.addAll(songList);

    if (isJobRunning.isFalse) {
      await triggerDownloadingJob();
    }
  }

  /// Queues [song] (or a whole [songList]) for download.
  ///
  /// [format] overrides the global default for this download: "original",
  /// "mp3", "flac", "opus" or "m4a". Playlists/auto-downloads pass no
  /// format and use the setting from Settings → Download.
  Future<void> download(MediaItem? song,
      {List<MediaItem>? songList, String? format}) async {
    if (!(await checkPermissionNDir())) return;
    if (songList != null) {
      for (final item in songList) {
        _setDownloadFormat(item, format);
      }
      songQueue.addAll(songList);
    } else {
      _setDownloadFormat(song!, format);
      songQueue.add(song);
    }
    if (isJobRunning.isFalse) {
      await triggerDownloadingJob();
    }
  }

  /// Records a per-song format override on the item (null = use default).
  void _setDownloadFormat(MediaItem song, String? format) {
    if (format == null || format == 'original') {
      song.extras?.remove('downloadFormat');
    } else {
      song.extras?['downloadFormat'] = format;
    }
  }

  Future<void> triggerDownloadingJob() async {
    //check if playlist download in queue => download playlistsongs else download from general songs queue
    if (playlistQueue.isNotEmpty) {
      isJobRunning.value = true;
      for (String playlistId in playlistQueue.keys.toList()) {
        //checked in case download cancel request
        if (playlistQueue.containsKey(playlistId)) {
          currentPlaylistId.value = playlistId;
          await downloadSongList((playlistQueue[playlistId]!).toList(),
              isPlaylist: true);
          if (Get.isRegistered<PlaylistScreenController>(
                  tag: Key(playlistId).hashCode.toString()) &&
              playlistQueue.containsKey(playlistId)) {
            Get.find<PlaylistScreenController>(
                    tag: Key(playlistId).hashCode.toString())
                .isDownloaded
                .value = true;
          } 
          // in case of album
          else if (Get.isRegistered<AlbumScreenController>(
                  tag: Key(playlistId).hashCode.toString()) &&
              playlistQueue.containsKey(playlistId)) {
            Get.find<AlbumScreenController>(
                    tag: Key(playlistId).hashCode.toString())
                .isDownloaded
                .value = true;
          }
          playlistQueue.remove(playlistId);
        }
        currentPlaylistId.value = "";
        playlistDownloadingProgress.value = 0;
      }
    } else {
      isJobRunning.value = true;
      await downloadSongList(songQueue.toList());
    }

    if (songQueue.isNotEmpty) {
      triggerDownloadingJob();
    } else {
      isJobRunning.value = false;
      currentSong = null;
    }
  }

  Future<void> downloadSongList(List<MediaItem> jobSongList,
      {bool isPlaylist = false}) async {
    for (MediaItem song in jobSongList) {
      // intrrupt downloading task in case of playlist download cancel request
      if (isPlaylist && !playlistQueue.containsKey(currentPlaylistId.value)) {
        currentPlaylistId.value = "";
        playlistDownloadingProgress.value = 0;
        return;
      }

      if (!Hive.box("SongDownloads").containsKey(song.id)) {
        currentSong = song;
        songDownloadingProgress.value = 0;
        await writeFileStream(song);
      }
      songQueue.remove(song);
      //for playlist downloading counter update
      if (isPlaylist) {
        playlistDownloadingProgress.value = jobSongList.indexOf(song) + 1;
      }
    }
  }

  Future<void> writeFileStream(MediaItem song) async {
    Completer<void> complete = Completer();

    final settingsScreenController = Get.find<SettingsScreenController>();
    final globalFormat = settingsScreenController.downloadingFormat.string;
    final requestedFormat = (song.extras?['downloadFormat'] as String?) ??
        (globalFormat.isEmpty ? 'original' : globalFormat);

    final playerResponse = await StreamRouter.build(StreamRouteConfig.fromSettings())
        .fetch(song.id, song: SongQuery.fromMediaItem(song));

    if (!playerResponse.playable) {
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!,
          playerResponse.statusMSG == "networkError"
              ? playerResponse.statusMSG.tr
              : playerResponse.statusMSG,
          size: SanckBarSize.BIG,
          duration: const Duration(seconds: 2),
          top: !GetPlatform.isDesktop));
      printINFO("Requested song is not downloadable. You may try again");
      complete.complete();
      return complete.future;
    }

    final requiredAudioStream = _pickAudioForFormat(playerResponse, requestedFormat);
    if (requiredAudioStream == null) {
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "downloadError3".tr,
          size: SanckBarSize.BIG,
          duration: const Duration(seconds: 2),
          top: !GetPlatform.isDesktop));
      printINFO("No audio stream available for download");
      complete.complete();
      return complete.future;
    }

    final dirPath = settingsScreenController.downloadLocationPath.string;
    final sourceExt = _extensionForCodec(requiredAudioStream.audioCodec);
    // Only MP3/FLAC can trigger a transcode; everything else keeps the
    // source file (and its real extension) as-is.
    final needsConversion = requestedFormat == 'mp3' ||
        (requestedFormat == 'flac' &&
            requiredAudioStream.audioCodec != Codec.flac);
    final targetExt =
        needsConversion ? (requestedFormat == 'flac' ? 'flac' : 'mp3') : sourceExt;
    final RegExp invalidChar =
        RegExp(r'Container.|\/|\\|\"|\<|\>|\*|\?|\:|\!|\[|\]|\¡|\||\%');
    final songTitle = "${song.title.trim()} (${song.artist?.trim()})"
        .replaceAll(invalidChar, "");
    String filePath = "$dirPath/$songTitle.$targetExt";
    final tempPath = "$filePath.part";
    printINFO("Downloading ($requestedFormat): $filePath");
    final totalBytes = requiredAudioStream.size;
    final downloadHeaders = <String, dynamic>{
      if (totalBytes > 0) "Range": 'bytes=0-$totalBytes',
      if (requiredAudioStream.headers != null) ...requiredAudioStream.headers!,
    };

    _dio.download(
        requiredAudioStream.url,
        options: Options(headers: downloadHeaders),
        tempPath, onReceiveProgress: (count, total) {
      if (total <= 0) return;
      songDownloadingProgress.value = ((count / total) * 100).toInt();
    }).then(
      (value) async {
        printINFO(value.data);

        // Convert (MP3/FLAC) or move the temp file into place.
        if (needsConversion) {
          final ok = await _convertToFormat(tempPath, filePath, requestedFormat);
          if (!ok) {
            final fallbackPath = "$dirPath/$songTitle.$sourceExt";
            await File(tempPath).rename(fallbackPath);
            filePath = fallbackPath;
            ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
                Get.context!,
                "ffmpeg not found — saved as $sourceExt instead",
                size: SanckBarSize.BIG,
                duration: const Duration(seconds: 2),
                top: !GetPlatform.isDesktop));
          }
        } else {
          await File(tempPath).rename(filePath);
        }

        String? year;
        try {
          if (song.extras?['year'] != null) {
            year = song.extras?['year'];
          } else {
            if (song.album != null) {
              final musicServ = Get.find<MusicServices>();
              year = await musicServ.getSongYear(song.id);
            }
          }
        } catch (_) {}

        // Save Thumbnail
        try {
          final thumbnailPath =
              "${settingsScreenController.supportDirPath}/thumbnails/${song.id}.png";
          await _dio.downloadUri(song.artUri!, thumbnailPath);
          // ignore: empty_catches
        } catch (e) {}

        song.extras?['url'] = filePath;
        final songJson = MediaItemBuilder.toJson(song);
        final streamInfoJson = requiredAudioStream.toJson();
        streamInfoJson['url'] = filePath;
        // [playbility status, info map]
        songJson["streamInfo"] = [true, streamInfoJson];

        Hive.box("SongDownloads").put(song.id, songJson);
        Get.find<LibrarySongsController>().librarySongsList.add(song);
        printINFO("Downloaded successfully");

        final trackDetails = (song.extras?['trackDetails'])?.split("/");
        final int? trackNumber = int.tryParse(trackDetails?[0] ?? "");
        final int? totalTracks = int.tryParse(trackDetails?[1] ?? "");

        try {
          /// Reverted -- Removed AudioTags as using this package, app is flagged as TROJ_GEN.R002V01K623 by TrendMicro-HouseCall
          final imageUrl = song.artUri!.toString();
          Tag tag = Tag(
              title: song.title,
              trackArtist: song.artist,
              album: song.album,
              year: int.tryParse(year ?? ""),
              trackNumber: trackNumber,
              trackTotal: totalTracks,
              albumArtist: song.artist,
              genre: song.genre,
              pictures: [
                Picture(
                    bytes: (await NetworkAssetBundle(Uri.parse((imageUrl)))
                            .load(imageUrl))
                        .buffer
                        .asUint8List(),
                    mimeType: MimeType.png,
                    pictureType: PictureType.coverFront)
              ]);

          await AudioTags.write(filePath, tag);
        } catch (e) {
          printERROR("$e");
        }
        complete.complete();
      },
    ).onError(
      (error, stackTrace) {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, "downloadError3".tr,
            size: SanckBarSize.BIG,
            duration: const Duration(seconds: 2),
            top: !GetPlatform.isDesktop));
        printINFO(
            "Downloading failed due to network/stream error! Please try again");
        complete.complete();
      },
    );

    return complete.future;
  }

  /// Picks the source audio stream for the requested download format.
  ///
  /// "original"/"mp3"/"flac" prefer lossless then the highest-quality
  /// YouTube stream (Opus); "opus"/"m4a" keep their historical behavior
  /// of selecting the matching stream when present.
  Audio? _pickAudioForFormat(StreamProvider response, String format) {
    final formats = response.audioFormats ?? const [];
    if (formats.isEmpty) return null;
    Audio? firstOf(Codec codec) {
      for (final audio in formats) {
        if (audio.audioCodec == codec) return audio;
      }
      return null;
    }

    switch (format) {
      case 'opus':
        return firstOf(Codec.opus) ?? formats.first;
      case 'm4a':
        return firstOf(Codec.mp4a) ?? formats.first;
      case 'flac':
        return firstOf(Codec.flac) ?? firstOf(Codec.opus) ?? formats.first;
      case 'mp3':
        return firstOf(Codec.flac) ?? firstOf(Codec.opus) ?? formats.first;
      default: // original
        return firstOf(Codec.flac) ?? firstOf(Codec.opus) ?? formats.first;
    }
  }

  static String _extensionForCodec(Codec codec) => switch (codec) {
        Codec.flac => 'flac',
        Codec.mp3 => 'mp3',
        Codec.mp4a => 'm4a',
        Codec.opus => 'opus',
      };

  bool? _ffmpegChecked;
  bool _ffmpegOk = false;

  /// Whether the `ffmpeg` binary is available on this device (desktop).
  Future<bool> _ffmpegAvailable() async {
    if (_ffmpegChecked == true) return _ffmpegOk;
    _ffmpegChecked = true;
    try {
      final res = await Process.run('ffmpeg', ['-version']);
      _ffmpegOk = res.exitCode == 0;
    } catch (_) {
      _ffmpegOk = false;
    }
    return _ffmpegOk;
  }

  /// Transcodes [input] into [output] (mp3 320k or flac). Returns false
  /// when ffmpeg is missing or the conversion failed.
  Future<bool> _convertToFormat(
      String input, String output, String format) async {
    if (!await _ffmpegAvailable()) return false;
    try {
      final args = format == 'flac'
          ? ['-y', '-i', input, '-vn', '-codec:a', 'flac', output]
          : [
              '-y',
              '-i',
              input,
              '-vn',
              '-codec:a',
              'libmp3lame',
              '-b:a',
              '320k',
              output
            ];
      final res = await Process.run('ffmpeg', args);
      return res.exitCode == 0 && await File(output).exists();
    } catch (_) {
      return false;
    }
  }
}
