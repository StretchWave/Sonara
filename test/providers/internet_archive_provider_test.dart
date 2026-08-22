import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/internet_archive_provider.dart';
import 'package:sonara/services/providers/song_query.dart';

void main() {
  group('normalizeTitle', () {
    test('strips punctuation, case and container noise', () {
      expect(
        InternetArchiveProvider.normalizeTitle('01. Scarlet Begonias (Live) - CD1'),
        'scarlet begonias live',
      );
      expect(
        InternetArchiveProvider.normalizeTitle('Jazz at the Pawnshop'),
        'jazz at the pawnshop',
      );
    });
  });

  group('parseHiresHints', () {
    test('detects 24-96 and 16-44 patterns', () {
      expect(InternetArchiveProvider.parseHiresHints('gd73_t01_24-96.flac'),
          (24, 96));
      expect(InternetArchiveProvider.parseHiresHints('track01_16-44.flac'),
          (16, 44));
    });

    test('ignores unrelated numbers', () {
      expect(InternetArchiveProvider.parseHiresHints('song_1991_ver2.flac'),
          isNull);
    });
  });

  group('scoreItem', () {
    const provider = InternetArchiveProvider();
    const query = SongQuery(
      mediaId: 'x',
      title: 'Scarlet Begonias',
      artists: ['Grateful Dead'],
      durationMs: 400000, // ~6:40
    );

    test('matches a track inside a concert item and prefers SBD', () {
      final sbd = provider.scoreItem(
        {
          'identifier': 'gd1977-05-08.sbd.miller.flac16',
          'title': 'Grateful Dead Live at Cornell 1977',
          'creator': 'Grateful Dead',
        },
        const [
          FlacFile(name: '01. Jack Straw.flac', length: '301'),
          FlacFile(name: '02. Scarlet Begonias.flac', length: '402'),
        ],
        query,
      );
      expect(sbd, isNotNull);
      expect(sbd!.file.name, '02. Scarlet Begonias.flac');
      expect(sbd.soundboard, isTrue);

      // Same item without SBD in the identifier scores lower.
      final aud = provider.scoreItem(
        {
          'identifier': 'gd1977-05-08.aud.barry.flac',
          'title': 'Grateful Dead Live at Cornell 1977',
          'creator': 'Grateful Dead',
        },
        const [
          FlacFile(name: '01. Jack Straw.flac', length: '301'),
          FlacFile(name: '02. Scarlet Begonias.flac', length: '402'),
        ],
        query,
      );
      expect(aud, isNotNull);
      expect(aud!.score, lessThan(sbd.score));
      expect(aud.soundboard, isFalse);
    });

    test('rejects items whose artist does not match', () {
      final result = provider.scoreItem(
        {
          'identifier': 'some-other-band-1977',
          'title': 'Other Band Live 1977',
          'creator': 'Some Other Band',
        },
        const [FlacFile(name: '02. Scarlet Begonias.flac', length: '402')],
        query,
      );
      expect(result, isNull);
    });

    test('rejects when no file name matches the song', () {
      final result = provider.scoreItem(
        {
          'identifier': 'gd1977-05-08.sbd.miller.flac16',
          'title': 'Grateful Dead Live 1977',
          'creator': 'Grateful Dead',
        },
        const [
          FlacFile(name: '01. Jack Straw.flac', length: '301'),
          FlacFile(name: '02. Sugaree.flac', length: '402'),
        ],
        query,
      );
      expect(result, isNull);
    });

    test('accepts a same-name file with slightly different duration', () {
      final result = provider.scoreItem(
        {
          'identifier': 'gd1977-05-08.sbd.miller.flac16',
          'title': 'Grateful Dead Live 1977',
          'creator': 'Grateful Dead',
        },
        const [FlacFile(name: 'Scarlet Begonias.flac', length: '408')],
        query,
      );
      expect(result, isNotNull);
      expect(result!.score, greaterThan(400));
    });

    test('falls back to item-title match for single-work releases', () {
      final result = provider.scoreItem(
        {
          'identifier': 'arne-domnerus-band-jazz-at-the-pawnshop',
          'title': 'Arne Domnérus Band - Jazz At The Pawnshop',
          'creator': 'Arne Domnérus',
        },
        const [
          FlacFile(name: '1 - Limehouse Blues.flac', length: '300'),
          FlacFile(name: '2 - High Life.flac', length: '290'),
        ],
        const SongQuery(
          mediaId: 'x',
          title: 'Jazz at the Pawnshop',
          artists: ['Arne Domnérus'],
        ),
      );
      expect(result, isNotNull);
      expect(result!.file.name, '1 - Limehouse Blues.flac');
      expect(result.score, lessThan(500));
    });

    test('prefers 24-bit files over 16-bit within the same item', () {
      final result = provider.scoreItem(
        {
          'identifier': 'gd1977-05-08.sbd.miller.flac16',
          'title': 'Grateful Dead Live 1977',
          'creator': 'Grateful Dead',
        },
        const [
          FlacFile(name: '02. Scarlet Begonias 16-44.flac', length: '402'),
          FlacFile(name: '02. Scarlet Begonias 24-96.flac', length: '402'),
        ],
        query,
      );
      expect(result, isNotNull);
      expect(result!.file.name, contains('24-96'));
    });
  });
}
