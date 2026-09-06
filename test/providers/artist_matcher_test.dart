import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/matching/artist_matcher.dart';

void main() {
  group('ArtistMatcher', () {
    test('exact primary artist match', () {
      final result = matchArtists(
        wantedArtists: ['The Weeknd'],
        candidateArtists: ['The Weeknd'],
      );
      expect(result.isCompatible, isTrue);
      expect(result.primaryMatches, isTrue);
      expect(result.exactMatchesCount, 1);
      expect(result.scoreContribution, greaterThanOrEqualTo(220));
    });

    test('primary artist matches when candidate has featured artist', () {
      final result = matchArtists(
        wantedArtists: ['Eminem'],
        candidateArtists: ['Eminem feat. Rihanna'],
      );
      expect(result.isCompatible, isTrue);
      expect(result.primaryMatches, isTrue);
      expect(result.scoreContribution, greaterThan(0));
    });

    test('missing featured artist is not rejected, only penalized', () {
      final result = matchArtists(
        wantedArtists: ['Drake', '21 Savage'],
        candidateArtists: ['Drake'],
      );
      expect(result.isCompatible, isTrue);
      expect(result.primaryMatches, isTrue);
    });

    test('completely different artist is rejected', () {
      final result = matchArtists(
        wantedArtists: ['Taylor Swift'],
        candidateArtists: ['Kanye West'],
      );
      expect(result.isCompatible, isFalse);
      expect(result.primaryMatches, isFalse);
    });

    test('handles collaborations with ampersand and x', () {
      final result = matchArtists(
        wantedArtists: ['David Guetta', 'Bebe Rexha'],
        candidateArtists: ['David Guetta & Bebe Rexha'],
      );
      expect(result.isCompatible, isTrue);
      expect(result.exactMatchesCount, greaterThanOrEqualTo(1));
    });
  });
}
