import 'dart:core';
import 'package:flutter/services.dart';
import 'package:sonara/services/providers/song_query.dart';
import 'package:sonara/services/providers/stream_route_config.dart';
import 'package:sonara/services/providers/stream_router.dart';

//Not in use for now
// Future<List<String>?> getSongUrlFromPiped(String songId,
//     {String defaultUrl = "https://pipedapi.kavin.rocks"}) async {
//   try {
//     if (songId.substring(0, 4) == "MPED") {
//       songId = songId.substring(4);
//     }
//     final response = await Dio().get("$defaultUrl/streams/$songId");
//     if (response.statusCode == 200) {
//       final audioStream = response.data["audioStreams"] as List;
//       final x =
//           audioStream.firstWhere((item) => (item['itag'].toString() == "251"));
//
//       final y =
//           audioStream.firstWhere((item) => (item['itag'].toString() == "251"));
//
//       return [y['url'], x['url']];
//     } else {
//       return null;
//     }
//   } catch (e) {
//     return null;
//   }
// }

/// Fetches stream info for [songId] in a background isolate.
///
/// [configJson] carries the stream route configuration (providers, resolver
/// instances, match overrides) built in the main isolate, since Hive is not
/// available here. [songJson] optionally carries the song metadata needed
/// for cross-catalog matching.
Future<Map<String, dynamic>> getStreamInfo(
  String songId,
  dynamic token, {
  String configJson = '{}',
  Map<String, dynamic>? songJson,
}) async {
  if (songId.length >= 4 && songId.substring(0, 4) == "MPED") {
    songId = songId.substring(4);
  }
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final config = StreamRouteConfig.fromJsonString(configJson);
  final song = songJson == null ? null : SongQuery.fromJson(songJson);
  final playerResponse =
      await StreamRouter.build(config).fetch(songId, song: song);
  return playerResponse.hmStreamingData;
}
