import 'package:synora_backend/src/cache.dart';
import 'package:synora_backend/src/models.dart';
import 'package:synora_backend/src/providers/playlist_provider.dart';
import 'package:synora_backend/src/resolver.dart';
import 'package:test/test.dart';

PlaylistResolution resolution(String source, {int trackCount = 2}) =>
    PlaylistResolution(
      playlist: NormalizedPlaylist(
          id: 'p1', name: 'Playlist from $source', trackCount: trackCount),
      tracks: [
        for (var i = 0; i < trackCount; i++)
          NormalizedTrack(
              sourceTrackId: '$source-$i',
              position: i,
              title: 'Track $i',
              artists: const ['Artist'],
              durationMs: 200000),
      ],
      source: source,
      method: 'test',
      total: trackCount,
      resolved: trackCount,
      unavailable: 0,
    );

class FakeProvider implements PlaylistMetadataProvider {
  @override
  final String id;
  final List<ResolveError> failWith;
  final PlaylistResolution? result;
  int calls = 0;
  final Duration? delay;

  FakeProvider(this.id,
      {this.failWith = const [], this.result, this.delay});

  @override
  bool canResolve(PlaylistResolveInput input) => true;

  @override
  Future<PlaylistResolution> resolve(PlaylistResolveInput input) async {
    calls++;
    if (delay != null) await Future.delayed(delay!);
    if (failWith.isNotEmpty) throw failWith.first;
    return result!;
  }
}

PlaylistResolveInput input([String id = 'p1']) =>
    PlaylistResolveInput(playlistId: id, url: 'https://open.spotify.com/playlist/$id');

void main() {
  group('provider chain', () {
    test('cache provider serves repeat requests without upstream calls',
        () async {
      final cache = ResolutionCache();
      final upstream = FakeProvider('spotify', result: resolution('spotify'));
      final resolver = PlaylistResolver(
        providers: [CachedPlaylistProvider(cache), upstream],
        cache: cache,
      );

      final first = await resolver.resolve(input());
      final second = await resolver.resolve(input());

      expect(first.source, 'spotify');
      expect(second.source, 'spotify');
      expect(second.cached, isTrue);
      expect(upstream.calls, 1);
    });

    test('falls through to the next provider when one fails', () async {
      final cache = ResolutionCache();
      final failing = FakeProvider('spotify',
          failWith: const [
            ResolveError(ResolveErrorCode.permissionDenied, 'private')
          ]);
      final fallback =
          FakeProvider('third-party', result: resolution('third-party'));
      final resolver = PlaylistResolver(
        providers: [CachedPlaylistProvider(cache), failing, fallback],
        cache: cache,
      );

      final result = await resolver.resolve(input());
      expect(result.source, 'third-party');
    });

    test('all providers failing surfaces the last structured error', () async {
      final cache = ResolutionCache();
      final resolver = PlaylistResolver(
        providers: [
          FakeProvider('a',
              failWith: const [
                ResolveError(ResolveErrorCode.playlistNotFound, 'gone')
              ]),
          FakeProvider('b',
              failWith: const [
                ResolveError(ResolveErrorCode.providerUnavailable, 'down')
              ]),
        ],
        cache: cache,
      );

      await expectLater(
        resolver.resolve(input()),
        throwsA(isA<ResolveError>()
            .having((e) => e.code, 'code', ResolveErrorCode.providerUnavailable)),
      );
    });

    test('coalesces concurrent identical requests into one upstream call',
        () async {
      final cache = ResolutionCache();
      final upstream = FakeProvider('spotify',
          result: resolution('spotify'), delay: const Duration(milliseconds: 30));
      final resolver = PlaylistResolver(
        providers: [CachedPlaylistProvider(cache), upstream],
        cache: cache,
      );

      final results =
          await Future.wait([for (var i = 0; i < 10; i++) resolver.resolve(input())]);

      expect(results, hasLength(10));
      expect(upstream.calls, 1);
      expect(cache.length, 1);
    });

    test('refresh bypasses the cache but re-writes it', () async {
      final cache = ResolutionCache();
      final upstream = FakeProvider('spotify', result: resolution('spotify'));
      final resolver = PlaylistResolver(
        providers: [CachedPlaylistProvider(cache), upstream],
        cache: cache,
      );

      await resolver.resolve(input());
      await resolver.resolve(input(), refresh: true);

      expect(upstream.calls, 2);
      expect(cache.length, 1);
    });

    test('invalidate clears a cached playlist', () async {
      final cache = ResolutionCache();
      final upstream = FakeProvider('spotify', result: resolution('spotify'));
      final resolver = PlaylistResolver(
        providers: [CachedPlaylistProvider(cache), upstream],
        cache: cache,
      );

      await resolver.resolve(input());
      cache.invalidate('p1');
      await resolver.resolve(input());

      expect(upstream.calls, 2);
    });

    test('TTL expiry forces a fresh resolution', () async {
      var now = DateTime(2026, 1, 1);
      final cache = ResolutionCache(
          ttl: const Duration(minutes: 10), now: () => now);
      final upstream = FakeProvider('spotify', result: resolution('spotify'));
      final resolver = PlaylistResolver(
        providers: [CachedPlaylistProvider(cache), upstream],
        cache: cache,
      );

      await resolver.resolve(input());
      now = now.add(const Duration(minutes: 11));
      await resolver.resolve(input());

      expect(upstream.calls, 2);
    });
  });

  group('partial results', () {
    test('official provider counts unavailable tracks as partial', () async {
      final cache = ResolutionCache();
      final provider = FakeProvider('spotify', result: const PlaylistResolution(
        playlist: NormalizedPlaylist(
            id: 'p1', name: 'Partial', trackCount: 4),
        tracks: [
          NormalizedTrack(
              sourceTrackId: '', position: 0, title: '', artists: [], durationMs: 0),
          NormalizedTrack(
              sourceTrackId: 't1',
              position: 1,
              title: 'Only One',
              artists: ['A'],
              durationMs: 1000),
        ],
        source: 'spotify',
        method: 'official_api',
        total: 4,
        resolved: 1,
        unavailable: 3,
        warnings: [
          ResolveWarning('PARTIAL_PLAYLIST', '3 tracks could not be resolved.')
        ],
      ));
      final resolver = PlaylistResolver(
        providers: [CachedPlaylistProvider(cache), provider],
        cache: cache,
      );

      final result = await resolver.resolve(input());
      expect(result.resolved, 1);
      expect(result.unavailable, 3);
      expect(result.warnings.single.code, 'PARTIAL_PLAYLIST');
      expect(result.tracks.first.sourceTrackId, '');
    });
  });
}
