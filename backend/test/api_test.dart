import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:sonara_backend/src/api.dart';
import 'package:sonara_backend/src/cache.dart';
import 'package:sonara_backend/src/models.dart';
import 'package:sonara_backend/src/providers/playlist_provider.dart';
import 'package:sonara_backend/src/rate_limit.dart';
import 'package:sonara_backend/src/resolver.dart';
import 'package:test/test.dart';

const _playlistUrl = 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M';

class StubProvider implements PlaylistMetadataProvider {
  final PlaylistResolution Function() build;
  final ResolveError? failWith;
  final bool configured;
  int calls = 0;

  StubProvider({
    required this.build,
    this.failWith,
    this.configured = true,
  });

  @override
  String get id => 'stub';

  @override
  bool canResolve(PlaylistResolveInput input) => configured;

  @override
  Future<PlaylistResolution> resolve(PlaylistResolveInput input) async {
    calls++;
    if (failWith != null) throw failWith!;
    return build();
  }
}

PlaylistResolution okResult() => const PlaylistResolution(
      playlist: NormalizedPlaylist(
          id: '37i9dQZF1DXcBWIGoYBM5M', name: 'Phonks to Download', trackCount: 1),
      tracks: [
        NormalizedTrack(
          sourceTrackId: 't1',
          position: 0,
          title: 'Blinding Lights',
          artists: ['The Weeknd'],
          album: 'After Hours',
          durationMs: 200000,
          isrc: 'USUMV2403154',
          explicit: false,
        ),
      ],
      source: 'spotify',
      method: 'official_api',
      total: 1,
      resolved: 1,
      unavailable: 0,
    );

Handler handlerWith(PlaylistResolver resolver, {RateLimiter? limiter}) =>
    buildHandler(resolver: resolver, rateLimiter: limiter, clientIp: (_) => 'test-ip');

Future<Response> post(Handler h, String body) async => await h(Request(
    'POST',
    Uri.parse('http://localhost/api/playlist/resolve'),
    body: body,
    headers: {'content-type': 'application/json'}));

Future<Response> get(Handler h, String path) async =>
    await h(Request('GET', Uri.parse('http://localhost$path')));

