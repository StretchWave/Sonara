import 'package:sonara_backend/src/api.dart';
import 'package:sonara_backend/src/models.dart';
import 'package:test/test.dart';

void main() {
  const id = '37i9dQZF1DXcBWIGoYBM5M';

  group('parseSpotifyPlaylistId', () {
    test('accepts playlist URLs with tracking parameters', () {
      expect(
        parseSpotifyPlaylistId(
            'https://open.spotify.com/playlist/$id?si=abc123&utm_source=copy'),
        id,
      );
    });

    test('accepts plain URLs, intl locales and play.spotify.com', () {
      expect(parseSpotifyPlaylistId('https://open.spotify.com/playlist/$id'), id);
      expect(
          parseSpotifyPlaylistId('https://open.spotify.com/intl-de/playlist/$id'),
          id);
      expect(parseSpotifyPlaylistId('https://play.spotify.com/playlist/$id'), id);
    });

    test('accepts spotify:playlist URIs and bare ids', () {
      expect(parseSpotifyPlaylistId('spotify:playlist:$id'), id);
      expect(parseSpotifyPlaylistId(id), id);
    });

    test('rejects track, album and artist URLs', () {
      expect(
          parseSpotifyPlaylistId(
              'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC'),
          isNull);
      expect(
          parseSpotifyPlaylistId(
              'https://open.spotify.com/album/4m2880jivSbbyEGAKfITCa'),
          isNull);
      expect(
          parseSpotifyPlaylistId(
              'https://open.spotify.com/artist/1Xyo4u8uXC1ZmMpatF05PJ'),
          isNull);
    });

    test('rejects malformed input', () {
      expect(parseSpotifyPlaylistId('not a url'), isNull);
      expect(parseSpotifyPlaylistId(''), isNull);
      expect(parseSpotifyPlaylistId('spotify:playlist:short'), isNull);
      expect(parseSpotifyPlaylistId('http://example.com/playlist/$id'), isNull,
          reason: 'non-Spotify hosts are rejected (SSRF guard)');
    });
  });

  group('validatePlaylistUrl', () {
    test('explains non-playlist Spotify links', () {
      final e = validatePlaylistUrl(
          'https://open.spotify.com/album/4m2880jivSbbyEGAKfITCa');
      expect(e.code, ResolveErrorCode.unsupportedUrl);
      expect(e.message, contains('album'));
    });

    test('rejects arbitrary URLs as unsupported', () {
      expect(validatePlaylistUrl('https://example.com/foo').code,
          ResolveErrorCode.unsupportedUrl);
    });

    test('rejects garbage as invalid', () {
      expect(validatePlaylistUrl('garbage input').code,
          ResolveErrorCode.invalidUrl);
      expect(validatePlaylistUrl('').code, ResolveErrorCode.invalidUrl);
    });
  });
}
