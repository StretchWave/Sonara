import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:terminate_restart/terminate_restart.dart';

import '/ui/screens/Search/search_screen_controller.dart';
import '/utils/get_localization.dart';
import '/services/downloader.dart';
import '/services/piped_service.dart';
import '/services/playback_stats_service.dart';
import '/services/lastfm_service.dart';
import '/services/onboarding_controller.dart';
import '/services/recommendation_service.dart';
import '/services/supabase/supabase_service.dart';
import '/services/supabase/playlist_sync_service.dart';
import '/services/supabase/user_preferences_service.dart';
import 'utils/app_link_controller.dart';
import '/services/audio_handler.dart';
import '/services/music_service.dart';
import '/ui/home.dart';
import '/ui/player/player_controller.dart';
import 'ui/screens/Settings/settings_screen_controller.dart';
import 'ui/screens/Settings/components/supabase_auth_dialog.dart';
import '/ui/utils/theme_controller.dart';
import 'ui/screens/Home/home_screen_controller.dart';
import 'ui/screens/Library/library_controller.dart';
import 'utils/system_tray.dart';
import 'utils/update_check_flag_file.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive();
  _setAppInitPrefs();
  try {
    await Supabase.initialize(
      url: 'https://wycltgbzbhvnfavwxgpm.supabase.co',
      anonKey: 'sb_publishable_i_8L3mLklUOv_ERRrvV94A_zya-5W-v',
    );
  } catch (e) {
    // If Supabase initialization fails unexpectedly (e.g. offline startup),
    // Sonara gracefully continues with 100% offline local functionality.
  }
  startApplicationServices();
  Get.put<AudioHandler>(await initAudioService(), permanent: true);
  // Start background listeners that depend on the audio handler
  Get.find<PlaybackStatsService>();
  Get.find<LastFmService>();
  Get.find<PlaylistSyncService>();
  WidgetsBinding.instance.addObserver(LifecycleHandler());
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  TerminateRestart.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    if (!GetPlatform.isDesktop) Get.put(AppLinksController());
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    return GetMaterialApp(
        title: 'Sonara',
        home: const Home(),
        debugShowCheckedModeBanner: false,
        translations: Languages(),
        locale:
            Locale(Hive.box("AppPrefs").get('currentAppLanguageCode') ?? "en"),
        fallbackLocale: const Locale("en"),
        builder: (context, child) {
          final mQuery = MediaQuery.of(context);
          // Preserve the user's system font scale, then apply the app's
          // density-scale preference on top (55% - 110%).
          final baseScale = mQuery.textScaler.scale(14) / 14;
          return Stack(
            children: [
              GetX<ThemeController>(
                builder: (controller) {
                  // Read the observable in this GetX's own scope so the
                  // builder registers a dependency (GetX requires every
                  // GetX/Obx builder to read at least one observable).
                  final themeData = controller.themedata.value!;
                  return GetX<SettingsScreenController>(
                    builder: (settings) {
                      final scale =
                          (baseScale * settings.densityScale.value)
                              .clamp(0.55, 1.1);
                      return MediaQuery(
                        data: mQuery.copyWith(
                            textScaler: TextScaler.linear(scale)),
                        child: AnimatedTheme(
                            duration: const Duration(milliseconds: 700),
                            data: themeData,
                            child: child!),
                      );
                    },
                  );
                },
              ),
              GestureDetector(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    color: Colors.transparent,
                    height: mQuery.padding.bottom,
                    width: mQuery.size.width,
                  ),
                ),
              )
            ],
          );
        });
  }
}

Future<void> startApplicationServices() async {
  Get.lazyPut(() => PipedServices(), fenix: true);
  Get.lazyPut(() => MusicServices(), fenix: true);
  Get.lazyPut(() => ThemeController(), fenix: true);
  Get.lazyPut(() => PlayerController(), fenix: true);
  Get.lazyPut(() => HomeScreenController(), fenix: true);
  Get.lazyPut(() => LibrarySongsController(), fenix: true);
  Get.lazyPut(() => LibraryPlaylistsController(), fenix: true);
  Get.lazyPut(() => LibraryAlbumsController(), fenix: true);
  Get.lazyPut(() => LibraryArtistsController(), fenix: true);
  Get.lazyPut(() => SettingsScreenController(), fenix: true);
  Get.lazyPut(() => Downloader(), fenix: true);
  Get.lazyPut(() => PlaybackStatsService(), fenix: true);
  Get.lazyPut(() => LastFmService(), fenix: true);
  Get.lazyPut(() => RecommendationService(), fenix: true);
  Get.lazyPut(() => SupabaseService(), fenix: true);
  Get.lazyPut(() => PlaylistSyncService(), fenix: true);
  Get.lazyPut(() => UserPreferencesService(), fenix: true);
  Get.lazyPut(() => OnboardingController(), fenix: true);
  if (GetPlatform.isDesktop) {
    Get.lazyPut(() => SearchScreenController(), fenix: true);
    Get.put(DesktopSystemTray());
  }
}

initHive() async {
  String applicationDataDirectoryPath;
  if (GetPlatform.isDesktop) {
    applicationDataDirectoryPath =
        "${(await getApplicationSupportDirectory()).path}/db";
  } else {
    applicationDataDirectoryPath =
        (await getApplicationDocumentsDirectory()).path;
  }
  await Hive.initFlutter(applicationDataDirectoryPath);
  await Hive.openBox("SongsCache");
  await Hive.openBox("SongDownloads");
  await Hive.openBox('SongsUrlCache');
  await Hive.openBox("AppPrefs");
  await Hive.openBox("LyricsOffset");
  await Hive.openBox("PlaylistSyncMetadata");
}

void _setAppInitPrefs() {
  final appPrefs = Hive.box("AppPrefs");
  if (appPrefs.isEmpty) {
    appPrefs.putAll({
      'themeModeType': 0,
      "cacheSongs": false,
      "skipSilenceEnabled": false,
      'streamingQuality': 1,
      'themePrimaryColor': 4278199603,
      'discoverContentType': "REC",
      'newVersionVisibility': updateCheckFlag,
      "cacheHomeScreenData": true,
      "inputControlEnabled": true
    });
  } else if (!appPrefs.containsKey("inputControlEnabled")) {
    appPrefs.put("inputControlEnabled", true);
  }
}

class LifecycleHandler extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else if (state == AppLifecycleState.detached) {
      await Get.find<AudioHandler>().customAction("saveSession");
    }
  }
}