void main() {
  test('POST resolves a playlist URL and returns the normalized shape',
      () async {
    final cache = ResolutionCache();
    final provider = StubProvider(build: okResult);
    final handler = handlerWith(PlaylistResolver(
        providers: [CachedPlaylistProvider(cache), provider], cache: cache));

    final res = await post(handler, jsonEncode({'url': _playlistUrl}));

    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['success'], true);
    expect(body['source']['provider'], 'spotify');
    expect((body['playlist'] as Map)['name'], 'Phonks to Download');
    final tracks = body['tracks'] as List;
    expect(tracks, hasLength(1));
    final track = tracks.first as Map;
    expect(track['title'], 'Blinding Lights');
    expect(track['artists'], ['The Weeknd']);
    expect(track['isrc'], 'USUMV2403154');
    expect(track['position'], 0);
    expect((body['resolution'] as Map)['resolved'], 1);
    expect(body['cached'], false);
    expect(provider.calls, 1);
  });

  test('second request is served from the cache', () async {
    final cache = ResolutionCache();
    final provider = StubProvider(build: okResult);
    final handler = handlerWith(PlaylistResolver(
        providers: [CachedPlaylistProvider(cache), provider], cache: cache));

    await post(handler, jsonEncode({'url': _playlistUrl}));
    final res2 = await post(handler, jsonEncode({'url': _playlistUrl}));
    final body = jsonDecode(await res2.readAsString()) as Map;

    expect(body['cached'], true);
    expect(provider.calls, 1);
  });

  test('GET /api/playlist/spotify/{id} resolves by id', () async {
    final cache = ResolutionCache();
    final provider = StubProvider(build: okResult);
    final handler = handlerWith(PlaylistResolver(
        providers: [CachedPlaylistProvider(cache), provider], cache: cache));

    final res = await get(handler, '/api/playlist/spotify/37i9dQZF1DXcBWIGoYBM5M');
    expect(res.statusCode, 200);
    expect(provider.calls, 1);
  });

  test('track and album URLs get a structured UNSUPPORTED error', () async {
    final cache = ResolutionCache();
    final handler = handlerWith(PlaylistResolver(
        providers: [CachedPlaylistProvider(cache)], cache: cache));

    final res = await post(handler, jsonEncode({
      'url': 'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC'
    }));
    expect(res.statusCode, 400);
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['success'], false);
    expect((body['error'] as Map)['code'], 'UNSUPPORTED_SPOTIFY_URL');
    expect((body['error'] as Map)['message'], contains('track'));
  });

  test('random URLs are rejected without any fetching', () async {
    final cache = ResolutionCache();
    final provider = StubProvider(build: okResult);
    final handler = handlerWith(PlaylistResolver(
        providers: [CachedPlaylistProvider(cache), provider], cache: cache));

    final res = await post(handler, jsonEncode({'url': 'https://evil.example/x'}));
    expect(res.statusCode, 400);
    expect(provider.calls, 0);
  });

  test('malformed JSON and missing url fields are rejected', () async {
    final cache = ResolutionCache();
    final handler = handlerWith(PlaylistResolver(
        providers: [CachedPlaylistProvider(cache)], cache: cache));

    expect((await post(handler, 'not json')).statusCode, 400);
    expect((await post(handler, jsonEncode({'foo': 1}))).statusCode, 400);
  });

  test('provider failures map to structured HTTP errors', () async {
    Future<int> statusFor(ResolveError e) async {
      final cache = ResolutionCache();
      final handler = handlerWith(PlaylistResolver(
        providers: [
          CachedPlaylistProvider(cache),
          StubProvider(build: okResult, failWith: e),
        ],
        cache: cache,
      ));
      final res = await post(handler, jsonEncode({'url': _playlistUrl}));
      final body = jsonDecode(await res.readAsString()) as Map;
      expect(body['success'], false);
      expect((body['error'] as Map)['code'], e.code.wire);
      return res.statusCode;
    }

    expect(
        await statusFor(const ResolveError(
            ResolveErrorCode.playlistNotFound, 'gone')),
        404);
    expect(
        await statusFor(const ResolveError(
            ResolveErrorCode.permissionDenied, 'private')),
        403);
    expect(
        await statusFor(const ResolveError(
            ResolveErrorCode.providerRateLimited, 'slow down')),
        429);
    expect(
        await statusFor(const ResolveError(
            ResolveErrorCode.authenticationRequired, 'creds missing')),
        401);
    expect(
        await statusFor(const ResolveError(
            ResolveErrorCode.providerUnavailable, 'down')),
        503);
  });

  test('rate limiter returns 429 with Retry-After', () async {
    final cache = ResolutionCache();
    final handler = handlerWith(
      PlaylistResolver(
        providers: [
          CachedPlaylistProvider(cache),
          StubProvider(build: okResult),
        ],
        cache: cache,
      ),
      limiter: RateLimiter(maxRequests: 2, window: const Duration(minutes: 1)),
    );

    final ok1 = await post(handler, jsonEncode({'url': _playlistUrl}));
    final ok2 = await post(handler, jsonEncode({'url': _playlistUrl}));
    final limited = await post(handler, jsonEncode({'url': _playlistUrl}));

    expect(ok1.statusCode, 200);
    expect(ok2.statusCode, 200);
    expect(limited.statusCode, 429);
    expect(limited.headers['retry-after'], isNotNull);
  });

  test('health reports configuration status', () async {
    final cache = ResolutionCache();
    final handler = handlerWith(PlaylistResolver(
        providers: [CachedPlaylistProvider(cache)], cache: cache));

    final res = await get(handler, '/health');
    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map;
    expect(body['ok'], true);
    expect(body['configured'], false);
  });
}
