import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/utils/language_filter.dart';

void main() {
  group('LanguageFilter', () {
    test('allows English songs when user selected only English', () {
      expect(
        LanguageFilter.isSongAllowed(
          title: 'Dark Red',
          artist: 'Steve Lacy',
          allowedLanguages: ['en'],
        ),
        isTrue,
      );

      expect(
        LanguageFilter.isSongAllowed(
          title: 'shut up',
          artist: 'Greyson Chance',
          allowedLanguages: ['en'],
        ),
        isTrue,
      );

      expect(
        LanguageFilter.isSongAllowed(
          title: 'Carry You Home',
          artist: 'Alex Warren',
          allowedLanguages: ['en'],
        ),
        isTrue,
      );
    });

    test('rejects Indian playback songs when user selected only English', () {
      expect(
        LanguageFilter.isSongAllowed(
          title: 'Raanjhan',
          artist: 'Parampara Tandon',
          allowedLanguages: ['en'],
        ),
        isFalse,
      );

      expect(
        LanguageFilter.isSongAllowed(
          title: 'Kaise Hua',
          artist: 'Vishal Mishra',
          allowedLanguages: ['en'],
        ),
        isFalse,
      );

      expect(
        LanguageFilter.isSongAllowed(
          title: 'O Rangrez',
          artist: 'Shreya Ghoshal',
          allowedLanguages: ['en'],
        ),
        isFalse,
      );

      expect(
        LanguageFilter.isSongAllowed(
          title: 'Tum Hi Ho',
          artist: 'Arijit Singh',
          allowedLanguages: ['en'],
        ),
        isFalse,
      );
    });

    test('rejects non-Latin scripts when user selected only English', () {
      expect(
        LanguageFilter.isSongAllowed(
          title: 'समझो ना कुछ तो समझो ना',
          artist: 'VP9008 Vikas',
          allowedLanguages: ['en'],
        ),
        isFalse,
      );

      expect(
        LanguageFilter.isSongAllowed(
          title: 'आईने के सौ टुकड़े',
          artist: 'Jitendra Kumar',
          allowedLanguages: ['en'],
        ),
        isFalse,
      );
    });

    test('rejects regional playlists by keyword when user selected only English', () {
      expect(
        LanguageFilter.isContentAllowed(
          title: 'Top 20 Telugu hits',
          subtitle: 'Karan Panikatti',
          allowedLanguages: ['en'],
        ),
        isFalse,
      );

      expect(
        LanguageFilter.isContentAllowed(
          title: 'Uncut Bollywood',
          subtitle: 'Arijit Singh',
          allowedLanguages: ['en'],
        ),
        isFalse,
      );

      expect(
        LanguageFilter.isContentAllowed(
          title: 'Ghazal Essentials',
          subtitle: 'Jagjit Singh',
          allowedLanguages: ['en'],
        ),
        isFalse,
      );

      expect(
        LanguageFilter.isContentAllowed(
          title: 'Pop Certified',
          subtitle: 'Sabrina Carpenter',
          allowedLanguages: ['en'],
        ),
        isTrue,
      );
    });

    test('allows Indian songs when user explicitly selected Hindi', () {
      expect(
        LanguageFilter.isSongAllowed(
          title: 'Raanjhan',
          artist: 'Parampara Tandon',
          allowedLanguages: ['en', 'hi'],
        ),
        isTrue,
      );

      expect(
        LanguageFilter.isSongAllowed(
          title: 'समझो ना कुछ तो समझो ना',
          artist: 'VP9008 Vikas',
          allowedLanguages: ['en', 'hi'],
        ),
        isTrue,
      );
    });

    test('allows artist from favorite artists even if regional language unselected', () {
      expect(
        LanguageFilter.isSongAllowed(
          title: 'O Rangrez',
          artist: 'Shreya Ghoshal',
          allowedLanguages: ['en'],
          favoriteArtistNames: {'shreya ghoshal'},
        ),
        isTrue,
      );
    });

    test('matchesLanguage identifies English correctly', () {
      expect(LanguageFilter.matchesLanguage('Steve Lacy', 'en'), isTrue);
      expect(LanguageFilter.matchesLanguage('Arijit Singh', 'en'), isFalse);
      expect(LanguageFilter.matchesLanguage('Uncut Bollywood', 'en'), isFalse);
    });
  });
}
