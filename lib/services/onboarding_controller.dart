import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '../utils/helper.dart';
import 'supabase/supabase_service.dart';
import 'supabase/user_preferences_service.dart';

/// Onboarding step identifiers.
enum OnboardingStep {
  /// User has never opened the app before.
  welcome,

  /// User is choosing whether to sign in or skip.
  loginOrSkip,

  /// Authenticated user is selecting music languages.
  musicLanguageSelection,

  /// Authenticated user is selecting favourite artists.
  artistSelection,

  /// Onboarding is complete — app functions normally.
  complete,
}

/// Manages the first-launch onboarding state machine.
///
/// State is persisted to the existing Hive `AppPrefs` box so restarts
/// never re-trigger completed steps.  For authenticated users the
/// preferences are additionally synced to Supabase via
/// [UserPreferencesService].
class OnboardingController extends GetxController {
  final _box = Hive.box('AppPrefs');

  // ---------------------------------------------------------------------------
  // Reactive state
  // ---------------------------------------------------------------------------

  final currentStep = OnboardingStep.welcome.obs;

  /// Whether the full onboarding flow has been completed (or skipped).
  final isOnboardingComplete = false.obs;

  /// Music language codes the user selected (e.g. ["ml", "hi", "en"]).
  final musicLanguages = <String>[].obs;

