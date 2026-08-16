import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../models/media_Item_builder.dart';
import '../utils/helper.dart';

/// Tracks listening statistics (play counts, listening time, play history)
/// by observing the [AudioHandler] playback streams.
///
/// Data is persisted in two Hive boxes:
/// - `PlaybackStats`   : per-song aggregates (plays, listened ms, first/last play)
/// - `PlaybackHistory` : one entry per play session (song snapshot + listened ms)
///
/// This service powers the "Listening statistics" screen and the yearly
/// Wrapped-style recap.
class PlaybackStatsService extends GetxService {
  static const String statsBoxName = 'PlaybackStats';
  static const String historyBoxName = 'PlaybackHistory';

  Box<dynamic>? _statsBox;
  Box<dynamic>? _historyBox;

  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<PlaybackState>? _playbackStateSub;
  StreamSubscription<Duration>? _positionSub;

  MediaItem? _currentSong;
  bool _isPlaying = false;
  Duration? _lastPosition;
  int _currentListenMs = 0;

  /// Total number of play sessions recorded (all time).
  final totalPlays = 0.obs;

  /// Total listening time in milliseconds (all time).
  final totalListenMs = 0.obs;

  @override
  void onInit() {
    super.onInit();
    _loadTotals();
    _listen();
  }

  Future<void> _loadTotals() async {
    final statsBox = await _getStatsBox();
    final historyBox = await _getHistoryBox();
    int plays = 0;
    int listenMs = 0;
    for (final value in statsBox.values) {
      plays += (value['playCount'] as int?) ?? 0;
      listenMs += (value['listenMs'] as int?) ?? 0;
    }
    totalPlays.value = plays;
    totalListenMs.value = listenMs;
    _historyBox = historyBox;
  }

  Future<Box<dynamic>> _getStatsBox() async {
    _statsBox ??= await Hive.openBox(statsBoxName);
    return _statsBox!;
  }

  Future<Box<dynamic>> _getHistoryBox() async {
    _historyBox ??= await Hive.openBox(historyBoxName);
    return _historyBox!;
  }

  void _listen() {
    final handler = Get.find<AudioHandler>();
    _mediaItemSub = handler.mediaItem.listen((song) {
      _finalizeCurrentPlay();
      _currentSong = song;
      _lastPosition = Duration.zero;
      _currentListenMs = 0;
    });
    _playbackStateSub = handler.playbackState.listen((state) {
      _isPlaying = state.playing;
      if (!_isPlaying) {
        _lastPosition = null;
      }
    });
    _positionSub = AudioService.position.listen((position) {
      if (!_isPlaying || _currentSong == null) {
        _lastPosition = null;
        return;
      }
      final last = _lastPosition;
      _lastPosition = position;
      if (last != null && position > last) {
        _currentListenMs += position.inMilliseconds - last.inMilliseconds;
      }
    });
  }

  /// Commits the currently playing song (if any) to the stats/history boxes.
  Future<void> _finalizeCurrentPlay() async {
    final song = _currentSong;
    if (song == null) return;

    final durationMs = song.duration?.inMilliseconds ?? 0;
    var listenedMs = _currentListenMs;
    if (durationMs > 0 && listenedMs > durationMs) {
      listenedMs = durationMs;
    }

    if (listenedMs > 0) {
      await _record(song, listenedMs);
    }
    _currentSong = null;
    _currentListenMs = 0;
  }

  Future<void> _record(MediaItem song, int listenedMs) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final statsBox = await _getStatsBox();
      final historyBox = await _getHistoryBox();

      final existing = statsBox.get(song.id);
      final Map<dynamic, dynamic> entry;
      if (existing is Map) {
        entry = Map<dynamic, dynamic>.from(existing);
      } else {
        entry = {
          'id': song.id,
          'title': song.title,
          'artist': song.artist,
          'album': song.album,
          'artUri': song.artUri?.toString(),
          'mediaItemJson': MediaItemBuilder.toJson(song),
          'firstPlayedAt': now,
        };
      }
      entry['playCount'] = ((entry['playCount'] as int?) ?? 0) + 1;
      entry['listenMs'] = ((entry['listenMs'] as int?) ?? 0) + listenedMs;
      entry['lastPlayedAt'] = now;
      await statsBox.put(song.id, Map<String, dynamic>.from(entry));
      await _syncTopPlayedBox(statsBox);

