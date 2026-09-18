import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/ui/player/player_controller.dart';
import '../../../utils/update_check_flag_file.dart';
import '../../../utils/helper.dart';
import '/models/album.dart';
import '/models/playlist.dart';
import '/models/quick_picks.dart';
import '/services/music_service.dart';
import '/services/recommendation_service.dart';
import '../../../utils/language_filter.dart';
import '../Onboarding/language_selection_step.dart';
import '../Settings/settings_screen_controller.dart';
import '/ui/widgets/new_version_dialog.dart';

class HomeScreenController extends GetxController {
  final MusicServices _musicServices = Get.find<MusicServices>();
  final isContentFetched = false.obs;
  final tabIndex = 0.obs;
  final networkError = false.obs;
  final quickPicks = QuickPicks([]).obs;
  final middleContent = [].obs;
  final fixedContent = [].obs;
  final showVersionDialog = true.obs;
  //isHomeScreenOnTop var only useful if bottom nav enabled
  final isHomeSreenOnTop = true.obs;
  final List<ScrollController> contentScrollControllers = [];
  bool reverseAnimationtransiton = false;

  @override
  onInit() {
    super.onInit();
    loadContent();
    if (updateCheckFlag) _checkNewVersion();
  }

  Future<void> loadContent() async {
    final box = Hive.box("AppPrefs");
    final isCachedHomeScreenDataEnabled =
        box.get("cacheHomeScreenData") ?? true;
    if (isCachedHomeScreenDataEnabled) {
      final loaded = await loadContentFromDb();

      if (loaded) {
        final currTimeSecsDiff = DateTime.now().millisecondsSinceEpoch -
            (box.get("homeScreenDataTime") ??
                DateTime.now().millisecondsSinceEpoch);
        if (currTimeSecsDiff / 1000 > 3600 * 8) {
          loadContentFromNetwork(silent: true);
        }
      } else {
        loadContentFromNetwork();
      }
    } else {
      loadContentFromNetwork();
    }
  }

  Future<bool> loadContentFromDb() async {
    final homeScreenData = await Hive.openBox("homeScreenData");
    if (homeScreenData.keys.isNotEmpty) {
      final String quickPicksType =
          homeScreenData.get("quickPicksType") ?? "";
      // Invalidate stale regional cache
      if (quickPicksType == "Quick picks" ||
          quickPicksType == "Trending" ||
          quickPicksType == "Top music videos") {
        return false;
      }

      final box = Hive.box("AppPrefs");
      final storedLangs = box.get("musicLanguages");
      final userLangs = (storedLangs is List)
          ? storedLangs.map((e) => e.toString()).toList()
          : <String>[];
      if (userLangs.isNotEmpty) {
        final List fixedContentData = homeScreenData.get("fixedContent") ?? [];
        final hasIndian =
            userLangs.any((l) => indianLanguageCodes.contains(l));
        for (final item in fixedContentData) {
          if (item is Map) {
            final title = item["title"]?.toString() ?? "";
            if (!hasIndian &&
                LanguageFilter.matchesIndianRegionalMarkers(title)) {
              return false;
            }
            final scriptLang = LanguageFilter.detectScriptLanguage(title);
            if (scriptLang != null && !userLangs.contains(scriptLang)) {
              return false;
            }
          }
        }
      }
      final List quickPicksData = homeScreenData.get("quickPicks") ?? [];
      final List middleContentData = homeScreenData.get("middleContent") ?? [];
      final List fixedContentData = homeScreenData.get("fixedContent") ?? [];
      quickPicks.value = QuickPicks(
          quickPicksData.map((e) => MediaItemBuilder.fromJson(e)).toList(),
          title: quickPicksType);
      middleContent.value = middleContentData
          .map((e) => e["type"] == "Album Content"
              ? AlbumContent.fromJson(e)
              : PlaylistContent.fromJson(e))
          .toList();
      fixedContent.value = fixedContentData
          .map((e) => e["type"] == "Album Content"
              ? AlbumContent.fromJson(e)
              : PlaylistContent.fromJson(e))
          .toList();
      isContentFetched.value = true;
      printINFO("Loaded from offline db");
      return true;
    } else {
      return false;
    }
  }

