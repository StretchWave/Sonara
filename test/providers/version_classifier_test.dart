import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/models/version_type.dart';

void main() {
  group('VersionClassifier', () {
    test('classifies standard versions', () {
      expect(VersionClassifier.classify('Blinding Lights'), VersionType.unknown);
      expect(VersionClassifier.classify('Song (Original Mix)'), VersionType.original);
      expect(VersionClassifier.classify('Song (Album Version)'), VersionType.albumVersion);
    });

    test('classifies live versions', () {
      expect(VersionClassifier.classify('Hotel California (Live)'), VersionType.live);
      expect(VersionClassifier.classify('Song', 'Live at Wembley'), VersionType.live);
    });

    test('classifies acoustic and instrumental', () {
      expect(VersionClassifier.classify('Layla (Acoustic)'), VersionType.acoustic);
      expect(VersionClassifier.classify('Song (Instrumental)'), VersionType.instrumental);
    });

    test('classifies remix, edit, speed mods', () {
      expect(VersionClassifier.classify('Song (Remix)'), VersionType.remix);
      expect(VersionClassifier.classify('Song (Radio Edit)'), VersionType.radioEdit);
      expect(VersionClassifier.classify('Song (Slowed + Reverb)'), VersionType.slowed);
      expect(VersionClassifier.classify('Song (Sped Up)'), VersionType.spedUp);
      expect(VersionClassifier.classify('Song (Nightcore)'), VersionType.nightcore);
    });

    test('detects version mismatch', () {
      expect(
        VersionClassifier.hasVersionMismatch(
          'Blinding Lights',
          null,
          'Blinding Lights (Remix)',
          null,
        ),
        isTrue,
      );

      // Same version is not a mismatch
      expect(
        VersionClassifier.hasVersionMismatch(
          'Blinding Lights (Live)',
          null,
          'Blinding Lights (Live)',
          null,
        ),
        isFalse,
      );

      // Original mix against standard is not a mismatch
      expect(
        VersionClassifier.hasVersionMismatch(
          'Blinding Lights',
          null,
          'Blinding Lights (Original Mix)',
          null,
        ),
        isFalse,
      );
    });

    test('does not misidentify whole words inside other words', () {
      expect(VersionClassifier.classify('Undercover'), VersionType.unknown);
      expect(VersionClassifier.classify('Deliverance'), VersionType.unknown);
      expect(VersionClassifier.classify('Remixology'), VersionType.unknown);
    });
  });
}
