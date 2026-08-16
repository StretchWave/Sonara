import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/spotify/track_normalizer.dart';

void main() {
  group('normalizeTitleForComparison', () {
    test('removes featuring sections', () {
      expect(normalizeTitleForComparison('Song feat. Artist'), 'song');
      expect(normalizeTitleForComparison('Song ft. Artist'), 'song');
      expect(normalizeTitleForComparison('Song featuring Artist'), 'song');
      expect(normalizeTitleForComparison('Song (feat. Artist)'), 'song');
      expect(normalizeTitleForComparison('Song (ft Artist)'), 'song');
    });

    test('removes editorial tags', () {
      expect(normalizeTitleForComparison('Song (Official Audio)'), 'song');
      expect(normalizeTitleForComparison('Song (Official Video)'), 'song');
      expect(normalizeTitleForComparison('Song (Official Music Video)'), 'song');
      expect(normalizeTitleForComparison('Song (Lyrics)'), 'song');
      expect(normalizeTitleForComparison('Song (HD)'), 'song');
      expect(normalizeTitleForComparison('Song (4K)'), 'song');
      expect(normalizeTitleForComparison('Song (Official Audio) HD'), 'song');
    });

    test('removes remaster tags but keeps the rest of the title', () {
      expect(normalizeTitleForComparison('Song (Remastered)'), 'song');
      expect(normalizeTitleForComparison('Song (Remastered 2021)'), 'song');
      expect(normalizeTitleForComparison('Song (2021 Remaster)'), 'song');
    });

    test('preserves version markers so versions never collapse', () {
      expect(normalizeTitleForComparison('Song - Live'), 'song live');
      expect(normalizeTitleForComparison('Song - Acoustic'), 'song acoustic');
      expect(normalizeTitleForComparison('Song - Remix'), 'song remix');
      expect(normalizeTitleForComparison('Song (Radio Edit)'), 'song radio edit');
      expect(normalizeTitleForComparison('Song (Extended Mix)'),
          'song extended mix');
      expect(normalizeTitleForComparison('Song'),
          isNot(normalizeTitleForComparison('Song - Live')));
      expect(normalizeTitleForComparison('Song'),
          isNot(normalizeTitleForComparison('Song - Remix')));
    });

    test('normalizes case, punctuation and whitespace', () {
      expect(normalizeTitleForComparison('  SONG!  (feat. X) '), 'song');
      expect(normalizeTitleForComparison('Blinding Lights'),
          normalizeTitleForComparison('blinding-lights'));
    });
  });

  group('hasVersionMarker', () {
    test('detects version markers', () {
      expect(hasVersionMarker('Song - Live'), isTrue);
      expect(hasVersionMarker('Song (Acoustic)'), isTrue);
      expect(hasVersionMarker('Song Remix'), isTrue);
      expect(hasVersionMarker('Song (Radio Edit)'), isTrue);
      expect(hasVersionMarker('Song (Extended Mix)'), isTrue);
    });

    test('does not flag plain titles', () {
      expect(hasVersionMarker('Song'), isFalse);
      expect(hasVersionMarker('Live from New York'), isTrue);
      expect(hasVersionMarker('Song - Live From New York'), isTrue);
      expect(hasVersionMarker('Radioactive'), isFalse);
    });
  });

  group('textSimilarity', () {
    test('exact match is 1.0', () {
      expect(textSimilarity('blinding lights', 'Blinding Lights'), 1.0);
      expect(textSimilarity('song', 'song'), 1.0);
    });

    test('containment is high but not perfect', () {
      final sim = textSimilarity('song', 'song live');
      expect(sim, greaterThan(0.8));
      expect(sim, lessThan(1.0));
    });

    test('disjoint titles score zero', () {
      expect(textSimilarity('blinding lights', 'shape of you'), 0.0);
    });

    test('partial token overlap scores between', () {
      final sim = textSimilarity('blinding lights', 'blinding lights remix');
      expect(sim, greaterThan(0.8));
      final partial = textSimilarity('song one', 'song two');
      expect(partial, greaterThan(0.0));
      expect(partial, lessThan(0.85));
    });
  });

  group('stripFeaturing', () {
    test('removes feat sections for search queries', () {
      expect(stripFeaturing('Song feat. Artist'), 'Song');
      expect(stripFeaturing('Song (feat. Artist)'), 'Song');
      expect(stripFeaturing('Song'), 'Song');
    });
  });
}