  Future<void> loadContentFromNetwork({bool silent = false}) async {
    final box = Hive.box("AppPrefs");
    String contentType = box.get("discoverContentType") ?? "REC";
    // Migrate removed regional chart and quick picks types to REC
    if (contentType == "TR" || contentType == "TMV" || contentType == "QP") {
      contentType = "REC";
      box.put("discoverContentType", "REC");
    }

    networkError.value = false;
    try {
      List middleContentTemp = [];
      final homeContentListMap = await _musicServices.getHome(
          limit:
              Get.find<SettingsScreenController>().noOfHomeScreenContent.value);

      // Remove any IP-based regional "Quick picks" shelf from home content
      homeContentListMap.removeWhere((element) =>
          element is Map && element['title'] == "Quick picks");

      if (contentType == "BOLI") {
        try {
          final songId = box.get("recentSongId");
          if (songId != null) {
            final rel = (await _musicServices.getContentRelatedToSong(
                songId, getContentHlCode()));
            final con = rel.removeAt(0);
            quickPicks.value =
                QuickPicks(List<MediaItem>.from(con["contents"]));
            middleContentTemp.addAll(rel);
          }
        } catch (e) {
          printERROR(
              "Seems Based on last interaction content currently not available!");
        }
      } else {
        // Default to personalized REC
        try {
          final recService = Get.find<RecommendationService>();
          final recommendations = await recService.getRecommendations();
          if (recommendations.isNotEmpty) {
            quickPicks.value = QuickPicks(recommendations,
                title: "discover".tr);
          }
        } catch (e) {
          printERROR("Recommendations unavailable: $e");
        }
      }

      middleContent.value = _setContentList(middleContentTemp);
      final filteredShelves = _setContentList(homeContentListMap);

      // If YouTube's IP-geolocated shelves yielded few language-appropriate
      // shelves, supplement with personalized shelves (favorite artists & language hits)
      if (filteredShelves.length < 3) {
        final supplementary = await _fetchPersonalizedSupplementaryShelves();
        filteredShelves.addAll(supplementary);
      }

      fixedContent.value = filteredShelves;

      isContentFetched.value = true;

      // set home content last update time
      cachedHomeScreenData(updateAll: true);
      await Hive.box("AppPrefs")
          .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
      // ignore: unused_catch_stack
    } on NetworkError catch (r, e) {
      printERROR("Home Content not loaded due to ${r.message}");
      await Future.delayed(const Duration(seconds: 1));
      networkError.value = !silent;
    }
  }

  Future<List<dynamic>> _fetchPersonalizedSupplementaryShelves() async {
    final supplementary = [];
    final box = Hive.box("AppPrefs");
    final storedLangs = box.get("musicLanguages");
    final userLangs = (storedLangs is List)
        ? storedLangs.map((e) => e.toString()).toList()
        : <String>[];

    final storedArtists = box.get("favoriteArtists");
    final artistNames = <String>{};
    if (storedArtists is List) {
      for (final a in storedArtists) {
        if (a is Map && a['name'] != null) {
          artistNames.add(a['name'].toString().toLowerCase().trim());
        }
      }
    }

    // 1. Shelves for favorite artists
    if (storedArtists is List && storedArtists.isNotEmpty) {
      for (final a in storedArtists.take(2)) {
        if (a is Map) {
          final browseId = a['browseId']?.toString() ?? '';
          final name = a['name']?.toString() ?? '';
          if (browseId.isNotEmpty && browseId.startsWith('UC')) {
            try {
              final artistData = await _musicServices.getArtist(browseId);
              final albumsSection = artistData['Albums'];
              if (albumsSection is Map && albumsSection['content'] is List) {
                final albumList = (albumsSection['content'] as List)
                    .whereType<Album>()
                    .take(10)
                    .toList();
                if (albumList.length >= 2) {
                  supplementary.add(AlbumContent(
                    albumList: albumList,
                    title: "Albums by $name",
                  ));
                }
              }
            } catch (_) {}
          }
        }
      }
    }

    // 2. Curated playlists for user's selected languages
    if (userLangs.isNotEmpty) {
      try {
        final isEnglish = userLangs.contains('en');
        final query = isEnglish
            ? "Today's Top Hits"
            : "${musicLanguageMap[userLangs.first] ?? ''} top hits";
        final searchRes =
            await _musicServices.search(query, filter: 'featured_playlists');
        final playlists = searchRes['Featured playlists'] ??
            searchRes['Community playlists'];
        if (playlists is List) {
          final validPlaylists = playlists
              .whereType<Playlist>()
              .where((p) => LanguageFilter.isContentAllowed(
                    title: p.title,
                    subtitle: p.description,
                    allowedLanguages: userLangs,
                    favoriteArtistNames: artistNames,
                  ))
              .take(10)
              .toList();
          if (validPlaylists.length >= 2) {
            supplementary.add(PlaylistContent(
              playlistList: validPlaylists,
              title: isEnglish ? "Top Global Hits" : "Top Hits",
            ));
          }
        }
      } catch (_) {}
    }

    return supplementary;
  }

