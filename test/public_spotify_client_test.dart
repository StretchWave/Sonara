import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/metadata/playlist_metadata_provider.dart';
import 'package:sonara/services/metadata/spotify_embed_provider.dart';
import 'package:sonara/services/spotify/public_spotify_client.dart';

import 'helpers/fake_dio_adapter.dart';

const _mockEmbedHtmlWithToken = '''
<!DOCTYPE html>
<html>
<head><title>Spotify Embed</title></head>
<body>
<script>
window.__INITIAL_STATE__ = {
  "accessToken": "mock_token_12345",
  "accessTokenExpirationTimestampMs": 9999999999999
};
</script>
</body>
</html>
''';

void main() {
  group('PublicSpotifyClient', () {
    test('bootstraps token and fetches paginated tracks with decoration',
        () async {
      final embedAdapter = FakeDioAdapter();
      embedAdapter.handler = (options) {
        expect(options.path, '/embed/playlist/mock_playlist_123');
        return ResponseBody.fromString(
          _mockEmbedHtmlWithToken,
          200,
          headers: {
            'content-type': ['text/html'],
          },
        );
      };

      final gqlAdapter = FakeDioAdapter();
      gqlAdapter.handler = (options) {
        expect(options.path, '/pathfinder/v2/query');
        final body = options.data as Map;
        final op = body['operationName'];

        if (op == 'fetchPlaylistMetadata') {
          final offset = body['variables']['offset'] as int;
          if (offset == 0) {
            // Page 1: returns items 0..99 and indicates totalCount is 150
            final items = List.generate(
              100,
              (i) => {
                'itemV2': {
                  'data': {
                    'uri': 'spotify:track:track_$i',
                    'name': 'Track $i',
                    'trackDuration': {'totalMilliseconds': 200000 + i},
                  }
                }
              },
            );
            return ResponseBody.fromString(
              jsonEncode({
                'data': {
                  'playlistV2': {
                    'name': 'Giant Playlist',
                    'description': 'Over 100 tracks',
                    'images': {
                      'items': [
                        {
                          'sources': [{'url': 'https://i.scdn.co/image/giant'}]
                        }
                      ]
                    },
                    'content': {
                      'totalCount': 150,
                      'items': items,
                      'pagingInfo': {'nextOffset': 100},
                    }
                  }
                }
              }),
              200,
              headers: {
                'content-type': ['application/json'],
              },
            );
          } else {
            // Page 2: returns items 100..149
            final items = List.generate(
              50,
              (i) => {
                'itemV2': {
                  'data': {
                    'uri': 'spotify:track:track_${100 + i}',
                    'name': 'Track ${100 + i}',
                    'trackDuration': {'totalMilliseconds': 210000 + i},
                  }
                }
              },
            );
            return ResponseBody.fromString(
              jsonEncode({
                'data': {
                  'playlistV2': {
                    'name': 'Giant Playlist',
                    'content': {
                      'totalCount': 150,
                      'items': items,
                      'pagingInfo': {'nextOffset': null},
                    }
                  }
                }
              }),
              200,
              headers: {
                'content-type': ['application/json'],
              },
            );
          }
        }

        if (op == 'decorateContextTracks') {
          final uris = (body['variables']['uris'] as List).cast<String>();
          final tracks = uris.map((uri) {
            return {
              'uri': uri,
              'name': 'Decorated ${uri.split(':').last}',
              'artists': {
                'items': [
                  {
                    'profile': {'name': 'Artist for $uri'}
                  }
                ]
              },
              'albumOfTrack': {
                'name': 'Album for $uri',
                'coverArt': {
                  'sources': [{'url': 'https://i.scdn.co/art/$uri'}]
                }
              },
              'duration': {'totalMilliseconds': 180000},
              'contentRating': {'label': 'NONE'},
            };
          }).toList();

          return ResponseBody.fromString(
            jsonEncode({
              'data': {'tracks': tracks}
            }),
            200,
            headers: {
              'content-type': ['application/json'],
            },
          );
        }

        throw UnimplementedError('Unexpected operation: $op');
      };

      final client = PublicSpotifyClient(
        dio: Dio(BaseOptions())..httpClientAdapter = gqlAdapter,
        embedDio: Dio(BaseOptions())..httpClientAdapter = embedAdapter,
      );

      final result = await client.fetchPlaylist('mock_playlist_123');
      expect(result.name, 'Giant Playlist');
      expect(result.totalCount, 150);
      expect(result.tracks, hasLength(150));

      // Verify the tracks were paged past 100
      expect(result.tracks[0].spotifyId, 'track_0');
      expect(result.tracks[0].title, 'Decorated track_0');
      expect(result.tracks[0].artists, ['Artist for spotify:track:track_0']);
      expect(result.tracks[99].spotifyId, 'track_99');
      expect(result.tracks[100].spotifyId, 'track_100');
      expect(result.tracks[149].spotifyId, 'track_149');
    });

    test('SpotifyEmbedProvider seamlessly uses PublicSpotifyClient for full playlists',
        () async {
      final embedAdapter = FakeDioAdapter();
      embedAdapter.handler = (options) {
        return ResponseBody.fromString(
          _mockEmbedHtmlWithToken,
          200,
          headers: {'content-type': ['text/html']},
        );
      };

      final gqlAdapter = FakeDioAdapter();
      gqlAdapter.handler = (options) {
        final body = options.data as Map;
        final op = body['operationName'];
        if (op == 'fetchPlaylistMetadata') {
          return ResponseBody.fromString(
            jsonEncode({
              'data': {
                'playlistV2': {
                  'name': '200 Songs Playlist',
                  'content': {
                    'totalCount': 120,
                    'items': List.generate(
                      120,
                      (i) => {
                        'itemV2': {
                          'data': {
                            'uri': 'spotify:track:t_$i',
                            'name': 'Track $i',
                            'trackDuration': {'totalMilliseconds': 190000},
                          }
                        }
                      },
                    ),
                    'pagingInfo': {'nextOffset': null},
                  }
                }
              }
            }),
            200,
            headers: {'content-type': ['application/json']},
          );
        }
        if (op == 'decorateContextTracks') {
          final uris = (body['variables']['uris'] as List).cast<String>();
          return ResponseBody.fromString(
            jsonEncode({
              'data': {
                'tracks': uris
                    .map((u) => {
                          'uri': u,
                          'name': 'Hydrated $u',
                          'artists': {
                            'items': [
                              {
                                'profile': {'name': 'Test Artist'}
                              }
                            ]
                          },
                          'duration': {'totalMilliseconds': 195000},
                        })
                    .toList(),
              }
            }),
            200,
            headers: {'content-type': ['application/json']},
          );
        }
        throw UnimplementedError();
      };

      final publicClient = PublicSpotifyClient(
        dio: Dio(BaseOptions())..httpClientAdapter = gqlAdapter,
        embedDio: Dio(BaseOptions())..httpClientAdapter = embedAdapter,
      );

      final provider = SpotifyEmbedProvider(
        dio: Dio(BaseOptions())..httpClientAdapter = embedAdapter,
        publicClient: publicClient,
      );

      final res = await provider.fetchPlaylist(
        Uri.parse('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M'),
      );

      expect(res.status, PlaylistMetadataStatus.success);
      expect(res.name, '200 Songs Playlist');
      // Full 120 tracks loaded (not capped at 100!)
      expect(res.tracks, hasLength(120));
      expect(res.tracks.last.spotifyId, 't_119');
    });
  });
}
