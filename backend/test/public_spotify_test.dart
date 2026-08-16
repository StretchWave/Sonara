import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sonara_backend/sonara_backend.dart';
import 'package:test/test.dart';

/// Scripts the Spotify anonymous surface: the embed page (token bootstrap)
/// and the partner GraphQL endpoint (playlist + decorate queries).
class FakeSpotifyApi {
  final int embedStatus;
  final String token;
  final List<Map<String, dynamic>> playlistItems;
  final Map<String, Map<String, dynamic>> trackByUri;
  final int graphStatus;

  FakeSpotifyApi({
    this.embedStatus = 200,
    this.token = 'anon-token-123',
    this.playlistItems = const [],
    this.trackByUri = const {},
    this.graphStatus = 200,
  });

  int embedCalls = 0;
  int graphCalls = 0;

  Dio buildDio() => Dio(BaseOptions(baseUrl: 'https://api-partner.spotify.com'))
    ..httpClientAdapter = _Adapter(this);
}

class _Adapter implements HttpClientAdapter {
  final FakeSpotifyApi api;
  _Adapter(this.api);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    ResponseBody json(Map body, int status) => ResponseBody.fromString(
        jsonEncode(body), status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });

    // Embed page bootstrap.
    if (options.method == 'GET' && options.path.startsWith('https://open.spotify.com/embed/')) {
      api.embedCalls++;
      if (api.embedStatus != 200) return json({'error': 'nope'}, api.embedStatus);
      final html =
          '<html><script>window.__data={"settings":{"session":{"accessToken":"${api.token}",'
          '"accessTokenExpirationTimestampMs":${DateTime.now().millisecondsSinceEpoch + 3600000}}}}</script></html>';
      return ResponseBody.fromString(html, 200, headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType]
      });
    }

    // Partner GraphQL.
    if (options.method == 'POST' && options.path == '/pathfinder/v2/query') {
      api.graphCalls++;
      if (api.graphStatus != 200) return json({'error': 'boom'}, api.graphStatus);
      final body = jsonDecode(utf8.decode(await requestStream!.toList().then((l) => l.fold<List<int>>([], (a, b) => a..addAll(b))))) as Map;
      final operation = body['operationName'] as String;
      if (operation == 'fetchPlaylistMetadata') {
        final items = api.playlistItems
            .map((item) => {
                  'itemV2': {
                    'data': {
                      '__typename': 'Track',
                      'uri': item['uri'],
                      'trackDuration': {
                        'totalMilliseconds': item['durationMs'] ?? 0,
                      },
                    }
                  }
                })
            .toList();
        return json({
          'data': {
            'playlistV2': {
              '__typename': 'Playlist',
              'name': 'Test Playlist',
              'description': 'desc',
              'images': {
                'items': [
                  {
                    'sources': [
                      {'url': 'https://i.scdn.co/image/cover', 'width': 640}
                    ]
                  }
                ]
              },
              'ownerV2': {
                'data': {'name': 'Owner'}
              },
              'content': {
                'totalCount': api.playlistItems.length,
                'items': items,
                'pagingInfo': {'offset': 0},
              },
            }
          }
        }, 200);
      }
      if (operation == 'decorateContextTracks') {
        final uris = (body['variables'] as Map)['uris'] as List;
        final tracks = uris
            .whereType<String>()
            .map((uri) => api.trackByUri[uri] ?? {
                  'uri': uri,
                  'name': 'Unknown',
                  'artists': {
                    'items': [
                      {'profile': {'name': '?'}}
                    ]
                  },
                  'albumOfTrack': {
                    'name': '?',
                    'coverArt': {'sources': []}
                  },
                  'duration': {'totalMilliseconds': 0},
                })
            .toList();
        return json({'data': {'tracks': tracks}}, 200);
      }
      return json({'data': <String, dynamic>{}}, 200);
    }

    return json({'error': 'unexpected ${options.path}'}, 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('PublicSpotifyClient', () {
    test('bootstraps an anonymous token from the embed page', () async {
      final api = FakeSpotifyApi();
      final client = PublicSpotifyClient(dio: api.buildDio());
      final token = await client.ensureToken('p1');
      expect(token.token, 'anon-token-123');
      expect(token.isExpired, isFalse);
      expect(api.embedCalls, 1);
    });

    test('reuses the cached token without re-fetching the embed page',
        () async {
      final api = FakeSpotifyApi();
      final client = PublicSpotifyClient(dio: api.buildDio());
      await client.ensureToken('p1');
      await client.ensureToken('p1');
      expect(api.embedCalls, 1);
    });

    test('enumerates the playlist and hydrates track metadata', () async {
      final api = FakeSpotifyApi(
        playlistItems: [
          {
            'uri': 'spotify:track:aaaaaaaaaaaaaaaaaaaaaa',
            'durationMs': 120000,
          },
          {
            'uri': 'spotify:track:bbbbbbbbbbbbbbbbbbbbbb',
            'durationMs': 90000,
          },
        ],
        trackByUri: {
          'spotify:track:aaaaaaaaaaaaaaaaaaaaaa': {
            'uri': 'spotify:track:aaaaaaaaaaaaaaaaaaaaaa',
            'name': 'Song A',
            'artists': {
              'items': [
                {'profile': {'name': 'Artist A'}}
              ]
            },
            'albumOfTrack': {
              'name': 'Album A',
              'coverArt': {
                'sources': [
                  {'url': 'https://i.scdn.co/image/a', 'width': 640}
                ]
              }
            },
            'duration': {'totalMilliseconds': 120000},
            'contentRating': {'label': 'EXPLICIT'},
          },
          'spotify:track:bbbbbbbbbbbbbbbbbbbbbb': {
            'uri': 'spotify:track:bbbbbbbbbbbbbbbbbbbbbb',
            'name': 'Song B',
            'artists': {
              'items': [
                {'profile': {'name': 'Artist B'}}
              ]
            },
            'albumOfTrack': {
              'name': 'Album B',
              'coverArt': {'sources': []}
            },
            'duration': {'totalMilliseconds': 90000},
          },
        },
      );
      final client = PublicSpotifyClient(dio: api.buildDio());

      final page = await client.fetchPlaylist('p1');
      expect(page.name, 'Test Playlist');
      expect(page.artworkUrl, 'https://i.scdn.co/image/cover');
      expect(page.totalCount, 2);
      expect(page.rawItems, hasLength(2));

      final token = await client.ensureToken('p1');
      final metadata =
          await client.fetchTrackMetadata(token, page.rawItems.map((i) => ((i['itemV2'] as Map)['data'] as Map)['uri'] as String).toList());
      expect(metadata, hasLength(2));
      expect(metadata.first['name'], 'Song A');
      expect(metadata.first['contentRating'], {'label': 'EXPLICIT'});
    });

    test('reports structured errors for a dead anonymous channel', () async {
      final api = FakeSpotifyApi(embedStatus: 403);
      final client = PublicSpotifyClient(dio: api.buildDio());
      await expectLater(
          client.ensureToken('p1'),
          throwsA(isA<ResolveError>().having(
              (e) => e.code, 'code', ResolveErrorCode.providerUnavailable)));
    });
  });

  group('PublicSpotifyProvider', () {
    PlaylistResolveInput input() => const PlaylistResolveInput(
        playlistId: 'p1', url: 'https://open.spotify.com/playlist/p1');

    test('resolves a public playlist to normalized tracks', () async {
      final api = FakeSpotifyApi(
        playlistItems: [
          {
            'uri': 'spotify:track:aaaaaaaaaaaaaaaaaaaaaa',
            'durationMs': 120000,
          },
        ],
        trackByUri: {
          'spotify:track:aaaaaaaaaaaaaaaaaaaaaa': {
            'uri': 'spotify:track:aaaaaaaaaaaaaaaaaaaaaa',
            'name': 'Song A',
            'artists': {
              'items': [
                {'profile': {'name': 'Artist A'}}
              ]
            },
            'albumOfTrack': {
              'name': 'Album A',
              'coverArt': {
                'sources': [
                  {'url': 'https://i.scdn.co/image/a', 'width': 640}
                ]
              }
            },
            'duration': {'totalMilliseconds': 120000},
          },
        },
      );
      final provider = PublicSpotifyProvider(PublicSpotifyClient(dio: api.buildDio()));

      final result = await provider.resolve(input());
      expect(result.source, 'spotify');
      expect(result.method, 'anonymous_graphql');
      expect(result.playlist.name, 'Test Playlist');
      expect(result.tracks, hasLength(1));
      final track = result.tracks.first;
      expect(track.title, 'Song A');
      expect(track.artists, ['Artist A']);
      expect(track.album, 'Album A');
      expect(track.durationMs, 120000);
      expect(track.sourceTrackId, 'aaaaaaaaaaaaaaaaaaaaaa');
      expect(track.artworkUrl, 'https://i.scdn.co/image/a');
    });

    test('throws playlistEmpty when the playlist has no tracks', () async {
      final api = FakeSpotifyApi(playlistItems: const []);
      final provider = PublicSpotifyProvider(PublicSpotifyClient(dio: api.buildDio()));
      await expectLater(provider.resolve(input()),
          throwsA(isA<ResolveError>()
              .having((e) => e.code, 'code', ResolveErrorCode.playlistNotFound)));
    });
  });

  group('resolver chain', () {
    test('public provider resolves without any credentials', () async {
      final cache = ResolutionCache(ttl: const Duration(minutes: 60));
      final api = FakeSpotifyApi(
        playlistItems: [
          {
            'uri': 'spotify:track:aaaaaaaaaaaaaaaaaaaaaa',
            'durationMs': 120000,
          },
        ],
        trackByUri: {
          'spotify:track:aaaaaaaaaaaaaaaaaaaaaa': {
            'uri': 'spotify:track:aaaaaaaaaaaaaaaaaaaaaa',
            'name': 'Song A',
            'artists': {
              'items': [
                {'profile': {'name': 'Artist A'}}
              ]
            },
            'albumOfTrack': {'name': 'Album A', 'coverArt': {'sources': []}},
            'duration': {'totalMilliseconds': 120000},
          },
        },
      );
      final resolver = PlaylistResolver(
        providers: [
          CachedPlaylistProvider(cache),
          PublicSpotifyProvider(PublicSpotifyClient(dio: api.buildDio())),
        ],
        cache: cache,
      );
      const input = PlaylistResolveInput(
          playlistId: 'p1', url: 'https://open.spotify.com/playlist/p1');
      final first = await resolver.resolve(input);
      expect(first.source, 'spotify');
      expect(first.tracks, hasLength(1));

      // Second request is served from cache — no new GraphQL calls.
      final graphCalls = api.graphCalls;
      final second = await resolver.resolve(input);
      expect(second.cached, isTrue);
      expect(api.graphCalls, graphCalls);
    });
  });
}