  List _setContentList(
    List<dynamic> contents,
  ) {
    final box = Hive.box("AppPrefs");
    final storedLangs = box.get("musicLanguages");
    final userLangs = (storedLangs is List)
        ? storedLangs.map((e) => e.toString()).toList()
        : <String>[];

    final storedArtists = box.get("favoriteArtists");
    final artistNames = <String>{};
    if (storedArtists is List) {
      for (final a in storedArtists) {
        if (a is Map && a['name'] != null) {
          artistNames.add(a['name'].toString().toLowerCase().trim());
        }
      }
    }

    List contentTemp = [];
    for (var content in contents) {
      if (content is! Map || content["contents"] == null) continue;
      final rawItems = content["contents"];
      if (rawItems is! List || rawItems.isEmpty) continue;

      final shelfTitle = content["title"]?.toString() ?? "";

      // Discard entire shelf if the title indicates an unselected regional language
      if (userLangs.isNotEmpty) {
        final hasIndian =
            userLangs.any((l) => indianLanguageCodes.contains(l));
        if (!hasIndian &&
            LanguageFilter.matchesIndianRegionalMarkers(shelfTitle)) {
          continue;
        }
        final scriptLang = LanguageFilter.detectScriptLanguage(shelfTitle);
        if (scriptLang != null && !userLangs.contains(scriptLang)) {
          continue;
        }
      }

      if (rawItems[0] is Playlist) {
        final filteredPlaylists = rawItems.whereType<Playlist>().where((p) {
          if (userLangs.isEmpty) return true;
          return LanguageFilter.isContentAllowed(
            title: p.title,
            subtitle: p.description,
            allowedLanguages: userLangs,
            favoriteArtistNames: artistNames,
          );
        }).toList();

        if (filteredPlaylists.length >= 2) {
          contentTemp.add(PlaylistContent(
            playlistList: filteredPlaylists,
            title: shelfTitle,
          ));
        }
      } else if (rawItems[0] is Album) {
        final filteredAlbums = rawItems.whereType<Album>().where((a) {
          if (userLangs.isEmpty) return true;
          final artistSubtitle = (a.artists != null && a.artists!.isNotEmpty)
              ? a.artists![0]['name']?.toString()
              : '';
          return LanguageFilter.isContentAllowed(
            title: a.title,
            subtitle: artistSubtitle,
            allowedLanguages: userLangs,
            favoriteArtistNames: artistNames,
          );
        }).toList();

        if (filteredAlbums.length >= 2) {
          contentTemp.add(AlbumContent(
            albumList: filteredAlbums,
            title: shelfTitle,
          ));
        }
      }
    }
    return contentTemp;
  }

  Future<void> changeDiscoverContent(dynamic val, {String? songId}) async {
    QuickPicks? quickPicks_;
    if (val == "REC" || val == 'QP') {
      try {
        final recService = Get.find<RecommendationService>();
        final recommendations = await recService.getRecommendations();
        if (recommendations.isNotEmpty) {
          quickPicks_ = QuickPicks(recommendations,
              title: "discover".tr);
        }
      } catch (e) {
        printERROR("Recommendations unavailable: $e");
      }
    } else {
      songId ??= Hive.box("AppPrefs").get("recentSongId");
      if (songId != null) {
        try {
          final value = await _musicServices.getContentRelatedToSong(
              songId, getContentHlCode());
          middleContent.value = _setContentList(value);
          if (value.isNotEmpty && (value[0]['title']).contains("like")) {
            quickPicks_ =
                QuickPicks(List<MediaItem>.from(value[0]["contents"]));
            Hive.box("AppPrefs").put("recentSongId", songId);
          }
          // ignore: empty_catches
        } catch (e) {}
      }
    }
    if (quickPicks_ == null) return;

    quickPicks.value = quickPicks_;

    // set home content last update time
    cachedHomeScreenData(updateQuickPicksNMiddleContent: true);
    await Hive.box("AppPrefs")
        .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
  }

  /// Reset the REC refresh cooldown, e.g. when the user manually picks
  /// "Recommendations" in settings, so it refreshes immediately.
  void resetRecommendationsCooldown() {
    _lastRecommendationsRefresh = null;
  }

  /// Minimum interval between automatic recommendation (REC) refreshes
  /// triggered by song plays, to avoid hammering the network on every
  /// single play.
  static const Duration _recommendationsRefreshCooldown = Duration(minutes: 10);

  DateTime? _lastRecommendationsRefresh;

