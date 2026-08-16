import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/lyrics/lrclib_api.dart';
import 'package:harmonymusic/services/spotify/playlist_migration_item.dart';
import 'package:harmonymusic/services/spotify/playlist_migration_service.dart';
import 'package:harmonymusic/services/spotify/provider_track_resolver.dart';
import 'package:harmonymusic/services/spotify/spotify_source_track.dart';
import 'package:harmonymusic/services/spotify/track_matcher.dart';
import 'package:hive/hive.dart';

import 'helpers/fake_dio_adapter.dart';

/// Resolver that counts how many searches it performed and maps queries to
/// results through a builder callback.
class _CountingResolver implements TrackResolver {
  final MediaItem Function(String query) builder;
  int calls = 0;

  _CountingResolver(this.builder);

  @override
  MusicProvider get provider => MusicProvider.youtubeMusic;

  @override
  Future<List<MediaItem>> searchSongs(String query, {int limit = 10}) async {
    calls++;
    return [builder(query)];
  }
}

MediaItem _track(String id, String title, String artist,
        {int seconds = 200}) =>
    MediaItem(
      id: id,
      title: title,
      artist: artist,
      duration: Duration(seconds: seconds),
      extras: const {},
    );

SpotifySourceTrack _src(
  String id,
  String title, {
  List<String> artists = const ['The Weeknd'],
  int durationMs = 200000,
  String? isrc,
}) =>
    SpotifySourceTrack(
      spotifyId: id,
      title: title,
      artists: artists,
      album: 'After Hours',
      durationMs: durationMs,
      isrc: isrc,
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('migration_flow_test');
    Hive.init(tempDir.path);
    await Hive.openBox('AppPrefs');
    await Hive.openBox('SpotifyResolutionCache');
    await Hive.openBox('SpotifyMigrations');
    await Hive.openBox('lyrics');
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  // ------------------------------------------------------------------
  // Resolution cache + force refresh
  // ------------------------------------------------------------------

  group('resolution cache', () {
    test('second resolution reuses the cached match without searching again',
        () async {
      // Resolver returns an exact match for the first strategy, so exactly
      // one search is expected per fresh resolution.
      final resolver = _CountingResolver((query) =>
          _track('yt-blinding', 'Blinding Lights', 'The Weeknd'));
      final service = PlaylistMigrationService(
          resolver: ProviderTrackResolver([resolver]));
      final item = PlaylistMigrationItem(
          sourceTrack: _src('s1', 'Blinding Lights', isrc: 'USCACHE1'));

      await service.resolveAll([item]);
      expect(item.status, MigrationStatus.matched);
      expect(resolver.calls, 1);

      // Cached: no provider request at all.
      final item2 = PlaylistMigrationItem(
          sourceTrack: _src('s1', 'Blinding Lights', isrc: 'USCACHE1'));
      await service.resolveAll([item2]);
      expect(resolver.calls, 1);
      expect(item2.status, MigrationStatus.matched);
    });

    test('forceRefresh bypasses the cache and searches again', () async {
      var id = 'yt-blinding';
      final resolver = _CountingResolver(
          (query) => _track(id, 'Blinding Lights', 'The Weeknd'));
      final service = PlaylistMigrationService(
          resolver: ProviderTrackResolver([resolver]));
      final item = PlaylistMigrationItem(
          sourceTrack: _src('s1', 'Blinding Lights', isrc: 'USFR1'));

      await service.resolveAll([item]);
      expect(resolver.calls, 1);
      expect(item.matchedTrack!.id, 'yt-blinding');

      // The provider now returns a different recording id.
      id = 'yt-blinding-v2';
      await service.resolveAll([item], forceRefresh: true);
      // The first strategy still scores high, so exactly one new search.
      expect(resolver.calls, 2);
      expect(item.matchedTrack!.id, 'yt-blinding-v2');
    });

    test('cache key changes when the source metadata changes', () async {
      final resolver = _CountingResolver(
          (query) => _track('yt-blinding', 'Blinding Lights', 'The Weeknd'));
      final service = PlaylistMigrationService(
          resolver: ProviderTrackResolver([resolver]));

      await service.resolveAll([
        PlaylistMigrationItem(
            sourceTrack: _src('s1', 'Blinding Lights', durationMs: 200000))
      ]);
      expect(resolver.calls, 1);

      // Same track id but different duration -> different metadata hash ->
      // cache miss.
      await service.resolveAll([
        PlaylistMigrationItem(
            sourceTrack: _src('s1', 'Blinding Lights', durationMs: 215000))
      ]);
      expect(resolver.calls, 2);
    });
  });

  // ------------------------------------------------------------------
  // Cancellation
  // ------------------------------------------------------------------

  group('cancellation', () {
    test('stops between batches and preserves resolved results', () async {
      final resolver = _CountingResolver(
          (query) => _track('yt-$query', 'Some Song', 'Someone'));
      final service = PlaylistMigrationService(
          resolver: ProviderTrackResolver([resolver]));
      final items = [
        for (var i = 0; i < 12; i++)
          PlaylistMigrationItem(
              sourceTrack: _src('s$i', 'Song $i', isrc: 'USCANCEL$i')),
      ];

      // Cancellation is polled between batches, so exactly the first batch
      // (kMaxConcurrentResolutions items) finishes; the rest stay pending.
      final batchSize = kMaxConcurrentResolutions;
      var done = 0;
      await service.resolveAll(
        items,
        onProgress: (completed, total) => done = completed,
        shouldCancel: () => done >= batchSize,
      );

      expect(done, batchSize);
      expect(
          items.where((e) => e.status == MigrationStatus.pending).length,
          items.length - batchSize);
      expect(
          items.where((e) => e.status != MigrationStatus.pending).length,
          batchSize);
    });
  });

  // ------------------------------------------------------------------
  // Re-import analysis
  // ------------------------------------------------------------------

  group('analyzeReimport', () {
    test('classifies unchanged, changed and added tracks', () {
      final service = PlaylistMigrationService(
          resolver: ProviderTrackResolver([_CountingResolver((q) => _track('t', 'T', 'A'))]));

      final stored = [
        PlaylistMigrationItem(sourceTrack: _src('s1', 'Same Song')),
        PlaylistMigrationItem(
            sourceTrack: _src('s2', 'Changed Song', durationMs: 200000)),
      ];
      final fresh = [
        _src('s1', 'Same Song'),
        _src('s2', 'Changed Song', durationMs: 180000),
        _src('s3', 'Brand New'),
      ];

      final analysis = service.analyzeReimport(stored, fresh);
      expect(analysis.unchanged.map((e) => e.sourceTrack.spotifyId),
          ['s1']);
      expect(analysis.changed.map((e) => e.sourceTrack.spotifyId), ['s2']);
      expect(analysis.added.map((t) => t.spotifyId), ['s3']);
      expect(analysis.total, 3);
    });

    test('removed tracks simply disappear from the analysis', () {
      final service = PlaylistMigrationService(
          resolver: ProviderTrackResolver([_CountingResolver((q) => _track('t', 'T', 'A'))]));
      final stored = [
        PlaylistMigrationItem(sourceTrack: _src('s1', 'Kept')),
        PlaylistMigrationItem(sourceTrack: _src('s2', 'Removed')),
      ];
      final fresh = [_src('s1', 'Kept')];

      final analysis = service.analyzeReimport(stored, fresh);
      expect(analysis.unchanged, hasLength(1));
      expect(analysis.added, isEmpty);
      expect(analysis.total, 1);
    });
  });

  // ------------------------------------------------------------------
  // Persistence round trip
  // ------------------------------------------------------------------

  group('persistence', () {
    test('persistProgress -> loadMigration -> itemsFromStored round trips',
        () async {
      final service = PlaylistMigrationService(
          resolver: ProviderTrackResolver([_CountingResolver((q) => _track('t', 'T', 'A'))]));
      final items = [
        PlaylistMigrationItem(
          sourceTrack: _src('s1', 'Blinding Lights', isrc: 'US123'),
          matchedTrack: _track('yt1', 'Blinding Lights', 'The Weeknd'),
          matchedProvider: MusicProvider.youtubeMusic,
          matchScore: 0.98,
          confidence: MatchConfidence.high,
          status: MigrationStatus.matched,
          manualOverride: true,
          lyrics: MigrationLyrics(
            status: LyricsStatus.synced,
            synced: '[00:01.00]Line',
            plain: 'Line',
            lrclibId: 42,
            retrievedAt: 1700000000000,
          ),
        ),
      ];

      await service.persistProgress(
          spotifyPlaylistId: 'p1',
          spotifyPlaylistName: 'My Playlist',
          items: items);
      final stored = await service.loadMigration('p1');
      expect(stored, isNotNull);
      expect(stored!['name'], 'My Playlist');
      expect(stored['status'], 'in_progress');

      final restored = service.itemsFromStored(stored);
      expect(restored, hasLength(1));
      final item = restored.first;
      expect(item.sourceTrack.spotifyId, 's1');
      expect(item.sourceTrack.isrc, 'US123');
      expect(item.metadataHash,
          computeMetadataHash(item.sourceTrack));
      expect(item.matchedTrack!.id, 'yt1');
      expect(item.matchedProvider, MusicProvider.youtubeMusic);
      expect(item.matchScore, 0.98);
      expect(item.confidence, MatchConfidence.high);
      expect(item.manualOverride, isTrue);
      expect(item.lyrics.status, LyricsStatus.synced);
      expect(item.lyrics.lrclibId, 42);
      expect(item.lyrics.retrievedAt, 1700000000000);
    });

    test('completeMigration marks the record completed', () async {
      final service = PlaylistMigrationService(
          resolver: ProviderTrackResolver([_CountingResolver((q) => _track('t', 'T', 'A'))]));
      await service.completeMigration(
          spotifyPlaylistId: 'p1',
          spotifyPlaylistName: 'P',
          items: []);
      final stored = await service.loadMigration('p1');
      expect(stored!['status'], 'completed');
    });
  });

  // ------------------------------------------------------------------
  // Confidence filter
  // ------------------------------------------------------------------

  group('passesConfidenceFilter', () {
    PlaylistMigrationItem item(MatchConfidence c,
            {bool manual = false, bool matched = true}) =>
        PlaylistMigrationItem(
          sourceTrack: _src('s1', 'Song'),
          matchedTrack: matched ? _track('yt1', 'Song', 'A') : null,
          matchedProvider: MusicProvider.youtubeMusic,
          matchScore: c == MatchConfidence.high
              ? 0.95
              : c == MatchConfidence.medium
                  ? 0.8
                  : 0.65,
          confidence: c,
          status: matched
              ? (c == MatchConfidence.high
                  ? MigrationStatus.matched
                  : MigrationStatus.lowConfidence)
              : MigrationStatus.unmatched,
          manualOverride: manual,
        );

    final service = PlaylistMigrationService(
        resolver: ProviderTrackResolver([_CountingResolver((q) => _track('t', 'T', 'A'))]));

    test('high passes every filter', () {
      final i = item(MatchConfidence.high);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.high), isTrue);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.highAndMedium),
          isTrue);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.all), isTrue);
    });

    test('medium passes highAndMedium and all, not high', () {
      final i = item(MatchConfidence.medium);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.high), isFalse);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.highAndMedium),
          isTrue);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.all), isTrue);
    });

    test('low passes only all', () {
      final i = item(MatchConfidence.low);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.high), isFalse);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.highAndMedium),
          isFalse);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.all), isTrue);
    });

    test('manual overrides always pass', () {
      final i = item(MatchConfidence.low, manual: true);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.high), isTrue);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.highAndMedium),
          isTrue);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.all), isTrue);
    });

    test('unmatched never passes', () {
      final i = item(MatchConfidence.unmatched, matched: false);
      expect(service.passesConfidenceFilter(i, ConfidenceFilter.all), isFalse);
    });
  });

  // ------------------------------------------------------------------
  // LRCLIB lyrics pipeline
  // ------------------------------------------------------------------

  group('lyrics pipeline', () {
    PlaylistMigrationItem matchedItem(String isrc,
            {int durationMs = 200000}) =>
        PlaylistMigrationItem(
          sourceTrack: _src('s1', 'Blinding Lights',
              durationMs: durationMs, isrc: isrc),
          matchedTrack: _track('yt-blinding', 'Blinding Lights', 'The Weeknd'),
          matchedProvider: MusicProvider.youtubeMusic,
          matchScore: 0.98,
          confidence: MatchConfidence.high,
          status: MigrationStatus.matched,
        );

    PlaylistMigrationService serviceWith(FakeDioAdapter adapter) =>
        PlaylistMigrationService(
          resolver:
              ProviderTrackResolver([_CountingResolver((q) => _track('t', 'T', 'A'))]),
          lrcLib: LrcLibClient(
              dio: Dio(BaseOptions())..httpClientAdapter = adapter),
        );

    test('synced lyrics are applied and cached by ISRC', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (o) =>
          o.path == '/get' ? jsonResponse(lrcJson()) : jsonResponse([]);
      final service = serviceWith(adapter);
      final item = matchedItem('USLYR1');

      await service.resolveLyrics([item]);
      expect(item.lyrics.status, LyricsStatus.synced);
      expect(item.lyrics.synced, contains('[00:01.00]'));
      expect(adapter.requestCount, 1);

      // Second run: cache hit, zero network requests.
      final item2 = matchedItem('USLYR1');
      await service.resolveLyrics([item2]);
      expect(adapter.requestCount, 1);
      expect(item2.lyrics.status, LyricsStatus.synced);
    });

    test('plain-only lyrics are marked plain, never synced', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse(
          lrcJson(synced: null, plain: 'Just plain words'));
      final service = serviceWith(adapter);
      final item = matchedItem('USPLAIN1');

      await service.resolveLyrics([item]);
      expect(item.lyrics.status, LyricsStatus.plain);
      expect(item.lyrics.synced, isNull);
      expect(item.lyrics.plain, 'Just plain words');
    });

    test('instrumental tracks are recorded without lyrics', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) =>
          jsonResponse(lrcJson(synced: null, plain: null, instrumental: true));
      final service = serviceWith(adapter);
      final item = matchedItem('USINST1');

      await service.resolveLyrics([item]);
      expect(item.lyrics.status, LyricsStatus.instrumental);
      expect(item.lyrics.instrumental, isTrue);
    });

    test('404 falls back to a scored search and accepts a good candidate',
        () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (o) => o.path == '/get'
          ? jsonResponse({}, status: 404)
          : jsonResponse([lrcJson()]);
      final service = serviceWith(adapter);
      final item = matchedItem('USSEARCH1');

      await service.resolveLyrics([item]);
      expect(item.lyrics.status, LyricsStatus.synced);
      expect(adapter.requestCount, 2); // one get + one search
    });

    test('search candidates below confidence are rejected', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (o) => o.path == '/get'
          ? jsonResponse({}, status: 404)
          : jsonResponse([
              lrcJson(
                  id: 99,
                  trackName: 'Totally Different Song',
                  artistName: 'Someone Else',
                  duration: 42),
            ]);
      final service = serviceWith(adapter);
      final item = matchedItem('USREJECT1');

      await service.resolveLyrics([item]);
      expect(item.lyrics.status, LyricsStatus.notFound);
    });

    test('429 honors Retry-After once, then succeeds', () async {
      final adapter = FakeDioAdapter();
      var calls = 0;
      adapter.handler = (o) {
        calls++;
        if (o.path == '/get' && calls == 1) {
          return jsonResponse({}, status: 429, headers: {'retry-after': '1'});
        }
        return jsonResponse(lrcJson());
      };
      final service = serviceWith(adapter);
      final item = matchedItem('US429A');

      await service.resolveLyrics([item]);
      expect(item.lyrics.status, LyricsStatus.synced);
      expect(adapter.requestCount, 2);
    });

    test('persistent 429 gives up instead of hammering', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) =>
          jsonResponse({}, status: 429, headers: {'retry-after': '1'});
      final service = serviceWith(adapter);
      final item = matchedItem('US429B');

      await service.resolveLyrics([item]);
      expect(item.lyrics.status, LyricsStatus.notFound);
      // get (1) + single retry (1) = 2 total — no search, no further retries.
      expect(adapter.requestCount, 2);
    });

    test('existing playback lyrics cache is reused without network',
        () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse(lrcJson());
      final service = serviceWith(adapter);
      final box = await Hive.openBox('lyrics');
      await box.put('yt-blinding',
          {'synced': '[00:01.00]Cached', 'plainLyrics': 'Cached'});
      await box.close();
      final item = matchedItem('USPLAY1');

      await service.resolveLyrics([item]);
      expect(item.lyrics.status, LyricsStatus.synced);
      expect(item.lyrics.synced, '[00:01.00]Cached');
      expect(adapter.requestCount, 0);
    });

    test('unmatched tracks skip lyrics entirely', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse(lrcJson());
      final service = serviceWith(adapter);
      final item = PlaylistMigrationItem(
          sourceTrack: _src('s1', 'Blinding Lights', isrc: 'USNONE1'));

      await service.resolveLyrics([item]);
      expect(item.lyrics.status, LyricsStatus.none);
      expect(adapter.requestCount, 0);
    });
  });

  // ------------------------------------------------------------------
  // Metadata hash
  // ------------------------------------------------------------------

  group('computeMetadataHash', () {
    test('same recording -> same hash (case insensitive)', () {
      expect(
        computeMetadataHash(_src('s1', 'Blinding Lights', isrc: 'USABC')),
        computeMetadataHash(_src('s2', 'blinding lights', isrc: 'usabc')),
      );
    });

    test('different duration -> different hash', () {
      expect(
        computeMetadataHash(_src('s1', 'Blinding Lights', durationMs: 200000)),
        isNot(computeMetadataHash(
            _src('s1', 'Blinding Lights', durationMs: 210000))),
      );
    });

    test('different ISRC -> different hash', () {
      expect(
        computeMetadataHash(_src('s1', 'Blinding Lights', isrc: 'USAAA')),
        isNot(computeMetadataHash(_src('s1', 'Blinding Lights', isrc: 'USBBB'))),
      );
    });
  });
}