      await historyBox.put(
        '${song.id}_$now',
        {
          'songId': song.id,
          'title': song.title,
          'artist': song.artist,
          'album': song.album,
          'playedAt': now,
          'listenMs': listenedMs,
        },
      );

      totalPlays.value += 1;
      totalListenMs.value += listenedMs;
    } catch (e) {
      printERROR("Failed to record playback stats: $e");
    }
  }

  /// All-time per-song aggregates, most played first.
  Future<List<Map<String, dynamic>>> getTopSongs({int limit = 50}) async {
    final statsBox = await _getStatsBox();
    final songs = statsBox.values.whereType<Map>().toList();
    songs.sort((a, b) =>
        ((b['playCount'] as int?) ?? 0).compareTo((a['playCount'] as int?) ?? 0));
    return songs.take(limit).map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Play history entries for the given year (or all time if [year] is null),
  /// newest first.
  Future<List<Map<String, dynamic>>> getHistory({int? year}) async {
    final historyBox = await _getHistoryBox();
    final entries = historyBox.values.whereType<Map>().toList();
    if (year != null) {
      entries.removeWhere((e) {
        final playedAt = DateTime.fromMillisecondsSinceEpoch(
            (e['playedAt'] as int?) ?? 0);
        return playedAt.year != year;
      });
    }
    entries.sort((a, b) =>
        ((b['playedAt'] as int?) ?? 0).compareTo((a['playedAt'] as int?) ?? 0));
    return entries.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Play counts per calendar day, keyed by "YYYY-MM-DD", for the given
  /// year (or all time if [year] is null).
  Future<Map<String, int>> getDailyActivity({int? year}) async {
    final historyBox = await _getHistoryBox();
    final daily = <String, int>{};
    for (final value in historyBox.values) {
      if (value is! Map) continue;
      final playedAt = DateTime.fromMillisecondsSinceEpoch(
          ((value['playedAt'] as int?) ?? 0));
      if (year != null && playedAt.year != year) continue;
      final key =
          '${playedAt.year}-${playedAt.month.toString().padLeft(2, '0')}-${playedAt.day.toString().padLeft(2, '0')}';
      daily[key] = (daily[key] ?? 0) + 1;
    }
    return daily;
  }

  /// Keeps the smart "Top played" playlist (LIBTP box) in sync with the
  /// current top 100 songs.
  Future<void> _syncTopPlayedBox(Box<dynamic> statsBox) async {
    try {
      final songs = statsBox.values.whereType<Map>().toList()
        ..sort((a, b) =>
            ((b['playCount'] as int?) ?? 0).compareTo((a['playCount'] as int?) ?? 0));
      final box = await Hive.openBox("LIBTP");
      await box.clear();
      for (final song in songs.take(100)) {
        final json = song['mediaItemJson'];
        if (json is Map) {
          await box.put(song['id'], json);
        }
      }
      await box.close();
    } catch (e) {
      printERROR("Failed to sync top played box: $e");
    }
  }

  /// Years that contain at least one play entry, sorted descending.
  Future<List<int>> getAvailableYears() async {
    final historyBox = await _getHistoryBox();
    final years = <int>{};
    for (final value in historyBox.values) {
      if (value is Map) {
        years.add(DateTime.fromMillisecondsSinceEpoch(
                ((value['playedAt'] as int?) ?? 0))
            .year);
      }
    }
    final list = years.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// Clears all recorded statistics.
  Future<void> clearStats() async {
    final statsBox = await _getStatsBox();
    final historyBox = await _getHistoryBox();
    await statsBox.clear();
    await historyBox.clear();
    totalPlays.value = 0;
    totalListenMs.value = 0;
    final topPlayedBox = await Hive.openBox("LIBTP");
    await topPlayedBox.clear();
    await topPlayedBox.close();
  }

  @override
  void onClose() {
    _mediaItemSub?.cancel();
    _playbackStateSub?.cancel();
    _positionSub?.cancel();
    super.onClose();
  }
}
