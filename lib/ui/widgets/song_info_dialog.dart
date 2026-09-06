import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/ui/widgets/common_dialog_widget.dart';
import '/ui/widgets/match_correction_dialog.dart';

class SongInfoDialog extends StatelessWidget {
  final MediaItem song;
  const SongInfoDialog({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    Map<dynamic, dynamic> streamInfo = _getStreamInfo(song.id);
    return CommonDialog(
      child: SizedBox(
        height: Get.mediaQuery.size.height * .7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: Text("songInfo".tr,
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            const Divider(),
            Expanded(
                child: ListView(
              children: [
                InfoItem(title: "id".tr, value: song.id),
                InfoItem(title: "title".tr, value: song.title),
                InfoItem(title: "album".tr, value: song.album ?? "NA"),
                InfoItem(title: "artists".tr, value: song.artist ?? "NA"),
                InfoItem(
                    title: "duration".tr,
                    value:
                        "${streamInfo["approxDurationMs"] ?? song.duration?.inMilliseconds ?? "NA"} ms"),
                InfoItem(
                    title: "audioCodec".tr,
                    value: streamInfo["audioCodec"] ?? "NA"),
                InfoItem(
                    title: "bitrate".tr,
                    value: "${streamInfo["bitrate"] ?? "NA"}"),
                if (song.extras?['streamSource'] != null || streamInfo["providerId"] != null)
                  InfoItem(
                    title: "Source",
                    value: "${song.extras?['streamSource'] ?? streamInfo["providerId"]}",
                  ),
                if (song.extras?['isrc'] != null)
                  InfoItem(title: "ISRC", value: "${song.extras!['isrc']}"),
                if (streamInfo["label"] != null)
                  InfoItem(title: "Format", value: "${streamInfo["label"]}"),
                if (streamInfo["sampleRate"] != null)
                  InfoItem(
                      title: "Sample rate",
                      value: "${streamInfo["sampleRate"]} Hz"),
                if (streamInfo["bitDepth"] != null)
                  InfoItem(
                      title: "Bit depth",
                      value: "${streamInfo["bitDepth"]} bit"),
                InfoItem(
                    title: "loudnessDb".tr,
                    value: "${streamInfo["loudnessDb"] ?? "NA"}"),
              ],
            )),
            const Divider(),
            ListTile(
              dense: true,
              leading: const Icon(Icons.search),
              title: const Text('Correct source match'),
              subtitle: const Text(
                  'Pick the right version when the automatic match is wrong'),
              onTap: () {
                showMatchCorrectionDialog(context, song);
              },
            ),
            const Divider(),
            SizedBox(
              height: 50,
              child: Align(
                alignment: Alignment.center,
                child: InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10.0, horizontal: 25),
                      child: Text("close".tr),
                    )),
              ),
            )
          ],
        ),
      ),
    );
  }

  Map<dynamic, dynamic> _getStreamInfo(String id) {
    Map<dynamic, dynamic> tempstreamInfo;
    final nullVal = {
      "audioCodec": null,
      "bitrate": null,
      "loudnessDb": null,
      "approxDurationMs": null,
      "label": null,
      "sampleRate": null,
      "bitDepth": null
    };
    if (Hive.box("SongDownloads").containsKey(id)) {
      final song = Hive.box("SongDownloads").get(id);

      tempstreamInfo =
          song["streamInfo"] == null ? nullVal : song["streamInfo"][1];
    } else {
      final dbStreamData = Hive.box("SongsUrlCache").get(id);
      tempstreamInfo = dbStreamData != null &&
              dbStreamData.runtimeType.toString().contains("Map")
          ? dbStreamData[Hive.box('AppPrefs').get('streamingQuality') == 0
              ? 'lowQualityAudio'
              : "highQualityAudio"]
          : nullVal;
    }
    return tempstreamInfo;
  }
}

class InfoItem extends StatelessWidget {
  final String title;
  final String value;
  const InfoItem({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            textAlign: TextAlign.start,
          ),
          TextSelectionTheme(
            data: Theme.of(context).textSelectionTheme,
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          )
        ],
      ),
    );
  }
}
