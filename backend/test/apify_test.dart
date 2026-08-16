import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:synora_backend/synora_backend.dart';
import 'package:test/test.dart';

/// In-memory fake of the Apify API v2 HTTP surface used by [ApifyClient].
///
/// Scripts the actor-run lifecycle (start → poll → dataset) and can inject
/// failures per stage so every error path is exercised without network.
class FakeApifyApi {
  final List<Map<String, dynamic>> datasetItems;
  final int startStatus;
  final int pollStatus;
  final String runStatus;
  final String? datasetId;
  final int pollCountBefore;

  FakeApifyApi({
    this.datasetItems = const [],
    this.startStatus = 200,
    this.pollStatus = 200,
    this.runStatus = 'SUCCEEDED',
    this.datasetId = 'ds-fake',
    this.pollCountBefore = 1,
  });

  /// Count of polls issued before the run reaches a terminal state.
  int _polls = 0;

  Dio buildDio() {
    final adapter = _FakeAdapter(this);
    return Dio(BaseOptions(baseUrl: 'https://api.apify.com/v2'))
      ..httpClientAdapter = adapter;
  }
}

class _FakeAdapter implements HttpClientAdapter {
  final FakeApifyApi api;

  _FakeAdapter(this.api);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = options.path;

    ResponseBody json(Map body, int status) => ResponseBody.fromString(
        jsonEncode(body), status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });

    // POST /acts/{actorId}/runs → run id
    if (options.method == 'POST' && path.startsWith('/acts/')) {
      if (api.startStatus != 200) {
        return json({'error': {'message': 'boom'}}, api.startStatus);
      }
      return json({
        'data': {'id': 'run-1', 'status': 'RUNNING'}
      }, 200);
    }

    // GET /actor-runs/{runId} → status + defaultDatasetId
    if (options.method == 'GET' && path.startsWith('/actor-runs/')) {
      if (api.pollStatus != 200) {
        return json({'error': {'message': 'boom'}}, api.pollStatus);
      }
      api._polls++;
      final status = api._polls < api.pollCountBefore
          ? 'RUNNING'
          : api.runStatus;
      return json({
        'data': {'id': 'run-1', 'status': status, 'defaultDatasetId': api.datasetId}
      }, 200);
    }

    // GET /datasets/{id}/items → items
    if (options.method == 'GET' && path.startsWith('/datasets/')) {
      return ResponseBody.fromString(jsonEncode(api.datasetItems), 200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          });
    }

    return json({'error': {'message': 'unexpected route $path'}}, 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('ApifyClient.runActor', () {
    const settings = ApifySettings(
      token: 'tok',
      actorId: 'axlymxp/spotify-playlist-track-extractor',
      runTimeout: Duration(seconds: 30),
      pollInterval: Duration(milliseconds: 1),
    );

    test('runs actor to completion and returns dataset items', () async {
      final api = FakeApifyApi(datasetItems: [
        {'trackName': 'Song A', 'artistNames': ['Artist A'], 'trackUrl': 'https://open.spotify.com/track/aaaaaaaaaaaaaaaaaaaaaa'},
      ]);
      final client = ApifyClient(dio: api.buildDio(), settings: settings);
      final items = await client.runActor(
          settings.actorId!, settings.buildInput('https://open.spotify.com/playlist/pppppppppppppppppppppp'));
      expect(items, hasLength(1));
      expect(items.first['trackName'], 'Song A');
    });

    test('builds the default actor input shape', () {
      final input = settings.buildInput('https://open.spotify.com/playlist/pppppppppppppppppppppp');
      expect(input['playlistUrls'], ['https://open.spotify.com/playlist/pppppppppppppppppppppp']);
      expect(input['includeISRC'], isTrue);
    });

    test('substitutes {{url}} in an input override template', () {
      const overridden = ApifySettings(
        token: 'tok',
        actorId: 'vendor/actor',
        inputOverride: {'startUrls': [{'url': '{{url}}'}]},
      );
      final input = overridden.buildInput('https://open.spotify.com/playlist/pppppppppppppppppppppp');
      expect(input['startUrls'], [
        {'url': 'https://open.spotify.com/playlist/pppppppppppppppppppppp'}
      ]);
    });

    test('maps 401 to apifyAuth', () async {
      final api = FakeApifyApi(startStatus: 401);
      final client = ApifyClient(dio: api.buildDio(), settings: settings);
      await expectLater(
          client.runActor(settings.actorId!, const {}),
          throwsA(isA<ResolveError>()
              .having((e) => e.code, 'code', ResolveErrorCode.apifyAuth)));
    });

    test('maps 429 to providerRateLimited', () async {
      final api = FakeApifyApi(startStatus: 429);
      final client = ApifyClient(dio: api.buildDio(), settings: settings);
      await expectLater(
          client.runActor(settings.actorId!, const {}),
          throwsA(isA<ResolveError>().having(
              (e) => e.code, 'code', ResolveErrorCode.providerRateLimited)));
    });

    test('maps a failed run to apifyActorError', () async {
      final api = FakeApifyApi(runStatus: 'FAILED');
      final client = ApifyClient(dio: api.buildDio(), settings: settings);
      await expectLater(
          client.runActor(settings.actorId!, const {}),
          throwsA(isA<ResolveError>()
              .having((e) => e.code, 'code', ResolveErrorCode.apifyActorError)));
    });

    test('times out when the run never reaches a terminal state', () async {
      final api = FakeApifyApi(runStatus: 'RUNNING', pollCountBefore: 9999);
      final client = ApifyClient(
        dio: api.buildDio(),
        settings: const ApifySettings(
          token: 'tok',
          actorId: 'vendor/actor',
          runTimeout: Duration(milliseconds: 50),
          pollInterval: Duration(milliseconds: 1),
        ),
      );
      await expectLater(
          client.runActor(settings.actorId!, const {}),
          throwsA(isA<ResolveError>()
              .having((e) => e.code, 'code', ResolveErrorCode.apifyTimeout)));
    });

    test('throws ApifyNotConfigured without a token', () async {
      final client = ApifyClient(
        dio: Dio(),
        settings: const ApifySettings(token: null, actorId: null),
      );
      await expectLater(client.runActor('a/b', const {}),
          throwsA(isA<ApifyNotConfigured>()));
    });
  });

  group('normalizeApifyTrack', () {
    test('maps the canonical axlymxp field names', () {
      final t = normalizeApifyTrack({
        'trackName': 'Blinding Lights',
        'artistNames': ['The Weeknd'],
        'albumName': 'After Hours',
        'durationMs': 200040,
        'isrc': 'USUG12000335',
        'trackUrl': 'https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT',
        'imageUrl': 'https://i.scdn.co/artwork.jpg',
        'explicit': false,
        'position': 1,
      }, 0);
      expect(t.title, 'Blinding Lights');
      expect(t.artists, ['The Weeknd']);
      expect(t.album, 'After Hours');
      expect(t.durationMs, 200040);
      expect(t.isrc, 'USUG12000335');
      expect(t.sourceTrackId, '4cOdK2wGLETKBW3PvgPWqT');
      expect(t.artworkUrl, 'https://i.scdn.co/artwork.jpg');
      expect(t.position, 0);
    });

    test('maps nested spotify-object field names', () {
      final t = normalizeApifyTrack({
        'track': {'name': 'Song', 'artists': [{'name': 'A'}], 'album': {'name': 'Al', 'release_date': '2020-01-01'}},
        'external_ids': {'isrc': 'US1234567890'},
        'id': 'bbbbbbbbbbbbbbbbbbbbbb',
      }, 0);
      expect(t.title, 'Song');
      expect(t.artists, ['A']);
      expect(t.album, 'Al');
      expect(t.isrc, 'US1234567890');
      expect(t.sourceTrackId, 'bbbbbbbbbbbbbbbbbbbbbb');
    });

    test('parses a spotify:track: uri and duration seconds', () {
      final t = normalizeApifyTrack({
        'title': 'X',
        'artist': 'Y',
        'trackUri': 'spotify:track:cccccccccccccccccccccc',
        'length': 213,
      }, 0);
      expect(t.sourceTrackId, 'cccccccccccccccccccccc');
      expect(t.durationMs, 213000);
    });

    test('parses m:ss duration text', () {
      final t = normalizeApifyTrack({'title': 'X', 'durationText': '3:33'}, 0);
      expect(t.durationMs, 213000);
    });

    test('caps oversized fields and drops invalid ids', () {
      final t = normalizeApifyTrack({
        'title': 'x' * 600,
        'artistNames': ['A'],
        'trackId': 'not-an-id',
      }, 0);
      expect(t.title.length, 500);
      expect(t.sourceTrackId, '');
    });

    test('returns an empty placeholder for a row with no identity', () {
      final t = normalizeApifyTrack({'position': 1}, 0);
      expect(t.title, '');
      expect(t.sourceTrackId, '');
    });
  });

  group('ApifyPlaylistProvider', () {
    const input = PlaylistResolveInput(
      playlistId: 'pppppppppppppppppppppp',
      url: 'https://open.spotify.com/playlist/pppppppppppppppppppppp',
    );

    ApifyPlaylistProvider providerWith(List<Map<String, dynamic>> items) {
      const settings = ApifySettings(
        token: 'tok',
        actorId: 'vendor/actor',
        runTimeout: Duration(seconds: 10),
        pollInterval: Duration(milliseconds: 1),
      );
      final api = FakeApifyApi(datasetItems: items);
      return ApifyPlaylistProvider(ApifyClient(dio: api.buildDio(), settings: settings));
    }

    test('cannot resolve without credentials', () {
      final p = ApifyPlaylistProvider(ApifyClient(
          dio: Dio(), settings: const ApifySettings()));
      expect(p.canResolve(input), isFalse);
    });

    test('normalizes items into a resolution with deduplication', () async {
      final p = providerWith([
        {'trackName': 'A', 'artistNames': ['X'], 'isrc': 'US1111111111', 'trackUrl': 'https://open.spotify.com/track/aaaaaaaaaaaaaaaaaaaaaa', 'position': 1},
        {'trackName': 'B', 'artistNames': ['Y'], 'trackUrl': 'https://open.spotify.com/track/bbbbbbbbbbbbbbbbbbbbbb', 'position': 2},
        // duplicate of A by ISRC
        {'trackName': 'A (Remastered)', 'artistNames': ['X'], 'isrc': 'US1111111111', 'trackUrl': 'https://open.spotify.com/track/cccccccccccccccccccccc', 'position': 3},
      ]);
      final result = await p.resolve(input);
      expect(result.source, 'apify');
      expect(result.tracks, hasLength(2));
      expect(result.resolved, 2);
      expect(result.unavailable, 0);
      expect(result.tracks.map((t) => t.title), ['A', 'B']);
    });

    test('reports unavailable placeholder rows as partial', () async {
      final p = providerWith([
        {'trackName': 'A', 'artistNames': ['X'], 'trackUrl': 'https://open.spotify.com/track/aaaaaaaaaaaaaaaaaaaaaa', 'position': 1},
        {'position': 2}, // no identity
      ]);
      final result = await p.resolve(input);
      expect(result.resolved, 1);
      expect(result.unavailable, 1);
      expect(result.warnings.map((w) => w.code), ['PARTIAL_PLAYLIST']);
    });

    test('throws playlistEmpty when there are no usable tracks', () async {
      final p = providerWith([
        {'position': 1},
        {'position': 2},
      ]);
      await expectLater(p.resolve(input),
          throwsA(isA<ResolveError>()
              .having((e) => e.code, 'code', ResolveErrorCode.playlistEmpty)));
    });

    test('throws playlistEmpty when the dataset is empty', () async {
      final p = providerWith(const []);
      await expectLater(p.resolve(input),
          throwsA(isA<ResolveError>()
              .having((e) => e.code, 'code', ResolveErrorCode.playlistEmpty)));
    });

    test('propagates apify errors', () async {
      const settings = ApifySettings(
        token: 'tok',
        actorId: 'vendor/actor',
        runTimeout: Duration(seconds: 10),
        pollInterval: Duration(milliseconds: 1),
      );
      final api = FakeApifyApi(runStatus: 'FAILED');
      final p = ApifyPlaylistProvider(
          ApifyClient(dio: api.buildDio(), settings: settings));
      await expectLater(p.resolve(input),
          throwsA(isA<ResolveError>()
              .having((e) => e.code, 'code', ResolveErrorCode.apifyActorError)));
    });
  });

  group('resolver chain with apify', () {
    test('apify result is cached and reused on the next request', () async {
      final cache = ResolutionCache(ttl: const Duration(minutes: 60));
      const settings = ApifySettings(
        token: 'tok',
        actorId: 'vendor/actor',
        runTimeout: Duration(seconds: 10),
        pollInterval: Duration(milliseconds: 1),
      );
      final api = FakeApifyApi(datasetItems: [
        {'trackName': 'A', 'artistNames': ['X'], 'trackUrl': 'https://open.spotify.com/track/aaaaaaaaaaaaaaaaaaaaaa'},
      ]);
      final resolver = PlaylistResolver(
        providers: [
          CachedPlaylistProvider(cache),
          ApifyPlaylistProvider(ApifyClient(dio: api.buildDio(), settings: settings)),
        ],
        cache: cache,
      );
      const input = PlaylistResolveInput(
        playlistId: 'pppppppppppppppppppppp',
        url: 'https://open.spotify.com/playlist/pppppppppppppppppppppp',
      );
      final first = await resolver.resolve(input);
      expect(first.cached, isFalse);
      expect(first.source, 'apify');

      final pollsBefore = api._polls;
      final second = await resolver.resolve(input);
      expect(second.cached, isTrue);
      expect(api._polls, pollsBefore, reason: 'no second Apify run');
    });

    test('falls through to the next provider when apify fails', () async {
      final cache = ResolutionCache(ttl: const Duration(minutes: 60));
      const settings = ApifySettings(
        token: 'tok',
        actorId: 'vendor/actor',
        runTimeout: Duration(seconds: 10),
        pollInterval: Duration(milliseconds: 1),
      );
      final failingApi = FakeApifyApi(runStatus: 'FAILED');
      final resolver = PlaylistResolver(
        providers: [
          CachedPlaylistProvider(cache),
          ApifyPlaylistProvider(
              ApifyClient(dio: failingApi.buildDio(), settings: settings)),
          _StubProvider(),
        ],
        cache: cache,
      );
      const input = PlaylistResolveInput(
        playlistId: 'pppppppppppppppppppppp',
        url: 'https://open.spotify.com/playlist/pppppppppppppppppppppp',
      );
      final result = await resolver.resolve(input);
      expect(result.source, 'stub');
    });

    test('reports the last error when every provider fails', () async {
      final cache = ResolutionCache(ttl: const Duration(minutes: 60));
      const settings = ApifySettings(
        token: 'tok',
        actorId: 'vendor/actor',
        runTimeout: Duration(seconds: 10),
        pollInterval: Duration(milliseconds: 1),
      );
      final failingApi = FakeApifyApi(runStatus: 'FAILED');
      final resolver = PlaylistResolver(
        providers: [
          CachedPlaylistProvider(cache),
          ApifyPlaylistProvider(
              ApifyClient(dio: failingApi.buildDio(), settings: settings)),
        ],
        cache: cache,
      );
      const input = PlaylistResolveInput(
        playlistId: 'pppppppppppppppppppppp',
        url: 'https://open.spotify.com/playlist/pppppppppppppppppppppp',
      );
      await expectLater(resolver.resolve(input),
          throwsA(isA<ResolveError>()
              .having((e) => e.code, 'code', ResolveErrorCode.apifyActorError)));
    });
  });
}

class _StubProvider implements PlaylistMetadataProvider {
  @override
  String get id => 'stub';

  @override
  bool canResolve(PlaylistResolveInput input) => true;

  @override
  Future<PlaylistResolution> resolve(PlaylistResolveInput input) async {
    return const PlaylistResolution(
      playlist: NormalizedPlaylist(id: 'x', name: 'Stub', trackCount: 1),
      tracks: [
        NormalizedTrack(
            sourceTrackId: 's',
            position: 0,
            title: 'Stub',
            artists: [],
            durationMs: 0),
      ],
      source: 'stub',
      method: 'stub',
      total: 1,
      resolved: 1,
      unavailable: 0,
    );
  }
}
