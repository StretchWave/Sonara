import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/metadata/playlist_metadata_provider.dart';
import 'package:sonara/services/metadata/spotify_embed_provider.dart';

import 'helpers/fake_dio_adapter.dart';

const _sampleEmbedHtml = '''
<!DOCTYPE html>
<html>
<head><title>Spotify Embed</title></head>
<body>
<script id="__NEXT_DATA__" type="application/json">
{
  "props": {
    "pageProps": {
      "state": {
        "data": {
          "entity": {
            "type": "playlist",
            "name": "Sonara import",
            "title": "Sonara import",
            "subtitle": "Test User",
            "visualIdentity": {
              "image": [
                {
                  "url": "https://i.scdn.co/image/small",
                  "maxHeight": 64,
                  "maxWidth": 64
                },
                {
                  "url": "https://i.scdn.co/image/large",
                  "maxHeight": 640,
                  "maxWidth": 640
                }
              ]
            },
            "trackList": [
              {
                "uri": "spotify:track:6ZAuQOgLrNQb9s7BXheuTy",
                "title": "Sue me",
                "subtitle": "Audrey Hobert",
                "duration": 170320,
                "isExplicit": true
              },
              {
                "uri": "spotify:track:3xwMjQriBVW0OGEvNKo9c0",
                "title": "Been By Now",
                "subtitle": "Morgan Wallen, Guest Artist",
                "duration": 213805,
                "isExplicit": false
              }
            ]
          }
        }
      }
    }
  }
}
</script>
</body>
</html>
''';

void main() {
  group('SpotifyEmbedProvider', () {
    test('canHandle accepts valid playlist and album links', () {
      final provider = SpotifyEmbedProvider();
      expect(
        provider.canHandle(Uri.parse('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M')),
        isTrue,
      );
      expect(
        provider.canHandle(Uri.parse('https://open.spotify.com/album/4m2880jivSbbyEGAKfITCa')),
        isTrue,
      );
      expect(
        provider.canHandle(Uri.parse('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M')),
        isTrue,
      );
      expect(
        provider.canHandle(Uri.parse('https://example.com/not-spotify')),
        isFalse,
      );
    });

    test('parses tracks, metadata, and artwork from embed HTML', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (options) {
        expect(options.path, '/embed/playlist/37i9dQZF1DXcBWIGoYBM5M');
        return ResponseBody.fromString(
          _sampleEmbedHtml,
          200,
          headers: {
            'content-type': ['text/html; charset=utf-8'],
          },
        );
      };

      final provider = SpotifyEmbedProvider(
        dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      );

      final result = await provider.fetchPlaylist(
        Uri.parse('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
      );

      expect(result.status, PlaylistMetadataStatus.success);
      expect(result.name, 'Sonara import');
      expect(result.artworkUrl, 'https://i.scdn.co/image/large');
      expect(result.tracks, hasLength(2));

      final first = result.tracks[0];
      expect(first.spotifyId, '6ZAuQOgLrNQb9s7BXheuTy');
      expect(first.title, 'Sue me');
      expect(first.artists, ['Audrey Hobert']);
      expect(first.durationMs, 170320);
      expect(first.explicit, isTrue);

      final second = result.tracks[1];
      expect(second.spotifyId, '3xwMjQriBVW0OGEvNKo9c0');
      expect(second.title, 'Been By Now');
      expect(second.artists, ['Morgan Wallen', 'Guest Artist']);
      expect(second.durationMs, 213805);
      expect(second.explicit, isFalse);
    });

    test('404 maps to notFound', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => ResponseBody.fromString(
            'Not Found',
            404,
            headers: {'content-type': ['text/plain']},
          );

      final provider = SpotifyEmbedProvider(
        dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      );

      final result = await provider.fetchPlaylist(
        Uri.parse('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
      );

      expect(result.status, PlaylistMetadataStatus.notFound);
    });

    test('429 maps to rateLimited', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => ResponseBody.fromString(
            'Rate Limited',
            429,
            headers: {'content-type': ['text/plain']},
          );

      final provider = SpotifyEmbedProvider(
        dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      );

      final result = await provider.fetchPlaylist(
        Uri.parse('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
      );

      expect(result.status, PlaylistMetadataStatus.rateLimited);
    });

    test('timeout maps to networkError', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => throw DioException.connectionTimeout(
            timeout: const Duration(seconds: 10),
            requestOptions: RequestOptions(path: '/embed/playlist/x'),
          );

      final provider = SpotifyEmbedProvider(
        dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      );

      final result = await provider.fetchPlaylist(
        Uri.parse('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
      );

      expect(result.status, PlaylistMetadataStatus.networkError);
    });
  });
}
