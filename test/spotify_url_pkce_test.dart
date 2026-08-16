import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/spotify/spotify_api_client.dart';
import 'package:sonara/services/spotify/spotify_oauth.dart';

void main() {
  const id = '37i9dQZF1DXcBWIGoYBM5M';

  group('parsePlaylistId', () {
    test('accepts a full playlist URL', () {
      expect(
        SpotifyApiClient.parsePlaylistId(
            'https://open.spotify.com/playlist/$id?si=abc123'),
        id,
      );
    });

    test('accepts a playlist URL without query', () {
      expect(
        SpotifyApiClient.parsePlaylistId('https://open.spotify.com/playlist/$id'),
        id,
      );
    });

    test('accepts an intl-locale playlist URL', () {
      expect(
        SpotifyApiClient.parsePlaylistId(
            'https://open.spotify.com/intl-de/playlist/$id'),
        id,
      );
    });

    test('accepts play.spotify.com', () {
      expect(
        SpotifyApiClient.parsePlaylistId('https://play.spotify.com/playlist/$id'),
        id,
      );
    });

    test('accepts a spotify:playlist URI', () {
      expect(SpotifyApiClient.parsePlaylistId('spotify:playlist:$id'), id);
    });

    test('accepts a bare playlist id', () {
      expect(SpotifyApiClient.parsePlaylistId(id), id);
    });

    test('rejects an album URL', () {
      expect(
        SpotifyApiClient.parsePlaylistId(
            'https://open.spotify.com/album/4m2880jivSbbyEGAKfITCa'),
        isNull,
      );
    });

    test('rejects a track URL', () {
      expect(
        SpotifyApiClient.parsePlaylistId(
            'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC'),
        isNull,
      );
    });

    test('rejects an artist URL', () {
      expect(
        SpotifyApiClient.parsePlaylistId(
            'https://open.spotify.com/artist/1Xyo4u8uXC1ZmMpatF05PJ'),
        isNull,
      );
    });

    test('rejects malformed ids', () {
      expect(SpotifyApiClient.parsePlaylistId('spotify:playlist:short'), isNull);
      expect(SpotifyApiClient.parsePlaylistId('not a url'), isNull);
      expect(SpotifyApiClient.parsePlaylistId(''), isNull);
    });

    test('invalidPlaylistReason explains non-playlist links', () {
      expect(
        SpotifyApiClient.invalidPlaylistReason(
            'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC'),
        contains('track'),
      );
      expect(SpotifyApiClient.invalidPlaylistReason('junk input'),
          contains('playlist'));
      expect(SpotifyApiClient.invalidPlaylistReason(''),
          isNotNull);
    });
  });

  group('PKCE primitives', () {
    test('generates a verifier/challenge pair', () {
      final pair = generatePkcePair(random: Random(42));
      expect(pair.verifier.length, inInclusiveRange(43, 128));
      expect(pair.challenge, isNotEmpty);
      // Challenge is the S256 hash of the verifier.
      final expected = base64UrlEncode(
              sha256.convert(utf8.encode(pair.verifier)).bytes)
          .replaceAll('=', '');
      expect(pair.challenge, expected);
    });

    test('is deterministic for a fixed random seed', () {
      final a = generatePkcePair(random: Random(7));
      final b = generatePkcePair(random: Random(7));
      expect(a.verifier, b.verifier);
      expect(a.challenge, b.challenge);
    });

    test('buildSpotifyAuthorizeUrl carries the PKCE parameters', () {
      final url = buildSpotifyAuthorizeUrl(
        clientId: 'client-123',
        redirectUri: 'http://localhost:53178/callback',
        codeChallenge: 'challenge-abc',
        state: 'state-xyz',
      );
      final params = url.queryParameters;
      expect(url.host, 'accounts.spotify.com');
      expect(url.path, '/authorize');
      expect(params['client_id'], 'client-123');
      expect(params['response_type'], 'code');
      expect(params['redirect_uri'], 'http://localhost:53178/callback');
      expect(params['code_challenge_method'], 'S256');
      expect(params['code_challenge'], 'challenge-abc');
      expect(params['state'], 'state-xyz');
      expect(params['scope'], contains('playlist-read-private'));
      expect(params['scope'], contains('playlist-read-collaborative'));
    });
  });
}
