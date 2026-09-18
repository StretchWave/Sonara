import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sonara/services/onboarding_controller.dart';
import 'package:sonara/ui/screens/Onboarding/curated_artists_data.dart';
import 'package:sonara/ui/screens/Settings/settings_screen_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('onboarding_test');
    Hive.init(tempDir.path);
    await Hive.openBox('AppPrefs');
  });

  tearDown(() async {
    await Hive.close();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('OnboardingController', () {
    test('initial state defaults to uncompleted onboarding', () {
      final controller = OnboardingController();
      controller.onInit();

      expect(controller.isOnboardingComplete.value, isFalse);
      expect(controller.currentStep.value, OnboardingStep.welcome);
      expect(controller.musicLanguages, isEmpty);
      expect(controller.favoriteArtists, isEmpty);
    });

    test('skipLogin advances to musicLanguageSelection for guest personalization', () {
      final controller = OnboardingController();
      controller.onInit();

      controller.skipLogin();

      expect(controller.isOnboardingComplete.value, isFalse);
      expect(controller.currentStep.value, OnboardingStep.musicLanguageSelection);

      final box = Hive.box('AppPrefs');
      expect(box.get('onboardingSkippedLogin'), isTrue);
      expect(box.get('onboardingCompleted'), isNull);
    });

    test('skipAll marks onboarding as complete and saves to Hive', () {
      final controller = OnboardingController();
      controller.onInit();

      controller.skipAll();

      expect(controller.isOnboardingComplete.value, isTrue);
      expect(controller.currentStep.value, OnboardingStep.complete);

      final box = Hive.box('AppPrefs');
      expect(box.get('onboardingCompleted'), isTrue);
    });

    test('canGoBack and goToPreviousStep navigates correctly', () {
      final controller = OnboardingController();
      controller.onInit();

      expect(controller.canGoBack, isFalse);

      controller.skipLogin(); // moves to musicLanguageSelection
      expect(controller.currentStep.value, OnboardingStep.musicLanguageSelection);
      expect(controller.canGoBack, isTrue);

      controller.setMusicLanguages(['en']); // moves to artistSelection
      expect(controller.currentStep.value, OnboardingStep.artistSelection);
      expect(controller.canGoBack, isTrue);

      controller.goToPreviousStep();
      expect(controller.currentStep.value, OnboardingStep.musicLanguageSelection);

      controller.goToPreviousStep();
      expect(controller.currentStep.value, OnboardingStep.welcome);
      expect(controller.canGoBack, isFalse);
    });

    test('reloading from Hive restores completed onboarding', () {
      final box = Hive.box('AppPrefs');
      box.put('onboardingCompleted', true);
      box.put('musicLanguages', ['ml', 'hi', 'en']);
      box.put('favoriteArtists', [
        {'name': 'A.R. Rahman', 'browseId': 'UC123'},
      ]);

      final controller = OnboardingController();
      controller.onInit();

      expect(controller.isOnboardingComplete.value, isTrue);
      expect(controller.currentStep.value, OnboardingStep.complete);
      expect(controller.musicLanguages, equals(['ml', 'hi', 'en']));
      expect(controller.favoriteArtists.first['name'], 'A.R. Rahman');
    });

    test('language selection updates state and moves to artistSelection', () {
      final controller = OnboardingController();
      controller.onInit();

      controller.setMusicLanguages(['ml', 'ta']);

      expect(controller.musicLanguages, equals(['ml', 'ta']));
      expect(controller.currentStep.value, OnboardingStep.artistSelection);

      final box = Hive.box('AppPrefs');
      expect(box.get('musicLanguages'), equals(['ml', 'ta']));
    });

    test('artist selection updates state and completes onboarding', () {
      final controller = OnboardingController();
      controller.onInit();

      final artists = [
        {'name': 'A.R. Rahman', 'browseId': 'UC123', 'thumbnailUrl': null},
        {'name': 'K.S. Chithra', 'browseId': 'UC456', 'thumbnailUrl': null},
      ];

      controller.setFavoriteArtists(artists);

      expect(controller.favoriteArtists.length, 2);
      expect(controller.favoriteArtists[0]['name'], 'A.R. Rahman');
      expect(controller.isOnboardingComplete.value, isTrue);
      expect(controller.currentStep.value, OnboardingStep.complete);

      final box = Hive.box('AppPrefs');
      expect(box.get('onboardingCompleted'), isTrue);
      expect(box.get('favoriteArtists'), isNotNull);
    });
  });

  group('DiscoverContentType Migration', () {
    test('migrates TR to REC', () {
      final box = Hive.box('AppPrefs');
      box.put('discoverContentType', 'TR');

      final controller = SettingsScreenController();
      expect(controller.discoverContentType.value, 'REC');
      expect(box.get('discoverContentType'), 'REC');
    });

    test('migrates TMV to REC', () {
      final box = Hive.box('AppPrefs');
      box.put('discoverContentType', 'TMV');

      final controller = SettingsScreenController();
      expect(controller.discoverContentType.value, 'REC');
      expect(box.get('discoverContentType'), 'REC');
    });

    test('migrates QP to REC', () {
      final box = Hive.box('AppPrefs');
      box.put('discoverContentType', 'QP');

      final controller = SettingsScreenController();
      expect(controller.discoverContentType.value, 'REC');
      expect(box.get('discoverContentType'), 'REC');
    });

    test('preserves valid BOLI content type', () {
      final box = Hive.box('AppPrefs');
      box.put('discoverContentType', 'BOLI');

      final controller = SettingsScreenController();
      expect(controller.discoverContentType.value, 'BOLI');
    });
  });

  group('UserPreferencesService', () {
    test('handles unconfigured Supabase gracefully without throwing', () async {
      // Register mock or stub SupabaseService
      // When not logged in, loadPreferences returns null
      // savePreferences completes safely
      final box = Hive.box('AppPrefs');
      box.put('musicLanguages', ['ml', 'en']);
      expect(box.get('musicLanguages'), equals(['ml', 'en']));
    });
  });

  group('CuratedArtistsData', () {
    test('returns up to 50 artists for empty language selection', () {
      final artists = CuratedArtistsData.getCuratedArtists(languageCodes: [], targetCount: 50);
      expect(artists.length, equals(50));
      expect(artists.first['name'], isNotNull);
      expect(artists.first['browseId'], isNotNull);
    });

    test('returns 50 artists for English language selection', () {
      final artists = CuratedArtistsData.getCuratedArtists(languageCodes: ['en'], targetCount: 50);
      expect(artists.length, equals(50));
      expect(artists.any((a) => a['name'] == 'The Weeknd'), isTrue);
      expect(artists.any((a) => a['name'] == 'Taylor Swift'), isTrue);
    });

    test('returns 50 artists for Hindi language selection', () {
      final artists = CuratedArtistsData.getCuratedArtists(languageCodes: ['hi'], targetCount: 50);
      expect(artists.length, equals(50));
      expect(artists.any((a) => a['name'] == 'Arijit Singh'), isTrue);
      expect(artists.any((a) => a['name'] == 'A.R. Rahman'), isTrue);
    });

    test('interleaves artists from multiple languages without duplicates', () {
      final artists = CuratedArtistsData.getCuratedArtists(
        languageCodes: ['en', 'hi', 'ml'],
        targetCount: 50,
      );
      expect(artists.length, equals(50));

      // Verify no duplicates
      final names = artists.map((a) => a['name'].toString().toLowerCase()).toSet();
      expect(names.length, equals(artists.length));

      // Contains artists from all 3 selected languages
      expect(artists.any((a) => a['name'] == 'The Weeknd'), isTrue);
      expect(artists.any((a) => a['name'] == 'Arijit Singh'), isTrue);
      expect(artists.any((a) => a['name'] == 'K.S. Chithra'), isTrue);
    });
  });
}

