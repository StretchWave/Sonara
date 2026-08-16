import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/metadata/musicbrainz_client.dart';
import 'package:sonara/services/spotify/playlist_migration_item.dart';
import 'package:sonara/services/spotify/playlist_migration_service.dart';
import 'package:sonara/services/spotify/provider_track_resolver.dart';
import 'package:sonara/services/spotify/spotify_source_track.dart';
import 'package:sonara/services/spotify/track_matcher.dart';
import 'package:hive/hive.dart';

import 'helpers/fake_dio_adapter.dart';

Map<String, dynamic> recordingJson({
  String id = 'mbid-1',
  String title = 'Blinding Lights',
  int? length = 200000,
  List<String> isrcs = const ['USUMV2403154'],
  List<Map<String, dynamic>> releases = const [
    {'date': '2019-11-29'},
  ],
  List<Map<String, dynamic>> artists = const [
    {'name': 'The Weeknd'},
  ],
}) =>
    {
      'id': id,
      'title': title,
      'length': length,
      'isrcs': isrcs,
      'releases': releases,
      'artist-credit': artists,
      'score': 100,
    };

MusicBrainzClient clientWith(FakeDioAdapter adapter) =>
    MusicBrainzClient(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('musicbrainz_test');
    Hive.init(tempDir.path);
    await Hive.openBox('AppPrefs');
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  group('MusicBrainzClient.findRecording', () {
    test('returns the best recording with ISRC and release date', () async {
      final adapter = FakeDioAdapter();
      late RequestOptions seen;
      adapter.handler = (o) {
        seen = o;
        return jsonResponse({
          'recordings': [recordingJson()],
        });
      };
      final client = clientWith(adapter);

      final result = await client.findRecording(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        album: 'After Hours',
        durationMs: 200000,
      );

      expect(result, isNotNull);
      expect(result!.isrcs, ['USUMV2403154']);
      expect(result.releaseDate, '2019-11-29');
      expect(result.lengthMs, 200000);
      expect(seen.queryParameters['query'],
          contains('recording:"Blinding Lights"'));
      expect(seen.queryParameters['query'], contains('artist:"The Weeknd"'));
      expect(seen.queryParameters['query'], contains('release:"After Hours"'));
      expect(seen.queryParameters['fmt'], 'json');
    });

    test('prefers the candidate whose duration matches', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse({
            'recordings': [
              recordingJson(id: 'wrong', title: 'Blinding Lights', length: 320000),
              recordingJson(id: 'right', title: 'Blinding Lights', length: 200000),
            ],
          });
      final client = clientWith(adapter);

      final result = await client.findRecording(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        durationMs: 200000,
      );
      expect(result!.mbid, 'right');
    });

    test('rejects candidates whose title does not match', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse({
            'recordings': [
              recordingJson(title: 'Completely Different Song', length: 200000),
            ],
          });
      final client = clientWith(adapter);

      final result = await client.findRecording(
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        durationMs: 200000,
      );
      expect(result, isNull);
    });

    test('returns null when the search has no recordings', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse({'recordings': <Object>[]});
      final client = clientWith(adapter);

      expect(
          await client.findRecording(
              title: 'X', artist: 'Y', durationMs: 10000),
          isNull);
    });

    test('503 with Retry-After surfaces MusicBrainzRateLimited', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) =>
          jsonResponse({}, status: 503, headers: {'retry-after': '9'});
      final client = clientWith(adapter);

      await expectLater(
        client.findRecording(title: 'X', artist: 'Y'),
        throwsA(isA<MusicBrainzRateLimited>()
            .having((e) => e.retryAfter, 'retryAfter', const Duration(seconds: 9))),
      );
    });
  });

  group('MusicBrainz enrichment stage', () {
    PlaylistMigrationService serviceWith(FakeDioAdapter adapter) =>
        PlaylistMigrationService(
          resolver: ProviderTrackResolver([_NoopResolver()]),
          musicBrainz: clientWith(adapter),
        );

    PlaylistMigrationItem item(String title,
            {String? isrc, int durationMs = 200000}) =>
        PlaylistMigrationItem(
          sourceTrack: SpotifySourceTrack(
            spotifyId: 's1',
            title: title,
            artists: const ['The Weeknd'],
            album: 'After Hours',
            durationMs: durationMs,
            isrc: isrc,
          ),
        );

    test('fills the ISRC for tracks that lack one', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse({
            'recordings': [recordingJson()],
          });
      final service = serviceWith(adapter);
      final items = [item('Blinding Lights')];

      await service.enrichWithMusicBrainz(items);

      expect(items.single.sourceTrack.isrc, 'USUMV2403154');
      expect(items.single.sourceTrack.releaseDate?.year, 2019);
      expect(adapter.requestCount, 1);
    });

    test('skips tracks that already have an ISRC', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse({
            'recordings': [recordingJson()],
          });
      final service = serviceWith(adapter);

      await service.enrichWithMusicBrainz([item('Blinding Lights', isrc: 'USKNOWN')]);
      expect(adapter.requestCount, 0);
    });

    test('caches results by metadata hash (no second network call)',
        () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse({
            'recordings': [recordingJson()],
          });
      final service = serviceWith(adapter);

      await service.enrichWithMusicBrainz([item('Blinding Lights')]);
      expect(adapter.requestCount, 1);

      await service.enrichWithMusicBrainz([item('Blinding Lights')]);
      expect(adapter.requestCount, 1);
    });

    test('negative results are cached too', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse({'recordings': <Object>[]});
      final service = serviceWith(adapter);

      await service.enrichWithMusicBrainz([item('Unknown Song')]);
      expect(adapter.requestCount, 1);

      await service.enrichWithMusicBrainz([item('Unknown Song')]);
      expect(adapter.requestCount, 1);
    });

    test('a rate limit retries once then continues quietly', () async {
      final adapter = FakeDioAdapter();
      var calls = 0;
      adapter.handler = (o) {
        calls++;
        if (calls == 1) {
          return jsonResponse({}, status: 503, headers: {'retry-after': '1'});
        }
        return jsonResponse({
          'recordings': [recordingJson()],
        });
      };
      final service = serviceWith(adapter);
      final items = [item('Blinding Lights')];

      await service.enrichWithMusicBrainz(items);
      expect(items.single.sourceTrack.isrc, 'USUMV2403154');
      expect(adapter.requestCount, 2);
    });

    test('a network failure never fails the import', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => throw DioException.connectionError(
          requestOptions: RequestOptions(path: '/recording/'),
          reason: 'test connection failure');
      final service = serviceWith(adapter);
      final items = [item('Blinding Lights')];

      await service.enrichWithMusicBrainz(items);
      expect(items.single.sourceTrack.isrc, isNull);
      expect(items.single.status, MigrationStatus.pending,
          reason: 'enrichment must not touch item status');
    });
  });
}

class _NoopResolver implements TrackResolver {
  @override
  MusicProvider get provider => MusicProvider.youtubeMusic;

  @override
  Future<List<MediaItem>> searchSongs(String query,
          {int limit = 10}) async =>
      const [];
}