  /// Serialised artist maps the user selected (name + browseId + thumbnail).
  final favoriteArtists = <Map<String, dynamic>>[].obs;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
    _loadFromHive();
  }

  void _loadFromHive() {
    final completed = _box.get('onboardingCompleted', defaultValue: false);
    isOnboardingComplete.value = completed == true;

    // Music languages
    final storedLangs = _box.get('musicLanguages');
    if (storedLangs is List) {
      musicLanguages.value =
          storedLangs.map((e) => e.toString()).toList();
    }

    // Favourite artists
    final storedArtists = _box.get('favoriteArtists');
    if (storedArtists is List) {
      favoriteArtists.value = storedArtists
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    if (isOnboardingComplete.value) {
      currentStep.value = OnboardingStep.complete;
    }
  }

  // ---------------------------------------------------------------------------
  // Welcome / Login-or-Skip
  // ---------------------------------------------------------------------------

  /// Called when the user taps "Skip for now" on the welcome screen.
  /// Moves directly to language selection so guest users can still personalize their feed.
  void skipLogin() {
    _box.put('onboardingSkippedLogin', true);
    _advanceToNextStep();
  }

  /// Whether the user can navigate back to a previous onboarding step.
  bool get canGoBack =>
      currentStep.value == OnboardingStep.musicLanguageSelection ||
      currentStep.value == OnboardingStep.artistSelection;

  /// Navigates back to the preceding onboarding step.
  void goToPreviousStep() {
    switch (currentStep.value) {
      case OnboardingStep.artistSelection:
        currentStep.value = OnboardingStep.musicLanguageSelection;
        break;
      case OnboardingStep.musicLanguageSelection:
        currentStep.value = OnboardingStep.welcome;
        break;
      default:
        break;
    }
  }

  /// Skips all remaining onboarding steps and completes onboarding.
  void skipAll() {
    _finaliseOnboarding();
  }

  /// Called after successful Google (or other) login during onboarding.
  ///
  /// Checks whether the user already has cloud-stored preferences and
  /// skips steps that are already completed.
  Future<void> completeLogin() async {
    // Try to load existing preferences from Supabase
    if (!Get.isRegistered<SupabaseService>()) {
      _advanceToNextStep();
      return;
    }
    final supabase = Get.find<SupabaseService>();
    if (supabase.isLoggedIn.value && supabase.userId.value.isNotEmpty) {
      try {
        if (!Get.isRegistered<UserPreferencesService>()) {
          _advanceToNextStep();
          return;
        }
        final prefService = Get.find<UserPreferencesService>();
        final cloudPrefs =
            await prefService.loadPreferences(supabase.userId.value);
        if (cloudPrefs != null) {
          final cloudCompleted =
              cloudPrefs['onboarding_completed'] == true;
          final cloudLangs = cloudPrefs['music_languages'];
          final cloudArtists = cloudPrefs['favorite_artists'];

          if (cloudLangs is List && cloudLangs.isNotEmpty) {
            musicLanguages.value =
                cloudLangs.map((e) => e.toString()).toList();
            _box.put('musicLanguages', musicLanguages.toList());
          }
          if (cloudArtists is List && cloudArtists.isNotEmpty) {
            favoriteArtists.value = cloudArtists
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            _box.put('favoriteArtists', favoriteArtists.toList());
          }

          if (cloudCompleted) {
            _box.put('onboardingCompleted', true);
            isOnboardingComplete.value = true;
            currentStep.value = OnboardingStep.complete;
            return;
          }
        }
      } catch (e) {
        printERROR('OnboardingController.completeLogin cloud load error: $e');
      }
    }

    _advanceToNextStep();
  }

  void _advanceToNextStep() {
    if (musicLanguages.isEmpty) {
      currentStep.value = OnboardingStep.musicLanguageSelection;
    } else if (favoriteArtists.isEmpty) {
      currentStep.value = OnboardingStep.artistSelection;
    } else {
      _finaliseOnboarding();
    }
  }

  // ---------------------------------------------------------------------------
  // Language selection
  // ---------------------------------------------------------------------------

  /// Saves the user's music language selections and moves to artist step.
  void setMusicLanguages(List<String> langs) {
    musicLanguages.value = langs;
    _box.put('musicLanguages', langs);
    currentStep.value = OnboardingStep.artistSelection;
  }

  /// User chose to skip language selection.
  void skipLanguages() {
    currentStep.value = OnboardingStep.artistSelection;
  }

  // ---------------------------------------------------------------------------
  // Artist selection
  // ---------------------------------------------------------------------------

  /// Saves the user's favourite artist selections and completes onboarding.
  void setFavoriteArtists(List<Map<String, dynamic>> artists) {
    favoriteArtists.value = artists;
    _box.put('favoriteArtists', artists);
    _finaliseOnboarding();
  }

  /// User chose to skip artist selection.
  void skipArtists() {
    _finaliseOnboarding();
  }

  // ---------------------------------------------------------------------------
  // Login-later flow
  // ---------------------------------------------------------------------------

  /// Called when a guest user logs in later (e.g. from Settings).
  ///
  /// Returns `true` if there are remaining onboarding steps to show.
  Future<bool> resumeOnboardingAfterLateLogin() async {
    if (!Get.isRegistered<SupabaseService>()) return false;
    final supabase = Get.find<SupabaseService>();
    if (!supabase.isLoggedIn.value) return false;

    // Try to load existing cloud prefs first
    try {
      if (!Get.isRegistered<UserPreferencesService>()) return false;
      final prefService = Get.find<UserPreferencesService>();
      final cloudPrefs =
          await prefService.loadPreferences(supabase.userId.value);
      if (cloudPrefs != null) {
        final cloudLangs = cloudPrefs['music_languages'];
        final cloudArtists = cloudPrefs['favorite_artists'];
        final cloudCompleted =
            cloudPrefs['onboarding_completed'] == true;

        // Merge cloud prefs into local if local is empty
        if (cloudLangs is List &&
            cloudLangs.isNotEmpty &&
            musicLanguages.isEmpty) {
          musicLanguages.value =
              cloudLangs.map((e) => e.toString()).toList();
          _box.put('musicLanguages', musicLanguages.toList());
        }
        if (cloudArtists is List &&
            cloudArtists.isNotEmpty &&
            favoriteArtists.isEmpty) {
          favoriteArtists.value = cloudArtists
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _box.put('favoriteArtists', favoriteArtists.toList());
        }

        if (cloudCompleted &&
            musicLanguages.isNotEmpty &&
            favoriteArtists.isNotEmpty) {
          // Everything already done in cloud — just sync local
          await _syncToCloud();
          return false;
        }
      }
    } catch (e) {
      printERROR(
          'OnboardingController.resumeOnboardingAfterLateLogin error: $e');
    }

    // Upload any existing local prefs to cloud
    await _syncToCloud();

    // Determine what's still missing
    if (musicLanguages.isEmpty) {
      currentStep.value = OnboardingStep.musicLanguageSelection;
      return true;
    }
    if (favoriteArtists.isEmpty) {
      currentStep.value = OnboardingStep.artistSelection;
      return true;
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _finaliseOnboarding() {
    _box.put('onboardingCompleted', true);
    isOnboardingComplete.value = true;
    currentStep.value = OnboardingStep.complete;
    _syncToCloud();
  }

  /// Uploads current local preferences to Supabase (best-effort).
  Future<void> _syncToCloud() async {
    try {
      if (!Get.isRegistered<SupabaseService>()) return;
      final supabase = Get.find<SupabaseService>();
      if (!supabase.isLoggedIn.value || supabase.userId.value.isEmpty) {
        return;
      }
      if (!Get.isRegistered<UserPreferencesService>()) return;
      final prefService = Get.find<UserPreferencesService>();
      await prefService.savePreferences(
        userId: supabase.userId.value,
        musicLanguages: musicLanguages.toList(),
        favoriteArtists: favoriteArtists.toList(),
        onboardingCompleted: isOnboardingComplete.value,
      );
    } catch (e) {
      printERROR('OnboardingController._syncToCloud error: $e');
    }
  }
}
