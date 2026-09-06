import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/models/version_type.dart';

void main() {
  group('Property-based and combinatorial version testing', () {
    const baseTitles = [
      'Numb',
      'Bohemian Rhapsody',
      'Starboy',
      'Lose Yourself',
      'Shape of You',
      'Hotel California',
      'Billie Jean',
    ];

    const versionTags = {
      VersionType.live: [
        '(Live)',
        '[Live]',
        '- Live',
        '(Live at Wembley)',
        '[Live in Paris 1998]',
        '- Live from Tokyo',
      ],
      VersionType.acoustic: [
        '(Acoustic)',
        '[Acoustic]',
        '- Acoustic Version',
        '(Acoustic Mix)',
      ],
      VersionType.instrumental: [
        '(Instrumental)',
        '[Instrumental]',
        '- Instrumental Version',
      ],
      VersionType.karaoke: [
        '(Karaoke)',
        '[Karaoke]',
      ],
      VersionType.remix: [
        '(Remix)',
        '[Remix]',
        '(Club Remix)',
        '- Tiësto Remix',
        '(VIP Mix)',
        '- Club Mix',
      ],
      VersionType.radioEdit: [
        '(Radio Edit)',
        '[Radio Edit]',
        '- Radio Version',
      ],
      VersionType.extended: [
        '(Extended Mix)',
        '[Extended Version]',
      ],
      VersionType.slowed: [
        '(Slowed)',
        '[Slowed + Reverb]',
        '- Slowed Down',
      ],
      VersionType.spedUp: [
        '(Sped Up)',
        '[Sped Up Version]',
      ],
      VersionType.nightcore: [
        '(Nightcore)',
        '[Nightcore Edit]',
      ],
    };

    test('all version descriptor formats correctly classify their VersionType', () {
      for (final entry in versionTags.entries) {
        final expectedType = entry.key;
        for (final tag in entry.value) {
          for (final base in baseTitles) {
            final title = '$base $tag';
            final classified = VersionClassifier.classify(title);
            expect(
              classified,
              expectedType,
              reason: 'Failed for title: "$title", expected $expectedType but got $classified',
            );
          }
        }
      }
    });

    test('symmetry: hasVersionMismatch(A, B) == hasVersionMismatch(B, A) for incompatible versions', () {
      for (final type1 in versionTags.keys) {
        for (final type2 in versionTags.keys) {
          if (type1 == type2) continue;
          final tag1 = versionTags[type1]!.first;
          final tag2 = versionTags[type2]!.first;

          for (final base in baseTitles.take(3)) {
            final title1 = '$base $tag1';
            final title2 = '$base $tag2';

            final mismatch1 = VersionClassifier.hasVersionMismatch(title1, null, title2, null);
            final mismatch2 = VersionClassifier.hasVersionMismatch(title2, null, title1, null);

            expect(
              mismatch1,
              mismatch2,
              reason: 'Symmetry violation between "$title1" and "$title2"',
            );
            expect(
              mismatch1,
              isTrue,
              reason: 'Expected mismatch between $type1 and $type2',
            );
          }
        }
      }
    });

    test('unlabeled base title always mismatches special versions (anti-substitution)', () {
      for (final entry in versionTags.entries) {
        final tag = entry.value.first;
        for (final base in baseTitles) {
          final candidate = '$base $tag';
          final mismatch = VersionClassifier.hasVersionMismatch(
            base,
            null,
            candidate,
            null,
          );
          expect(
            mismatch,
            isTrue,
            reason: 'Base "$base" must NOT match special candidate "$candidate"',
          );
        }
      }
    });

    test('case variations (upper, lower, mixed) classify identically', () {
      for (final entry in versionTags.entries) {
        final expectedType = entry.key;
        final rawTag = entry.value.first;

        for (final tag in [
          rawTag.toUpperCase(),
          rawTag.toLowerCase(),
        ]) {
          final title = 'Song $tag';
          expect(
            VersionClassifier.classify(title),
            expectedType,
            reason: 'Case insensitivity failed for "$title"',
          );
        }
      }
    });
  });
}
