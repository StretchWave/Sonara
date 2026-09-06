import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/matching/track_candidate.dart';
import 'package:sonara/services/providers/matching/track_scorer.dart';
import 'package:sonara/services/providers/models/match_decision.dart';
import 'package:sonara/services/providers/song_query.dart';

void main() {
  group('MatchDecision & evaluateCandidate', () {
    const query = SongQuery(
      mediaId: 'q-1',
      title: 'Starboy',
      artists: ['The Weeknd', 'Daft Punk'],
      album: 'Starboy',
      durationMs: 230000,
      isrc: 'USUM71605332',
    );

    test('exact match produces verified MatchDecision with explanations', () {
      const candidate = TrackCandidate(
        trackId: 'c-exact',
        title: 'Starboy',
        artists: ['The Weeknd', 'Daft Punk'],
        album: 'Starboy',
        durationMs: 230000,
        isrc: 'USUM71605332',
        hires: true,
      );

      final decision = evaluateCandidate(candidate: candidate, query: query);
      expect(decision.accepted, isTrue);
      expect(decision.verificationLevel, VerificationLevel.verified);
      expect(decision.isrcMatch, isTrue);
      expect(decision.scoreBreakdown.containsKey('isrc'), isTrue);
      expect(decision.scoreBreakdown.containsKey('artist'), isTrue);
      expect(decision.scoreBreakdown.containsKey('duration'), isTrue);
      expect(decision.explanation, contains('Exact ISRC'));
      expect(decision.summary, contains('Verified'));
    });

    test('version mismatch produces rejected MatchDecision with explanation', () {
      const candidate = TrackCandidate(
        trackId: 'c-remix',
        title: 'Starboy (Kygo Remix)',
        artists: ['The Weeknd'],
        album: 'Starboy',
        durationMs: 230000,
      );

      final decision = evaluateCandidate(candidate: candidate, query: query);
      expect(decision.accepted, isFalse);
      expect(decision.verificationLevel, VerificationLevel.rejected);
      expect(decision.reasons.first, contains('Version mismatch'));
    });

    test('pickBestMatchWithDecision returns candidate and decision pair', () {
      const candidate1 = TrackCandidate(
        trackId: 'c-1',
        title: 'Starboy',
        artists: ['The Weeknd'],
        album: 'Starboy',
        durationMs: 230000,
      );
      const candidate2 = TrackCandidate(
        trackId: 'c-2',
        title: 'Starboy',
        artists: ['Wrong Artist'],
        album: 'Starboy',
        durationMs: 230000,
      );

      final result = pickBestMatchWithDecision([candidate2, candidate1], query);
      expect(result, isNotNull);
      expect(result!.candidate.trackId, 'c-1');
      expect(result.decision.accepted, isTrue);
      expect(result.decision.artistCompatible, isTrue);
    });
  });
}
