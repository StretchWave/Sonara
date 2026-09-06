import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/matching/track_candidate.dart';
import 'package:sonara/services/providers/matching/track_scorer.dart';
import 'package:sonara/services/providers/song_query.dart';

const _query = SongQuery(
  mediaId: 'some-id',
  title: 'Blinding Lights',
  artists: ['The Weeknd'],
  album: 'After Hours',
  durationMs: 200000,
);

const _exact = TrackCandidate(
  trackId: 'exact',
  title: 'Blinding Lights',
  artists: ['The Weeknd'],
  album: 'After Hours',
  durationMs: 200000,
);

void main() {
  group('scoreCandidate', () {
    test('exact title/artist/album/duration scores above threshold', () {
      final score = scoreCandidate(candidate: _exact, query: _query);
      expect(score, greaterThan(0));
      expect(score, greaterThanOrEqualTo(minAcceptableScore));
    });

    test('wrong artist is rejected', () {
      final score = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'wrong-artist',
          title: 'Blinding Lights',
          artists: ['Someone Else'],
          album: 'After Hours',
          durationMs: 200000,
        ),
        query: _query,
      );
      expect(score, rejectScore);
    });

    test('version mismatch (remix) is rejected when the query has none', () {
      final score = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'remix',
          title: 'Blinding Lights (Remix)',
          artists: ['The Weeknd'],
          album: 'After Hours',
          durationMs: 200000,
        ),
        query: _query,
      );
      expect(score, rejectScore);
    });

    test('cover version is rejected', () {
      final score = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'cover',
          title: 'Blinding Lights Cover',
          artists: ['The Weeknd'],
          album: 'After Hours',
          durationMs: 200000,
        ),
        query: _query,
      );
      expect(score, rejectScore);
    });

    test('mixed version is rejected', () {
      final score = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'mixed',
          title: 'Blinding Lights (Mixed)',
          artists: ['The Weeknd'],
          album: 'After Hours',
          durationMs: 200000,
        ),
        query: _query,
      );
      expect(score, rejectScore);
    });

    test('slowed + reverb version is rejected', () {
      final score = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'slowed-reverb',
          title: 'Blinding Lights (Slowed + Reverb)',
          artists: ['The Weeknd'],
          album: 'After Hours',
          durationMs: 200000,
        ),
        query: _query,
      );
      expect(score, rejectScore);
    });

    test('nightcore and bass boosted versions are rejected', () {
      for (final title in ['Blinding Lights (Nightcore)',
          'Blinding Lights (Bass Boosted)']) {
        final score = scoreCandidate(
          candidate: TrackCandidate(
            trackId: 'v',
            title: title,
            artists: const ['The Weeknd'],
            album: 'After Hours',
            durationMs: 200000,
          ),
          query: _query,
        );
        expect(score, rejectScore, reason: 'should reject $title');
      }
    });

    test('an explicit Original Mix is accepted, not treated as a mismatch', () {
      final score = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'original-mix',
          title: 'Blinding Lights (Original Mix)',
          artists: ['The Weeknd'],
          album: 'After Hours',
          durationMs: 200000,
        ),
        query: _query,
      );
      expect(score, greaterThanOrEqualTo(minAcceptableScore));
    });

    test('the plain original outranks an Original Mix variant', () {
      const plain = TrackCandidate(
        trackId: 'plain',
        title: 'Blinding Lights',
        artists: ['The Weeknd'],
        album: 'After Hours',
        durationMs: 200000,
      );
      const mixVariant = TrackCandidate(
        trackId: 'mix-variant',
        title: 'Blinding Lights (Original Mix)',
        artists: ['The Weeknd'],
        album: 'After Hours',
        durationMs: 200000,
      );
      final best = pickBestMatch(const [mixVariant, plain], _query);
      expect(best?.trackId, 'plain');
    });

    test('words inside titles are not mistaken for version tokens', () {
      // "Undercover" contains "cover" and "Deliverance" contains "live"
      // as substrings — whole-word matching must not reject these.
      for (final title in ['Undercover', 'Deliverance', 'Cover Me']) {
        final score = scoreCandidate(
          candidate: TrackCandidate(
            trackId: 't',
            title: title,
            artists: const ['The Weeknd'],
            album: 'After Hours',
            durationMs: 200000,
          ),
          query: SongQuery(
            mediaId: 'q',
            title: title,
            artists: const ['The Weeknd'],
            album: 'After Hours',
            durationMs: 200000,
          ),
        );
        expect(score, greaterThanOrEqualTo(minAcceptableScore),
            reason: 'should accept $title');
      }
    });

    test('a version descriptor hidden in the album is rejected', () {
      final score = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'mixed-album',
          title: 'Blinding Lights',
          artists: ['The Weeknd'],
          album: 'After Hours (Continuous Mix)',
          durationMs: 200000,
        ),
        query: _query,
      );
      expect(score, rejectScore);
    });

    test('a wildly different duration is rejected as a wrong recording', () {
      final score = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'too-short-hard',
          title: 'Blinding Lights',
          artists: ['The Weeknd'],
          album: 'After Hours',
          durationMs: 70000, // 3:20 -> 1:10, ~65% shorter
        ),
        query: _query,
      );
      expect(score, rejectScore);
    });

    test('an ISRC match rescues a candidate even with a long duration', () {
      final score = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'isrc-long',
          title: 'Blinding Lights',
          artists: ['The Weeknd'],
          album: 'After Hours',
          isrc: 'USUM72020701',
          durationMs: 70000,
        ),
        query: const SongQuery(
          mediaId: 'x',
          title: 'Blinding Lights',
          artists: ['The Weeknd'],
          album: 'After Hours',
          isrc: 'USUM72020701',
          durationMs: 200000,
        ),
      );
      expect(score, greaterThanOrEqualTo(minAcceptableScore));
    });

    test('ISRC equality rescues an otherwise weak title match', () {
      final score = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'isrc-win',
          title: 'Something Completely Different',
          artists: ['The Weeknd'],
          album: 'Other Album',
          isrc: 'USUM72020701',
          durationMs: 200000,
        ),
        query: const SongQuery(
          mediaId: 'x',
          title: 'Blinding Lights',
          artists: ['The Weeknd'],
          album: 'After Hours',
          isrc: 'USUM72020701',
          durationMs: 200000,
        ),
      );
      expect(score, greaterThanOrEqualTo(minAcceptableScore));
    });

    test('a duration more than a few seconds off is rejected as a different recording', () {
      // A cover/mix/edit almost always differs in length from the original.
      // 30s shorter must not be accepted even when title/artist/album match.
      final score = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'too-short',
          title: 'Blinding Lights',
          artists: ['The Weeknd'],
          album: 'After Hours',
          durationMs: 170000, // 30s shorter than the query
        ),
        query: _query,
      );
      expect(score, rejectScore);
    });

    test('a same-length cover within a few seconds still matches (indistinguishable)', () {
      // A faithful cover within the 5s tolerance is indistinguishable from
      // the original by metadata alone — accept it (the title/version
      // checks handle explicitly-labelled covers).
      final score = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'close-cover',
          title: 'Blinding Lights',
          artists: ['The Weeknd'],
          album: 'After Hours',
          durationMs: 197000, // 3s shorter
        ),
        query: _query,
      );
      expect(score, greaterThanOrEqualTo(minAcceptableScore));
    });
  });

  group('pickBestMatch', () {
    test('picks the highest-scoring candidate', () {
      final best = pickBestMatch(
        const [
          TrackCandidate(
            trackId: 'weak',
            title: 'Blinding Lights',
            artists: ['Other Artist'],
            album: 'x',
            durationMs: 200000,
          ),
          TrackCandidate(
            trackId: 'strong',
            title: 'Blinding Lights',
            artists: ['The Weeknd'],
            album: 'After Hours',
            durationMs: 200000,
          ),
        ],
        _query,
      );
      expect(best?.trackId, 'strong');
    });

    test('returns null when nothing is acceptable', () {
      final best = pickBestMatch(
        const [
          TrackCandidate(
            trackId: 'wrong-artist',
            title: 'Blinding Lights',
            artists: ['Someone Else'],
            album: 'After Hours',
            durationMs: 200000,
          ),
        ],
        _query,
      );
      expect(best, isNull);
    });
  });
}
