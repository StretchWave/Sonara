import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/playling_from.dart';
import '/ui/widgets/songinfo_bottom_sheet.dart';
import '/utils/helper.dart';
import '../ui/widgets/loader.dart';
import '/services/music_service.dart';
import '/services/supabase/supabase_service.dart';
import '/ui/player/player_controller.dart';
import '../ui/navigator.dart';
import '../ui/widgets/snackbar.dart';

class AppLinksController extends GetxController with ProcessLink {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void onInit() {
    initDeepLinks();
    super.onInit();
  }

  Future<void> initDeepLinks() async {
    _appLinks = AppLinks();

    // Check initial link if app was in cold state (terminated)
    final appLink = await _appLinks.getInitialAppLink();
    if (appLink != null) {
      await filterLinks(appLink);
    }

    // Handle link when app is in warm state (front or background)
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) async {
      await filterLinks(uri);
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }
}

mixin ProcessLink {
  Future<void> filterLinks(Uri uri) async {
    // Handle Supabase auth callbacks FIRST, before touching any UI
    // controllers. During onboarding PlayerController/panel may not be
    // ready, and any exception here would swallow the auth callback
    // (app returns to foreground but login state never updates).
    final isSupabaseScheme = uri.scheme == "io.supabase.sonara" ||
        uri.scheme.startsWith("io.supabase") ||
        uri.scheme == "io.supabase.wycltgbzbhvnfavwxgpm";
    final hasAuthParams = uri.queryParameters.containsKey("code") ||
        uri.fragment.contains("access_token") ||
        uri.fragment.contains("error_description") ||
        uri.queryParameters.containsKey("error") ||
        uri.queryParameters.containsKey("error_description") ||
        uri.queryParameters.containsKey("access_token");
    if ((isSupabaseScheme && uri.host == "login-callback") ||
        (isSupabaseScheme && hasAuthParams) ||
        hasAuthParams) {
      printINFO("Received Supabase auth deep link: $uri");
      try {
        if (Get.isRegistered<SupabaseService>()) {
          final supabaseService = Get.find<SupabaseService>();
          // supabase_flutter observes deep links internally
          // (detectSessionInUri) and exchanges ?code= automatically. To
          // avoid a double-exchange race (second exchange fails with "Code
          // verifier could not be found"), only fall back to manual handling
          // if the SDK did not log the user in.
          await Future.delayed(const Duration(milliseconds: 800));
          if (!supabaseService.isLoggedIn.value &&
              supabaseService.client?.auth.currentSession == null) {
            await supabaseService.handleAuthDeeplink(uri);
          } else {
            printINFO("Supabase auth already handled by SDK, skipping manual exchange.");
          }
          // Surface outcome for debugging: if still logged out, make sure
          // the dialog shows *something* instead of silent no-op.
          if (!supabaseService.isLoggedIn.value &&
              supabaseService.authErrorMessage.value.isEmpty) {
            supabaseService.authErrorMessage.value =
                'Login redirect received but session was not created. Open Supabase Dashboard -> Authentication -> Logs -> Auth Logs and check for code-exchange errors.';
          }
        }
      } catch (e) {
        printERROR("Error processing Supabase auth deep link: $e");
      }
      return;
    }

    try {
      final playerController = Get.find<PlayerController>();
      if (playerController.playerPanelController.isPanelOpen) {
        playerController.playerPanelController.close();
      }

      if (Get.isRegistered<SongInfoController>()) {
        Navigator.of(Get.context!).pop();
      }
    } catch (e) {
      printERROR("App link UI reset skipped: $e");
    }

    if (uri.host == "youtube.com" ||
        uri.host == "music.youtube.com" ||
        uri.host == "youtu.be" ||
        uri.host == "www.youtube.com" ||
        uri.host == "m.youtube.com") {
      printINFO(
          "pathsegmet: ${uri.pathSegments} params:${uri.queryParameters}");
      if (uri.pathSegments[0] == "playlist" &&
          uri.queryParameters.containsKey("list")) {
        final browseId = uri.queryParameters['list'];
        await openPlaylistOrAlbum(browseId!);
      } else if (uri.pathSegments[0] == "shorts") {
        ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
            Get.context!, "notaSongVideo".tr,
            size: SanckBarSize.MEDIUM));
      } else if (uri.pathSegments[0] == "watch") {
        final songId = uri.queryParameters['v'];
        await playSong(songId!);
      } else if (uri.pathSegments[0] == "channel") {
        final browseId = uri.pathSegments[1];
        await openArtist(browseId);
      } else if ((uri.queryParameters.isEmpty || uri.query.contains("si=")) &&
          uri.host == "youtu.be") {
        final songId = uri.pathSegments[0];
        await playSong(songId);
      }
    } else {
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "notaValidLink".tr,
          size: SanckBarSize.MEDIUM));
    }
  }

  Future<void> openPlaylistOrAlbum(String browseId) async {
    if (browseId.contains("OLAK5uy")) {
      Get.toNamed(ScreenNavigationSetup.albumScreen,
          id: ScreenNavigationSetup.id, arguments: (null, browseId));
    } else {
      Get.toNamed(ScreenNavigationSetup.playlistScreen,
          id: ScreenNavigationSetup.id, arguments: [null, browseId]);
    }
  }

  Future<void> openArtist(String channelId) async {
    await Get.toNamed(ScreenNavigationSetup.artistScreen,
        id: ScreenNavigationSetup.id, arguments: [true, channelId]);
  }

  Future<void> playSong(String songId) async {
    showDialog(
        context: Get.context!,
        builder: (context) => const Center(
                child: LoadingIndicator(
              strokeWidth: 5,
            )),
        barrierDismissible: false);
    final result = await Get.find<MusicServices>().getSongWithId(songId);
    Navigator.of(Get.context!).pop();
    if (result[0]) {
      Get.find<PlayerController>().playPlayListSong(List.from(result[1]), 0,
          playfrom: PlaylingFrom(type: PlaylingFromType.SELECTION));
    } else {
      ScaffoldMessenger.of(Get.context!).showSnackBar(snackbar(
          Get.context!, "notaSongVideo".tr,
          size: SanckBarSize.MEDIUM));
    }
  }
}
