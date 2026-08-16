import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/spotify/spotify_api_client.dart';
import 'package:harmonymusic/services/spotify/spotify_source_track.dart';
import 'package:harmonymusic/services/spotify/track_matcher.dart';

SpotifySourceTrack source({
  String id = 'sp1',
  String title = 'Blinding Lights',
  List<String> artists = const ['The Weeknd'],
  String? album = 'After Hours',
  int durationMs = 200000,
  String? isrc,
  bool explicit = false,
}) =>
    SpotifySourceTrack(
      spotifyId: id,
      title: title,
      artists: artists,
      album: album,
      durationMs: durationMs,
      isrc: isrc,
      explicit: explicit,
    );

MediaItem candidate({
  String id = 'yt1',
  String title = 'Blinding Lights',
  String artist = 'The Weeknd',
  String? album = 'After Hours',
  Duration? duration = const Duration(milliseconds: 200000),
  String? isrc,
  bool? explicit,
}) =>
    MediaItem(
      id: id,
      title: title,
      artist: artist,
      duration: duration,
      extras: {
        if (album != null) 'album': {'name': album, 'id': 'al1'},
        if (isrc != null) 'isrc': isrc,
        if (explicit != null) 'explicit': explicit,
      },
    );

void main() {
  group('scoreTrack', () {
    test('exact ISRC dominates even with slightly different metadata', () {
      final s = source(isrc: 'USUM71703861');
      final c = candidate(title: 'Blinding Lights (Remastered)',
          isrc: 'usum71703861');
      final score = scoreTrack(s, c);
      expect(score, greaterThanOrEqualTo(MatchThresholds.high));
    });

    test('matching ISRC is required to claim exact ISRC match', () {
      final s = source(isrc: 'USUM71703861');
      final c = candidate(isrc: 'USUM71703862');
      final score = scoreTrack(s, c);
      expect(score, lessThan(MatchThresholds.high));
    });

    test('exact title + artist + duration without ISRC scores high', () {
      final s = source();
      final c = candidate();
      final score = scoreTrack(s, c);
      expect(score, greaterThanOrEqualTo(MatchThresholds.high));
      expect(score, lessThanOrEqualTo(1.0));
    });

    test('slight title variation still matches', () {
      final s = source(title: 'Blinding Lights');
      final c = candidate(title: 'Blinding Lights (Official Audio)');
      expect(scoreTrack(s, c), greaterThanOrEqualTo(MatchThresholds.high));

      final c2 = candidate(title: 'Blinding Lights (Remastered 2021)');
      expect(scoreTrack(s, c2), greaterThanOrEqualTo(MatchThresholds.high));
    });

    test('duration mismatch reduces the score', () {
      final s = source(durationMs: 200000);
      final c = candidate(duration: const Duration(milliseconds: 120000));
      final score = scoreTrack(s, c);
      expect(score, lessThan(MatchThresholds.high));
      expect(score, greaterThan(0.0));
    });

    test('remix is not accepted as the original', () {
      final s = source();
      final c = candidate(title: 'Blinding Lights (Remix)');
      final score = scoreTrack(s, c);
      expect(score, lessThan(MatchThresholds.high));
    });

    test('live version is not accepted as the studio version', () {
      final s = source();
      final c = candidate(title: 'Blinding Lights - Live');
      final score = scoreTrack(s, c);
      expect(score, lessThan(MatchThresholds.high));
    });

    test('same live marker on both sides keeps the match strong', () {
      final s = source(title: 'Blinding Lights - Live');
      final c = candidate(title: 'Blinding Lights - Live');
      expect(scoreTrack(s, c), greaterThanOrEqualTo(MatchThresholds.high));
    });

    test('explicit vs clean mismatch applies a penalty', () {
      final s = source(explicit: true);
      final c = candidate(explicit: false);
      final score = scoreTrack(s, c);
      expect(score, lessThan(1.0));
    });

    test('multiple artists are compared as a set', () {
      final s = source(artists: ['Kendrick Lamar', 'SZA']);
      final c = candidate(artist: 'SZA, Kendrick Lamar');
      expect(scoreTrack(s, c), greaterThanOrEqualTo(MatchThresholds.high));
    });

    test('missing ISRC does not unfairly penalize', () {
      final withIsrc = scoreTrack(
          source(isrc: 'USUM71703861'), candidate(isrc: 'USUM71703861'));
      final without =
          scoreTrack(source(), candidate());
      // Both should reach high confidence; missing ISRC must not block it.
      expect(withIsrc, greaterThanOrEqualTo(MatchThresholds.high));
      expect(without, greaterThanOrEqualTo(MatchThresholds.high));
    });

    test('wrong artist drops the score below high', () {
      final s = source(artists: ['The Weeknd']);
      final c = candidate(artist: 'Ed Sheeran');
      final score = scoreTrack(s, c);
      expect(score, lessThan(MatchThresholds.high));
    });

    test('completely unrelated track scores low', () {
      final s = source(title: 'Blinding Lights', artists: ['The Weeknd']);
      final c = candidate(
          title: 'Shape of You', artist: 'Ed Sheeran', album: 'Divide');
      expect(scoreTrack(s, c), lessThan(MatchThresholds.low));
    });
  });

  group('MatchConfidence.fromScore', () {
    test('classifies bands correctly', () {
      expect(MatchConfidence.fromScore(0.95), MatchConfidence.high);
      expect(MatchConfidence.fromScore(0.90), MatchConfidence.high);
      expect(MatchConfidence.fromScore(0.89), MatchConfidence.medium);
      expect(MatchConfidence.fromScore(0.75), MatchConfidence.medium);
      expect(MatchConfidence.fromScore(0.74), MatchConfidence.low);
      expect(MatchConfidence.fromScore(0.60), MatchConfidence.low);
      expect(MatchConfidence.fromScore(0.59), MatchConfidence.unmatched);
      expect(MatchConfidence.fromScore(0.0), MatchConfidence.unmatched);
    });
  });

  group('generateSearchQueries', () {
    test('starts with title + artist', () {
      final q = generateSearchQueries(source());
      expect(q.first, '"Blinding Lights" "The Weeknd"');
    });

    test('adds album strategy and reversed order', () {
      final q = generateSearchQueries(
          source(album: 'After Hours'));
      expect(q.length, 3);
      expect(q[1], '"Blinding Lights" "The Weeknd" "After Hours"');
      expect(q[2], '"The Weeknd" "Blinding Lights"');
    });

    test('omits album strategy when no album is known', () {
      final q = generateSearchQueries(source(album: null));
      expect(q.length, 2);
    });

    test('falls back to title only when no artists', () {
      final q = generateSearchQueries(source(artists: []));
      expect(q, ['"Blinding Lights"']);
    });
  });

  group('SpotifyApiClient.parsePlaylistId', () {
    test('parses urls, uris and bare ids', () {
      const id = '37i9dQZF1DXcBWIGoYBM5M';
      expect(SpotifyApiClient.parsePlaylistId(
              'https://open.spotify.com/playlist/$id?si=abc'),
          id);
      expect(SpotifyApiClient.parsePlaylistId(
              'https://open.spotify.com/playlist/$id'),
          id);
      expect(SpotifyApiClient.parsePlaylistId('spotify:playlist:$id'), id);
      expect(SpotifyApiClient.parsePlaylistId(id), id);
    });

    test('rejects invalid input', () {
      expect(SpotifyApiClient.parsePlaylistId(''), isNull);
      expect(SpotifyApiClient.parsePlaylistId('not a playlist'), isNull);
      expect(SpotifyApiClient.parsePlaylistId('https://example.com/x'), isNull);
    });
  });
}
