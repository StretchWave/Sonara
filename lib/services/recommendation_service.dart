import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../models/media_Item_builder.dart';
import '../ui/screens/Onboarding/language_selection_step.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '../utils/language_filter.dart';
import 'music_service.dart';

/// Builds personalised song recommendations by combining the user's liked
/// songs (LIBFAV), play-count data (PlaybackStats), selected music languages,
/// and favourite artists, then fetching related content from YouTube Music.
///
/// The algorithm:
/// 1. Read liked songs, play-count stats, favorite artists, and music languages.
/// 2. Score each liked song (liked bonus + play-count weight).
/// 3. Add synthetic seed songs for favorite artists and languages so new users
///    with no liked songs still receive personalized recommendations.
/// 4. Pick the top-N seed songs.
/// 5. For each seed, fetch YouTube Music related content in parallel.
/// 6. Merge and rank results by seed relevance.
/// 7. Apply bonus weights for songs matching favorite artists or selected languages.
/// 8. Filter out songs already in liked list, recently played, or seed set.
class RecommendationService extends GetxService {
  /// Number of seed songs to use for the related-content look-ups.
  static const int _seedCount = 10;

  /// Weight added to every liked song regardless of play count.
  static const double _likedBonus = 5.0;

  /// Multiplier applied to play count when computing the taste score.
  static const double _playCountWeight = 1.0;

  /// Base score assigned to synthetic seeds from user's favorite artists.
  static const double _artistPreferenceBonus = 8.0;

  /// Base score assigned to synthetic seeds from user's music languages.
  static const double _languagePreferenceBonus = 6.0;

  /// Maximum number of recommendation results to return.
  static const int _maxResults = 24;

  final MusicServices _musicServices = Get.find<MusicServices>();

  /// In-memory cache for artist top songs to avoid redundant network calls.
  final Map<String, List<MediaItem>> _artistSongsCache = {};

  /// In-memory cache for language top songs to avoid redundant network calls.
  final Map<String, List<MediaItem>> _langSongsCache = {};

  /// Fetches top songs for a user's favorite artist.
  Future<List<MediaItem>> _fetchArtistTopSongs(Map<String, dynamic> artist) async {
    final browseId = artist['browseId']?.toString() ?? '';
    final name = artist['name']?.toString() ?? '';
    final cacheKey = browseId.isNotEmpty ? browseId : name;
    if (cacheKey.isEmpty) return [];
    if (_artistSongsCache.containsKey(cacheKey)) {
      return _artistSongsCache[cacheKey]!;
    }

    final songs = <MediaItem>[];
    try {
      if (browseId.isNotEmpty && browseId.startsWith('UC')) {
        final artistData = await _musicServices.getArtist(browseId);
        final songsSection = artistData['Songs'];
        if (songsSection is Map && songsSection['content'] is List) {
          for (final item in songsSection['content']) {
            if (item is MediaItem) songs.add(item);
          }
        }
      }
    } catch (_) {}

    // Fallback: search by artist name if browseId did not yield songs
    if (songs.isEmpty && name.isNotEmpty) {
      try {
        final searchResults =
            await _musicServices.search('$name songs', filter: 'songs');
        final list = searchResults['Songs'] ?? searchResults['songs'];
        if (list is List) {
          for (final item in list) {
            if (item is MediaItem) songs.add(item);
          }
        }
      } catch (_) {}
    }

    final topSongs = songs.take(3).toList();
    _artistSongsCache[cacheKey] = topSongs;
    return topSongs;
  }

  /// Fetches top songs for a language code as fallback/supplementary seeds.
  Future<List<MediaItem>> _fetchLanguageTopSongs(String langCode) async {
    if (_langSongsCache.containsKey(langCode)) {
      return _langSongsCache[langCode]!;
    }
    final langName = musicLanguageMap[langCode] ?? langCode;
    final songs = <MediaItem>[];
    try {
      final searchResults =
          await _musicServices.search('$langName top songs', filter: 'songs');
      final list = searchResults['Songs'] ??
          searchResults['songs'] ??
          searchResults['Videos'] ??
          searchResults['videos'];
      if (list is List) {
        for (final item in list) {
          if (item is MediaItem) songs.add(item);
        }
      }
    } catch (_) {}

    final topSongs = songs.take(3).toList();
    _langSongsCache[langCode] = topSongs;
    return topSongs;
  }

  /// In-memory cache for global seed songs.
  final List<MediaItem> _globalSeedsCache = [];

  /// Fetches global popular songs to use as seeds when no user history or preferences exist.
  Future<List<MediaItem>> _fetchGlobalSeeds() async {
    if (_globalSeedsCache.isNotEmpty) return _globalSeedsCache;
    try {
      final searchResults =
          await _musicServices.search('global top hits', filter: 'songs');
      final list = searchResults['Songs'] ??
          searchResults['songs'] ??
          searchResults['Videos'] ??
          searchResults['videos'];
      if (list is List) {
        for (final item in list) {
          if (item is MediaItem) _globalSeedsCache.add(item);
        }
      }
    } catch (_) {}
    return _globalSeedsCache;
  }

