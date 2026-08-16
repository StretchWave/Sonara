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

    test('an implausible duration is heavily penalized', () {
      final plausible = scoreCandidate(candidate: _exact, query: _query);
      final implausible = scoreCandidate(
        candidate: const TrackCandidate(
          trackId: 'too-short',
          title: 'Blinding Lights',
          artists: ['The Weeknd'],
          album: 'After Hours',
          durationMs: 170000, // 30s shorter than the query
        ),
        query: _query,
      );
      expect(implausible, lessThan(plausible));
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