  /// Keeps the home song selection in sync with the user's usage.
  ///
  /// Called whenever a song starts playing:
  /// - `BOLI` (Based on last interaction): rebuilds the quick picks from
  ///   the song that was just played.
  /// - `REC` (Recommendations): recomputes personalised recommendations
  ///   from the updated play stats, throttled by [_recommendationsRefreshCooldown].
  void refreshHomeContentOnSongPlay({String? songId}) {
    final contentType =
        Hive.box("AppPrefs").get("discoverContentType") ?? "REC";
    if (contentType == "BOLI") {
      changeDiscoverContent("BOLI", songId: songId);
    } else if (contentType == "REC") {
      final now = DateTime.now();
      if (_lastRecommendationsRefresh == null ||
          now.difference(_lastRecommendationsRefresh!) >=
              _recommendationsRefreshCooldown) {
        _lastRecommendationsRefresh = now;
        changeDiscoverContent("REC");
      }
    }
  }

  /// Called whenever a song is liked/unliked or when cloud favorites are synced.
  /// If the discover content type is REC (Based on Likes) or still on initial fallback,
  /// this immediately updates the recommendations so the home screen reflects user likes.
  void onFavoritesChanged() {
    final contentType =
        Hive.box("AppPrefs").get("discoverContentType") ?? "REC";
    if (contentType == "REC") {
      resetRecommendationsCooldown();
      changeDiscoverContent("REC");
    }
  }

  String getContentHlCode() {
    const List<String> unsupportedLangIds = ["ia", "ga", "fj", "eo"];
    final userLangId =
        Get.find<SettingsScreenController>().currentAppLanguageCode.value;
    return unsupportedLangIds.contains(userLangId) ? "en" : userLangId;
  }

  void onSideBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
  }

  void onBottonBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
  }

  void _checkNewVersion() {
    showVersionDialog.value =
        Hive.box("AppPrefs").get("newVersionVisibility") ?? true;
    if (showVersionDialog.isTrue) {
      newVersionCheck(Get.find<SettingsScreenController>().currentVersion)
          .then((value) {
        if (value) {
          showDialog(
              context: Get.context!,
              builder: (context) => const NewVersionDialog());
        }
      });
    }
  }

  void onChangeVersionVisibility(bool val) {
    Hive.box("AppPrefs").put("newVersionVisibility", !val);
    showVersionDialog.value = !val;
  }

  ///This is used to minimized bottom navigation bar by setting [isHomeSreenOnTop.value] to `true` and set mini player height.
  ///
  ///and applicable/useful if bottom nav enabled
  void whenHomeScreenOnTop() {
    if (Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
      final currentRoute = getCurrentRouteName();
      final isHomeOnTop = currentRoute == '/homeScreen';
      final isResultScreenOnTop = currentRoute == '/searchResultScreen';
      final playerCon = Get.find<PlayerController>();

      isHomeSreenOnTop.value = isHomeOnTop;

      // Set miniplayer height accordingly
      if (!playerCon.initFlagForPlayer) {
        if (isHomeOnTop) {
          playerCon.playerPanelMinHeight.value = 75.0;
        } else {
          Future.delayed(
              isResultScreenOnTop
                  ? const Duration(milliseconds: 300)
                  : Duration.zero, () {
            playerCon.playerPanelMinHeight.value =
                75.0 + Get.mediaQuery.viewPadding.bottom;
          });
        }
      }
    }
  }

  Future<void> cachedHomeScreenData({
    bool updateAll = false,
    bool updateQuickPicksNMiddleContent = false,
  }) async {
    if (Get.find<SettingsScreenController>().cacheHomeScreenData.isFalse ||
        quickPicks.value.songList.isEmpty) {
      return;
    }

    final homeScreenData = Hive.box("homeScreenData");

    if (updateQuickPicksNMiddleContent) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
      });
    } else if (updateAll) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
        "fixedContent": _getContentDataInJson(fixedContent.toList())
      });
    }

    printINFO("Saved Homescreen data data");
  }

  List<Map<String, dynamic>> _getContentDataInJson(List content,
      {bool isQuickPicks = false}) {
    if (isQuickPicks) {
      return content.toList().map((e) => MediaItemBuilder.toJson(e)).toList();
    } else {
      return content.map((e) {
        if (e.runtimeType == AlbumContent) {
          return (e as AlbumContent).toJson();
        } else {
          return (e as PlaylistContent).toJson();
        }
      }).toList();
    }
  }

  void disposeDetachedScrollControllers({bool disposeAll = false}) {
    final scrollControllersCopy = contentScrollControllers.toList();
    for (final contoller in scrollControllersCopy) {
      if (!contoller.hasClients || disposeAll) {
        contentScrollControllers.remove(contoller);
        contoller.dispose();
      }
    }
  }

  @override
  void dispose() {
    disposeDetachedScrollControllers(disposeAll: true);
    super.dispose();
  }
}
