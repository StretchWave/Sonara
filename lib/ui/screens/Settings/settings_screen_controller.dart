import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sonara/services/permission_service.dart';
import 'package:sonara/services/providers/stream_route_config.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';

import '../../../utils/update_check_flag_file.dart';
import '/services/piped_service.dart';
import '../Library/library_controller.dart';
import '../../widgets/snackbar.dart';
import '../../../utils/helper.dart';
import '/services/music_service.dart';
import '/ui/player/player_controller.dart';
import '../Home/home_screen_controller.dart';
import '/ui/utils/theme_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class SettingsScreenController extends GetxController {
  late String _supportDir;
  final cacheSongs = false.obs;
  final setBox = Hive.box("AppPrefs");
  final themeModetype = ThemeType.dynamic.obs;
  final skipSilenceEnabled = false.obs;
  final loudnessNormalizationEnabled = false.obs;
  final noOfHomeScreenContent = 3.obs;
  final streamingQuality = AudioQuality.High.obs;
  final playerUi = 0.obs;
  final slidableActionEnabled = true.obs;
  final isIgnoringBatteryOptimizations = false.obs;
  final autoOpenPlayer = false.obs;
  final discoverContentType = _initialDiscoverContentType().obs;
  final isNewVersionAvailable = false.obs;
  final isLinkedWithPiped = false.obs;
  final stopPlyabackOnSwipeAway = false.obs;
  final currentAppLanguageCode = "en".obs;
  final downloadLocationPath = "".obs;
  final exportLocationPath = "".obs;
  final downloadingFormat = "".obs;
  final autoDownloadFavoriteSongEnabled = false.obs;
  final qobuzEnabled = RxBool(Hive.box("AppPrefs").get("qobuzEnabled", defaultValue: false) == true);
  final qobuzInstances = RxString((Hive.box("AppPrefs").get("qobuzInstances", defaultValue: "") as String?) ?? "");
  final qobuzCountry = RxString((Hive.box("AppPrefs").get("qobuzCountry", defaultValue: "US") as String?) ?? "US");
  final qobuzQuality = RxInt(_prefInt('qobuzQuality', 27));
  final isTransitionAnimationDisabled = false.obs;
  final isBottomNavBarEnabled = false.obs;
  final spotifyAutoFetchLyrics = RxBool(Hive.box("AppPrefs")
      .get("spotifyAutoFetchLyrics", defaultValue: true) ==
      true);
  final spotifyAutoEnrichTracks = RxBool(Hive.box("AppPrefs")
      .get("spotifyAutoEnrichTracks", defaultValue: true) ==
      true);
  final backgroundPlayEnabled = true.obs;
  final keepScreenAwake = false.obs;
  final restorePlaybackSession = false.obs;
  final cacheHomeScreenData = true.obs;
  final galaxyOverlayEnabled = true.obs;

  /// UI density scale: 1.0 (native) down to 0.55 (ultra compact).
  final densityScale = 1.0.obs;
  final currentVersion = "V1.0.0";

  /// When false, all external media-button inputs (wired headset, BT AVRCP,
  /// lockscreen/notification, Auto/Wear OS) are gated. Persisted in Hive.
  /// Default true per spec. This is the single source of truth for all
  /// four gating points (session, commands, key dispatch).
  final inputControlEnabled =
      RxBool(Hive.box("AppPrefs").get("inputControlEnabled", defaultValue: true) == true);

  static const _inputControlChannel =
      MethodChannel("com.sonara.music/inputControl");

  void toggleInputControlEnabled(bool val) {
    inputControlEnabled.value = val;
    setBox.put("inputControlEnabled", val);
    // Notify AudioHandler for immediate playbackState refresh (controls empty).
    try {
      Get.find<AudioHandler>().customAction(
          "setInputControlEnabled", {"enabled": val});
    } catch (_) {}
    // Sync to native InputControlManager (wired key dispatch gating).
    _inputControlChannel.invokeMethod("setInputControlEnabled", {"enabled": val}).catchError((_) {});
  }

  Future<void> _syncInputControlToNative() async {
    try {
      await _inputControlChannel.invokeMethod(
          "setInputControlEnabled", {"enabled": inputControlEnabled.value});
    } catch (_) {}
    try {
      Get.find<AudioHandler>().customAction(
          "setInputControlEnabled", {"enabled": inputControlEnabled.value});
    } catch (_) {}
  }

  @override
  void onInit() {
    _setInitValue();
    if (updateCheckFlag) _checkNewVersion();
    _createInAppSongDownDir();
    // Ensure native side and AudioHandler reflect persisted toggle without restart.
    Future.delayed(const Duration(milliseconds: 500), _syncInputControlToNative);
    ever(inputControlEnabled, (bool val) => _syncInputControlToNative());
    super.onInit();
  }

  get currentVision => currentVersion;
  get isCurrentPathsupportDownDir =>
      "$_supportDir/Music" == downloadLocationPath.toString();
  String get supportDirPath => _supportDir;

  _checkNewVersion() {
    newVersionCheck(currentVersion)
        .then((value) => isNewVersionAvailable.value = value);
  }

  Future<String> _createInAppSongDownDir() async {
    _supportDir = (await getApplicationSupportDirectory()).path;
    final directory = Directory("$_supportDir/Music/");
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return "$_supportDir/Music";
  }

  static int _prefInt(String key, int fallback) {
    final value = Hive.box('AppPrefs').get(key, defaultValue: fallback);
    return value is int ? value : fallback;
  }

  static String _initialDiscoverContentType() {
    try {
      final box = Hive.box("AppPrefs");
      final stored = box.get('discoverContentType');
      if (stored == "TR" || stored == "TMV" || stored == "QP") {
        box.put('discoverContentType', "REC");
        return "REC";
      }
      return (stored == "BOLI" || stored == "REC") ? stored : "REC";
    } catch (_) {
      return "REC";
    }
  }

  void toggleQobuzEnabled(bool val) {
    qobuzEnabled.value = val;
    setBox.put("qobuzEnabled", val);
  }

  void changeQobuzInstances(String val) {
    qobuzInstances.value = val;
    setBox.put("qobuzInstances", val);
  }

  void changeQobuzCountry(String val) {
    qobuzCountry.value = val.toUpperCase();
    setBox.put("qobuzCountry", qobuzCountry.value);
  }

  void changeQobuzQuality(int val) {
    qobuzQuality.value = val;
    setBox.put("qobuzQuality", val);
  }

  final soundcloudEnabled = RxBool(
      Hive.box("AppPrefs").get("soundcloudEnabled", defaultValue: true) == true);

  void toggleSoundCloudEnabled(bool val) {
    soundcloudEnabled.value = val;
    setBox.put("soundcloudEnabled", val);
  }

  /// Free lossless FLAC fallback from archive.org.
  final internetArchiveEnabled = RxBool(Hive.box("AppPrefs")
          .get("internetArchiveEnabled", defaultValue: true) ==
      true);

  void toggleInternetArchiveEnabled(bool val) {
    internetArchiveEnabled.value = val;
    setBox.put("internetArchiveEnabled", val);
  }

  /// Provider priority order — the first entry is tried first.
  final providerOrder = RxList<String>(_storedProviderOrder());

  static List<String> _storedProviderOrder() {
    final stored = Hive.box('AppPrefs').get('providerOrder');
    if (stored is List && stored.whereType<String>().isNotEmpty) {
      return stored.whereType<String>().toList();
    }
    return List.of(StreamRouteConfig.defaultProviderOrder);
  }

  void setProviderOrder(List<String> order) {
    final clean = order.where((id) => id.isNotEmpty).toList();
    providerOrder.value = clean;
    setBox.put('providerOrder', clean);
  }

  final tidalEnabled = RxBool(
      Hive.box("AppPrefs").get("tidalEnabled", defaultValue: false) == true);
  final tidalEndpoints = RxString((Hive.box("AppPrefs")
          .get("tidalEndpoints", defaultValue: "") as String?) ??
      "");
  final tidalQuality = RxString((Hive.box("AppPrefs")
          .get("tidalQuality", defaultValue: "LOSSLESS") as String?) ??
      "LOSSLESS");

  void toggleTidalEnabled(bool val) {
    tidalEnabled.value = val;
    setBox.put("tidalEnabled", val);
  }

  void changeTidalEndpoints(String val) {
    tidalEndpoints.value = val;
    setBox.put("tidalEndpoints", val);
  }

  void changeTidalQuality(String val) {
    tidalQuality.value = val;
    setBox.put("tidalQuality", val);
  }

  // ---- Deezer -----------------------------------------------------------
  final deezerEnabled = RxBool(
      Hive.box("AppPrefs").get("deezerEnabled", defaultValue: false) == true);
  final deezerEndpoints = RxString((Hive.box("AppPrefs")
          .get("deezerEndpoints", defaultValue: "") as String?) ??
      "");
  final deezerQuality = RxString((Hive.box("AppPrefs")
          .get("deezerQuality", defaultValue: "FLAC") as String?) ??
      "FLAC");

  void toggleDeezerEnabled(bool val) {
    deezerEnabled.value = val;
    setBox.put("deezerEnabled", val);
  }

  void changeDeezerEndpoints(String val) {
    deezerEndpoints.value = val;
    setBox.put("deezerEndpoints", val);
  }

  void changeDeezerQuality(String val) {
    deezerQuality.value = val;
    setBox.put("deezerQuality", val);
  }

  // ---- Apple Music ------------------------------------------------------
  final appleEnabled = RxBool(
      Hive.box("AppPrefs").get("appleEnabled", defaultValue: false) == true);
  final appleEndpoints = RxString((Hive.box("AppPrefs")
          .get("appleEndpoints", defaultValue: "") as String?) ??
      "");

  void toggleAppleEnabled(bool val) {
    appleEnabled.value = val;
    setBox.put("appleEnabled", val);
  }

  void changeAppleEndpoints(String val) {
    appleEndpoints.value = val;
    setBox.put("appleEndpoints", val);
  }

  // ---- Amazon Music -----------------------------------------------------
  final amazonEnabled = RxBool(
      Hive.box("AppPrefs").get("amazonEnabled", defaultValue: false) == true);
  final amazonEndpoints = RxString((Hive.box("AppPrefs")
          .get("amazonEndpoints", defaultValue: "") as String?) ??
      "");
  final amazonQuality = RxString((Hive.box("AppPrefs")
          .get("amazonQuality", defaultValue: "HI_RES") as String?) ??
      "HI_RES");

  void toggleAmazonEnabled(bool val) {
    amazonEnabled.value = val;
    setBox.put("amazonEnabled", val);
  }

  void changeAmazonEndpoints(String val) {
    amazonEndpoints.value = val;
    setBox.put("amazonEndpoints", val);
  }

  void changeAmazonQuality(String val) {
    amazonQuality.value = val;
    setBox.put("amazonQuality", val);
  }

  // ---- Instagram ---------------------------------------------------------
  final instagramEnabled = RxBool(Hive.box("AppPrefs")
          .get("instagramEnabled", defaultValue: false) == true);
  final instagramCookie = RxString((Hive.box("AppPrefs")
          .get("instagramCookie", defaultValue: "") as String?) ??
      "");

  void toggleInstagramEnabled(bool val) {
    instagramEnabled.value = val;
    setBox.put("instagramEnabled", val);
  }

  void changeInstagramCookie(String val) {
    instagramCookie.value = val;
    setBox.put("instagramCookie", val);
  }

  Future<void> _setInitValue() async {
    final isDesktop = GetPlatform.isDesktop;
    final appLang = setBox.get('currentAppLanguageCode') ?? "en";
    currentAppLanguageCode.value = appLang == "zh_Hant"
        ? "zh-TW"
        : appLang == "zh_Hans"
            ? "zh-CN"
            : appLang;
    isBottomNavBarEnabled.value =
        isDesktop ? false : (setBox.get("isBottomNavBarEnabled") ?? false);
    noOfHomeScreenContent.value = setBox.get("noOfHomeScreenContent") ?? 3;
    isTransitionAnimationDisabled.value =
        setBox.get("isTransitionAnimationDisabled") ?? false;
    cacheSongs.value = setBox.get('cacheSongs') ?? false;
    themeModetype.value = ThemeType.values[setBox.get('themeModeType') ?? 0];
    skipSilenceEnabled.value =
        isDesktop ? false : setBox.get("skipSilenceEnabled");
    loudnessNormalizationEnabled.value = isDesktop
        ? false
        : (setBox.get("loudnessNormalizationEnabled") ?? false);
    autoOpenPlayer.value = (setBox.get("autoOpenPlayer") ?? true);
    restorePlaybackSession.value =
        setBox.get("restrorePlaybackSession") ?? false;
    cacheHomeScreenData.value = setBox.get("cacheHomeScreenData") ?? true;
    final storedQuality = setBox.get('streamingQuality');
    streamingQuality.value = (storedQuality is int &&
            storedQuality >= 0 &&
            storedQuality < AudioQuality.values.length)
        ? AudioQuality.values[storedQuality]
        : AudioQuality.High;
    playerUi.value = isDesktop ? 0 : (setBox.get('playerUi') ?? 0);
    backgroundPlayEnabled.value = setBox.get("backgroundPlayEnabled") ?? true;
    keepScreenAwake.value =
        setBox.get("keepScreenAwake") ?? GetPlatform.isDesktop ? true : false;
    final downloadPath =
        setBox.get('downloadLocationPath') ?? await _createInAppSongDownDir();
    downloadLocationPath.value =
        (isDesktop && downloadPath.contains("emulated"))
            ? await _createInAppSongDownDir()
            : downloadPath;

    exportLocationPath.value =
        setBox.get("exportLocationPath") ?? "/storage/emulated/0/Music";
    downloadingFormat.value = setBox.get('downloadingFormat') ?? "original";
    discoverContentType.value = setBox.get('discoverContentType') ?? "REC";
    // Migrate removed regional chart and quick picks types to REC
    if (discoverContentType.value == "TR" ||
        discoverContentType.value == "TMV" ||
        discoverContentType.value == "QP") {
      discoverContentType.value = "REC";
      setBox.put('discoverContentType', "REC");
    }
    slidableActionEnabled.value = setBox.get('slidableActionEnabled') ?? true;
    if (setBox.containsKey("piped")) {
      isLinkedWithPiped.value = setBox.get("piped")['isLoggedIn'];
    }
    stopPlyabackOnSwipeAway.value =
        setBox.get('stopPlyabackOnSwipeAway') ?? false;
    if (GetPlatform.isAndroid) {
      isIgnoringBatteryOptimizations.value =
          (await Permission.ignoreBatteryOptimizations.isGranted);
    }
    autoDownloadFavoriteSongEnabled.value =
        setBox.get("autoDownloadFavoriteSongEnabled") ?? false;
    galaxyOverlayEnabled.value = setBox.get("galaxyOverlayEnabled") ?? true;
    densityScale.value =
        (setBox.get("densityScale") as num?)?.toDouble() ?? 1.0;
    inputControlEnabled.value =
        setBox.get("inputControlEnabled", defaultValue: true) == true;
  }

  void setAppLanguage(String? val) {
    Get.updateLocale(Locale(val!));
    Get.find<MusicServices>().hlCode = val;
    Get.find<HomeScreenController>().loadContentFromNetwork(silent: true);
    currentAppLanguageCode.value = val;
    setBox.put('currentAppLanguageCode', val);
  }

  void setContentNumber(int? no) {
    noOfHomeScreenContent.value = no!;
    setBox.put("noOfHomeScreenContent", no);
  }

  void setStreamingQuality(dynamic val) {
    setBox.put("streamingQuality", AudioQuality.values.indexOf(val));
    streamingQuality.value = val;
  }

  void setPlayerUi(dynamic val) {
    final playerCon = Get.find<PlayerController>();
    setBox.put("playerUi", val);
    if (val == 1 && playerCon.gesturePlayerStateAnimationController == null) {
      playerCon.initGesturePlayerStateAnimationController();
    }

    playerUi.value = val;
  }

  void enableBottomNavBar(bool val) {
    final homeScrCon = Get.find<HomeScreenController>();
    final playerCon = Get.find<PlayerController>();
    if (val) {
      homeScrCon.onSideBarTabSelected(3);
      isBottomNavBarEnabled.value = true;
    } else {
      isBottomNavBarEnabled.value = false;
      homeScrCon.onSideBarTabSelected(5);
    }
    if (!Get.find<PlayerController>().initFlagForPlayer) {
      playerCon.playerPanelMinHeight.value =
          val ? 75.0 : 75.0 + Get.mediaQuery.viewPadding.bottom;
    }
    setBox.put("isBottomNavBarEnabled", val);
  }

  void toggleSlidableAction(bool val) {
    setBox.put("slidableActionEnabled", val);
    slidableActionEnabled.value = val;
  }

  void changeDownloadingFormat(String? val) {
    setBox.put("downloadingFormat", val);
    downloadingFormat.value = val!;
  }

  Future<void> setExportedLocation() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Select export file folder");
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    setBox.put("exportLocationPath", pickedFolderPath);
    exportLocationPath.value = pickedFolderPath;
  }

  Future<void> setDownloadLocation() async {
    if (!await PermissionService.getExtStoragePermission()) {
      return;
    }

    final String? pickedFolderPath = await FilePicker.platform
        .getDirectoryPath(dialogTitle: "Select downloads folder");
    if (pickedFolderPath == '/' || pickedFolderPath == null) {
      return;
    }

    setBox.put("downloadLocationPath", pickedFolderPath);
    downloadLocationPath.value = pickedFolderPath;
  }

  void disableTransitionAnimation(bool val) {
    setBox.put('isTransitionAnimationDisabled', val);
    isTransitionAnimationDisabled.value = val;
  }

  Future<void> clearImagesCache() async {
    final tempImgDirPath =
        "${(await getApplicationCacheDirectory()).path}/libCachedImageData";
    final tempImgDir = Directory(tempImgDirPath);
    try {
      if (await tempImgDir.exists()) {
        await tempImgDir.delete(recursive: true);
      }
      // ignore: empty_catches
    } catch (e) {}
  }

  void resetDownloadLocation() {
    final defaultPath = "$_supportDir/Music";
    setBox.put("downloadLocationPath", defaultPath);
    downloadLocationPath.value = defaultPath;
  }

  void onThemeChange(dynamic val) {
    setBox.put('themeModeType', ThemeType.values.indexOf(val));
    themeModetype.value = val;
    Get.find<ThemeController>().changeThemeModeType(val);
  }

  void onContentChange(dynamic value) {
    setBox.put('discoverContentType', value);
    discoverContentType.value = value;
    final homeScreenController = Get.find<HomeScreenController>();
    if (value == "REC") homeScreenController.resetRecommendationsCooldown();
    homeScreenController.changeDiscoverContent(value);
  }

  void toggleCachingSongsValue(bool value) {
    setBox.put("cacheSongs", value);
    cacheSongs.value = value;
  }

  void toggleSkipSilence(bool val) {
    Get.find<PlayerController>().toggleSkipSilence(val);
    setBox.put('skipSilenceEnabled', val);
    skipSilenceEnabled.value = val;
  }

  void toggleLoudnessNormalization(bool val) {
    Get.find<PlayerController>().toggleLoudnessNormalization(val);
    setBox.put("loudnessNormalizationEnabled", val);
    loudnessNormalizationEnabled.value = val;
  }

  void toggleRestorePlaybackSession(bool val) {
    setBox.put("restrorePlaybackSession", val);
    restorePlaybackSession.value = val;
  }

  void toggleSpotifyAutoFetchLyrics(bool val) {
    setBox.put("spotifyAutoFetchLyrics", val);
    spotifyAutoFetchLyrics.value = val;
  }

  void toggleSpotifyAutoEnrichTracks(bool val) {
    setBox.put("spotifyAutoEnrichTracks", val);
    spotifyAutoEnrichTracks.value = val;
  }

  Future<void> toggleCacheHomeScreenData(bool val) async {
    setBox.put("cacheHomeScreenData", val);
    cacheHomeScreenData.value = val;
    if (!val) {
      Hive.openBox("homeScreenData").then((box) async {
        await box.clear();
        await box.close();
      });
    } else {
      await Hive.openBox("homeScreenData");
      Get.find<HomeScreenController>().cachedHomeScreenData(updateAll: true);
    }
  }

  void toggleAutoDownloadFavoriteSong(bool val) {
    setBox.put("autoDownloadFavoriteSongEnabled", val);
    autoDownloadFavoriteSongEnabled.value = val;
  }

  void toggleBackgroundPlay(bool val) {
    setBox.put('backgroundPlayEnabled', val);
    backgroundPlayEnabled.value = val;
  }

  void toggleKeepScreenAwake(bool val) {
    setBox.put('keepScreenAwake', val);
    keepScreenAwake.value = val;
    try {
        if (val) {
          // enable wakelock immediately if music is playing
          if (Get.find<PlayerController>().buttonState.value ==
              PlayButtonState.playing) {
            WakelockPlus.enable();
          }
        } else {
          WakelockPlus.disable();
        }
     
    } catch (e) {
      // ignore if player/controller not available
    }
  }

  Future<void> enableIgnoringBatteryOptimizations() async {
    await Permission.ignoreBatteryOptimizations.request();
    isIgnoringBatteryOptimizations.value =
        await Permission.ignoreBatteryOptimizations.isGranted;
  }

  void toggleAutoOpenPlayer(bool val) {
    setBox.put('autoOpenPlayer', val);
    autoOpenPlayer.value = val;
  }

  Future<void> unlinkPiped() async {
    Get.find<PipedServices>().logout();
    isLinkedWithPiped.value = false;
    Get.find<LibraryPlaylistsController>().removePipedPlaylists();
    final box = await Hive.openBox('blacklistedPlaylist');
    box.clear();
    ScaffoldMessenger.of(Get.context!).showSnackBar(
        snackbar(Get.context!, "unlinkAlert".tr, size: SanckBarSize.MEDIUM));
    box.close();
  }

  Future<void> resetAppSettingsToDefault() async {
    await setBox.clear();
    // Re-seed the same defaults main() would seed on a fresh install, so
    // the persisted state stays consistent even before the next restart.
    setBox.putAll({
      'themeModeType': 0,
      "cacheSongs": false,
      "skipSilenceEnabled": false,
      'streamingQuality': 1,
      'themePrimaryColor': 4278199603,
      'discoverContentType': "REC",
      'newVersionVisibility': updateCheckFlag,
      "cacheHomeScreenData": true
    });
    await _setInitValue();
    // Fields initialized in field initializers (not by _setInitValue) also
    // need their in-memory state restored so the UI reflects the reset.
    qobuzEnabled.value = false;
    qobuzInstances.value = "";
    qobuzCountry.value = "US";
    qobuzQuality.value = 27;
    tidalEnabled.value = false;
    tidalEndpoints.value = "";
    tidalQuality.value = "LOSSLESS";
    deezerEnabled.value = false;
    deezerEndpoints.value = "";
    deezerQuality.value = "FLAC";
    appleEnabled.value = false;
    appleEndpoints.value = "";
    amazonEnabled.value = false;
    amazonEndpoints.value = "";
    amazonQuality.value = "HI_RES";
    instagramEnabled.value = false;
    instagramCookie.value = "";
    internetArchiveEnabled.value = true;
    inputControlEnabled.value = true;
    providerOrder.value = List.of(StreamRouteConfig.defaultProviderOrder);
    spotifyAutoFetchLyrics.value = true;
    spotifyAutoEnrichTracks.value = true;
    isLinkedWithPiped.value = false;
    try {
      Get.find<ThemeController>().refreshTheme();
    } catch (_) {
      // Theme controller may not be registered yet.
    }
  }

  void toggleStopPlyabackOnSwipeAway(bool val) {
    setBox.put('stopPlyabackOnSwipeAway', val);
    stopPlyabackOnSwipeAway.value = val;
  }

  void toggleGalaxyOverlay(bool val) {
    setBox.put("galaxyOverlayEnabled", val);
    galaxyOverlayEnabled.value = val;
  }

  void setDensityScale(double val) {
    setBox.put("densityScale", val);
    densityScale.value = val;
    Get.find<ThemeController>().refreshTheme();
  }

  Future<void> closeAllDatabases() async {
    await Hive.close();
  }

  Future<String> get dbDir async {
    if (GetPlatform.isDesktop) {
      return "$supportDirPath/db";
    } else {
      return (await getApplicationDocumentsDirectory()).path;
    }
  }
}
