import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../models/media_Item_builder.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import 'music_service.dart';

/// Builds personalised song recommendations by combining the user's liked
/// songs (LIBFAV) with play-count data (PlaybackStats) and fetching
/// related content from YouTube Music.
///
/// The algorithm:
/// 1. Read liked songs and play-count stats.
/// 2. Score each liked song (liked bonus + play-count weight).
/// 3. Pick the top-N seed songs.
/// 4. For each seed, fetch YouTube Music "related content".
/// 5. Merge, deduplicate, and rank results by how many seeds they are
///    related to (more seeds → higher relevance).
/// 6. Filter out songs already in the user's liked list.
class RecommendationService extends GetxService {
  /// Number of seed songs to use for the related-content look-ups.
  static const int _seedCount = 8;

  /// Weight added to every liked song regardless of play count.
  static const double _likedBonus = 5.0;

  /// Multiplier applied to play count when computing the taste score.
  static const double _playCountWeight = 1.0;

  /// Maximum number of recommendation results to return.
  static const int _maxResults = 24;

  final MusicServices _musicServices = Get.find<MusicServices>();

  /// Compute a taste-scored list of seed songs from the user's library.
  ///
  /// Each entry in the returned list is a `MediaItem` converted from the
  /// LIBFAV JSON, scored by `likedBonus + playCount * playCountWeight`.
  Future<List<_ScoredSong>> _buildTasteProfile() async {
    final favBox = await Hive.openBox('LIBFAV');
    final statsBox = await Hive.openBox('PlaybackStats');

    final scored = <_ScoredSong>[];

    for (final key in favBox.keys) {
      final json = favBox.get(key);
      if (json == null || json is! Map) continue;
      try {
        final song = MediaItemBuilder.fromJson(json);
        final playCount = (statsBox.get(song.id)?['playCount'] as int?) ?? 0;
        final score = _likedBonus + playCount * _playCountWeight;
        scored.add(_ScoredSong(song: song, score: score));
      } catch (_) {
        // Skip malformed entries.
      }
    }

    // Sort by score descending (highest preference first).
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  /// Fetch content related to [song] from YouTube Music.
  /// Fetch content related to [song] from YouTube Music.
  ///
  /// Uses YouTube Music's song radio (watch playlist) which returns true musical
  /// peers (genre, style, artists), and supplements with related browse sections.
  Future<List<MediaItem>> _fetchRelated(MediaItem song) async {
    try {
      final songs = <MediaItem>[];

      // 1. Fetch song radio (watch playlist) — YouTube Music's direct musical peers
      try {
        final watch = await _musicServices.getWatchPlaylist(
            videoId: song.id, limit: 20, radio: true);
        if (watch['tracks'] != null && watch['tracks'] is List) {
          for (final item in watch['tracks']) {
            if (item is MediaItem) songs.add(item);
          }
        }
      } catch (_) {}

      // 2. Supplement with related browse sections if available
      if (songs.length < 5) {
        try {
          final hlCode =
              Get.find<SettingsScreenController>().currentAppLanguageCode.value;
          final related =
              await _musicServices.getContentRelatedToSong(song.id, hlCode);
          if (related != null && related is List) {
            for (final section in related) {
              if (section is Map && section['contents'] is List) {
                for (final item in section['contents']) {
                  if (item is MediaItem) songs.add(item);
                }
              }
            }
          }
        } catch (_) {}
      }

      return songs;
    } catch (_) {
      return [];
    }
  }

  /// Build the final recommendation list.
  ///
  /// Returns up to [_maxResults] `MediaItem` songs that are related to the
  /// user's taste profile but are **not** already in their liked list.
  Future<List<MediaItem>> getRecommendations() async {
    final profile = await _buildTasteProfile();
    if (profile.isEmpty) return [];

    // Pick top seed songs (up to [_seedCount]).
    final seeds = profile.take(_seedCount).toList();

    // Map from videoId → score (how many seeds this song is related to).
    final relevanceMap = <String, double>{};
    // Map from videoId → MediaItem.
    final songMap = <String, MediaItem>{};

    // Fetch related content for each seed in parallel.
    final futures = seeds.map((s) => _fetchRelated(s.song));
    final results = await Future.wait(futures);

    // Seed score for weighting (higher-ranked seeds contribute more).
    for (var i = 0; i < seeds.length; i++) {
      final seedWeight = 1.0 + (seeds.length - i) / seeds.length;
      final related = results[i];
      for (final song in related) {
        final id = song.id;
        if (id.isEmpty) continue;

        relevanceMap[id] = (relevanceMap[id] ?? 0) + seedWeight;
        songMap[id] = song;
      }
    }

    // Build the set of already-liked videoIds to exclude.
    final favBox = await Hive.openBox('LIBFAV');
    final likedIds = <String>{};
    for (final key in favBox.keys) {
      likedIds.add(key.toString());
    }

    // Build the set of recently played videoIds to diversify results.
    final rpBox = await Hive.openBox('LIBRP');
    final recentIds = <String>{};
    for (final entry in rpBox.values) {
      if (entry is Map && entry['videoId'] != null) {
        recentIds.add(entry['videoId'].toString());
      }
    }

    // Build the set of seed videoIds to exclude (don't recommend seeds).
    final seedIds = <String>{for (final s in seeds) s.song.id};

    // Filter out liked, recently played, seeds, and empty IDs.
    final candidates = relevanceMap.entries
        .where((e) =>
            e.key.isNotEmpty &&
            !likedIds.contains(e.key) &&
            !recentIds.contains(e.key) &&
            !seedIds.contains(e.key))
        .toList();

    // Sort by relevance (more seeds → higher rank).
    candidates.sort((a, b) => b.value.compareTo(a.value));

    // Take top results.
    return candidates
        .take(_maxResults)
        .map((e) => songMap[e.key]!)
        .toList();
  }
}

/// Internal helper to pair a song with its taste score.
class _ScoredSong {
  final MediaItem song;
  final double score;
  const _ScoredSong({required this.song, required this.score});
}