  /// Compute a taste-scored list of seed songs from the user's library
  /// and preferences (favorite artists + music languages).
  Future<List<_ScoredSong>> _buildTasteProfile() async {
    final favBox = await Hive.openBox('LIBFAV');
    final statsBox = await Hive.openBox('PlaybackStats');
    final appPrefs = Hive.box('AppPrefs');

    final storedLangs = appPrefs.get('musicLanguages');
    final userLangs = (storedLangs is List)
        ? storedLangs.map((e) => e.toString()).toList()
        : <String>[];

    final storedArtists = appPrefs.get('favoriteArtists');
    final artistNames = <String>{};
    if (storedArtists is List) {
      for (final a in storedArtists) {
        if (a is Map && a['name'] != null) {
          artistNames.add(a['name'].toString().toLowerCase().trim());
        }
      }
    }

    final scored = <_ScoredSong>[];
    final seenIds = <String>{};

    // 1. Liked songs scored by play count, filtered by allowed languages
    for (final key in favBox.keys) {
      final json = favBox.get(key);
      if (json == null || json is! Map) continue;
      try {
        final song = MediaItemBuilder.fromJson(json);

        // Disqualify songs in unselected languages so they never become seeds
        if (userLangs.isNotEmpty &&
            !LanguageFilter.isSongAllowed(
              title: song.title,
              artist: song.artist ?? '',
              allowedLanguages: userLangs,
              favoriteArtistNames: artistNames,
            )) {
          continue;
        }

        final playCount = (statsBox.get(song.id)?['playCount'] as int?) ?? 0;
        final score = _likedBonus + playCount * _playCountWeight;
        scored.add(_ScoredSong(song: song, score: score));
        seenIds.add(song.id);
      } catch (_) {
        // Skip malformed entries.
      }
    }

    // 2. Favorite artists (synthetic seeds)
    if (storedArtists is List && storedArtists.isNotEmpty) {
      final artistList = storedArtists
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .take(4)
          .toList();

      for (final artist in artistList) {
        try {
          final topSongs = await _fetchArtistTopSongs(artist);
          for (final song in topSongs) {
            if (!seenIds.contains(song.id)) {
              seenIds.add(song.id);
              scored.add(
                _ScoredSong(song: song, score: _artistPreferenceBonus),
              );
            }
          }
        } catch (_) {}
      }
    }

    // 3. Music languages (if seed count is still low)
    if (scored.length < _seedCount) {
      if (userLangs.isNotEmpty) {
        final langList = userLangs.take(3).toList();
        for (final lang in langList) {
          try {
            final langSongs = await _fetchLanguageTopSongs(lang);
            for (final song in langSongs) {
              if (!seenIds.contains(song.id)) {
                seenIds.add(song.id);
                scored.add(
                  _ScoredSong(song: song, score: _languagePreferenceBonus),
                );
              }
            }
          } catch (_) {}
        }
      }
    }

    // 4. Global fallback for guest users or users who skipped preferences
    if (scored.isEmpty) {
      try {
        final globalSeeds = await _fetchGlobalSeeds();
        for (final song in globalSeeds.take(_seedCount)) {
          if (!seenIds.contains(song.id)) {
            seenIds.add(song.id);
            scored.add(_ScoredSong(song: song, score: 5.0));
          }
        }
      } catch (_) {}
    }

    // Sort by score descending
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Diversify seeds across distinct artists from the user's library
    // to prevent a single artist/cluster from dominating all seeds.
    final diversified = <_ScoredSong>[];
    final artistSongCounts = <String, int>{};
    final secondary = <_ScoredSong>[];

    for (final item in scored) {
      final artist = item.song.artist?.toLowerCase().trim() ?? '';
      final count = artistSongCounts[artist] ?? 0;
      if (count < 2) {
        diversified.add(item);
        artistSongCounts[artist] = count + 1;
      } else {
        secondary.add(item);
      }
    }
    diversified.addAll(secondary);

    return diversified;
  }

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

    // Read user preference metadata for candidate boosting and language filtering
    final appPrefs = Hive.box('AppPrefs');
    final storedArtists = appPrefs.get('favoriteArtists');
    final artistNames = <String>{};
    if (storedArtists is List) {
      for (final a in storedArtists) {
        if (a is Map && a['name'] != null) {
          artistNames.add(a['name'].toString().toLowerCase().trim());
        }
      }
    }

    final storedLangs = appPrefs.get('musicLanguages');
    final userLangs = <String>[];
    if (storedLangs is List) {
      userLangs.addAll(storedLangs.map((e) => e.toString()));
    }

    // Disqualify candidates that violate selected languages, and apply boosts
    final disqualifiedIds = <String>{};
    for (final entry in songMap.entries) {
      final song = entry.value;
      final artist = song.artist?.toLowerCase() ?? '';
      final title = song.title;

      // Disqualify any song that violates the user's selected music languages
      if (userLangs.isNotEmpty &&
          !LanguageFilter.isSongAllowed(
            title: title,
            artist: song.artist ?? '',
            allowedLanguages: userLangs,
            favoriteArtistNames: artistNames,
          )) {
        disqualifiedIds.add(entry.key);
        continue;
      }

      // Artist boost (+3.0)
      if (artistNames.isNotEmpty) {
        for (final favName in artistNames) {
          if (favName.isNotEmpty &&
              (artist.contains(favName) || favName.contains(artist))) {
            relevanceMap[entry.key] = (relevanceMap[entry.key] ?? 0) + 3.0;
            break;
          }
        }
      }

      // Language boost (+2.0)
      if (userLangs.isNotEmpty) {
        for (final code in userLangs) {
          if (LanguageFilter.matchesLanguage(artist, code) ||
              LanguageFilter.matchesLanguage(title, code)) {
            relevanceMap[entry.key] = (relevanceMap[entry.key] ?? 0) + 2.0;
            break;
          }
        }
      }
    }

    for (final id in disqualifiedIds) {
      relevanceMap.remove(id);
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

    // Filter out liked, recently played, seeds, disqualified, and empty IDs.
    final candidates = relevanceMap.entries
        .where((e) =>
            e.key.isNotEmpty &&
            !disqualifiedIds.contains(e.key) &&
            !likedIds.contains(e.key) &&
            !recentIds.contains(e.key) &&
            !seedIds.contains(e.key))
        .toList();

    // Sort by relevance (more seeds + preference boost → higher rank).
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
