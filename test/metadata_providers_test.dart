import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/metadata/cached_migration_provider.dart';
import 'package:sonara/services/metadata/playlist_metadata_provider.dart';
import 'package:sonara/services/metadata/playlist_metadata_resolver.dart';
import 'package:sonara/services/metadata/spotify_oembed_provider.dart';
import 'package:sonara/services/metadata/spotify_official_provider.dart';
import 'package:sonara/services/spotify/playlist_migration_item.dart';
import 'package:sonara/services/spotify/playlist_migration_service.dart';
import 'package:sonara/services/spotify/provider_track_resolver.dart';
import 'package:sonara/services/spotify/spotify_api_client.dart';
import 'package:sonara/services/spotify/track_matcher.dart';
import 'package:sonara/services/spotify/spotify_source_track.dart';
import 'package:hive/hive.dart';

import 'helpers/fake_dio_adapter.dart';

const _playlistUrl = 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M';

class _FakeApiClient extends SpotifyApiClient {
  final SpotifyPlaylistData data;
  final bool session;
  final SpotifyApiException? error;
  int fetchCalls = 0;

  _FakeApiClient(this.data, {this.session = true, this.error})
      : super(dio: Dio(BaseOptions()));

  @override
  bool get hasSession => session;

  @override
  Future<SpotifyPlaylistData> fetchPlaylist(String playlistId) async {
    fetchCalls++;
    if (error != null) throw error!;
    return data;
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('metadata_providers_test');
    Hive.init(tempDir.path);
    await Hive.openBox('SpotifyMigrations');
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  group('SpotifyOEmbedProvider', () {
    test('returns playlist title and artwork without any auth', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (o) {
        expect(o.queryParameters['url'], _playlistUrl);
        return jsonResponse({
          'title': 'Today\'s Top Hits',
          'thumbnail_url': 'https://i.scdn.co/image/abc',
          'type': 'rich',
        });
      };
      final provider =
          SpotifyOEmbedProvider(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

      final result = await provider.fetchPlaylist(Uri.parse(_playlistUrl));

      expect(result.status, PlaylistMetadataStatus.partialSuccess);
      expect(result.name, 'Today\'s Top Hits');
      expect(result.artworkUrl, 'https://i.scdn.co/image/abc');
      expect(result.hasTracks, isFalse,
          reason: 'oEmbed identifies a playlist but never claims its tracks');
    });

    test('404 maps to notFound', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse({}, status: 404);
      final provider =
          SpotifyOEmbedProvider(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

      final result = await provider.fetchPlaylist(Uri.parse(_playlistUrl));
      expect(result.status, PlaylistMetadataStatus.notFound);
    });

    test('timeout maps to networkError', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 10), requestOptions: RequestOptions(path: '/oembed'));
      final provider =
          SpotifyOEmbedProvider(dio: Dio(BaseOptions())..httpClientAdapter = adapter);

      final result = await provider.fetchPlaylist(Uri.parse(_playlistUrl));
      expect(result.status, PlaylistMetadataStatus.networkError);
    });

    test('rejects non-playlist URLs', () {
      final provider = SpotifyOEmbedProvider();
      expect(provider.canHandle(Uri.parse('https://open.spotify.com/album/abc')), isFalse);
      expect(provider.canHandle(Uri.parse(_playlistUrl)), isTrue);
    });
  });

  group('SpotifyOfficialProvider', () {
    test('reports authenticationRequired when there is no session', () async {
      final provider = SpotifyOfficialProvider(_FakeApiClient(
          const SpotifyPlaylistData(id: 'p', name: 'P', tracks: []),
          session: false));

      final result = await provider.fetchPlaylist(Uri.parse(_playlistUrl));
      expect(result.status, PlaylistMetadataStatus.authenticationRequired);
    });

    test('returns tracks on success', () async {
      final api = _FakeApiClient(const SpotifyPlaylistData(
        id: 'p',
        name: 'P',
        tracks: [
          SpotifySourceTrack(
              spotifyId: 't1', title: 'Blinding Lights', artists: ['The Weeknd']),
        ],
      ));
      final provider = SpotifyOfficialProvider(api);

      final result = await provider.fetchPlaylist(Uri.parse(_playlistUrl));
      expect(result.status, PlaylistMetadataStatus.success);
      expect(result.tracks.single.title, 'Blinding Lights');
      expect(api.fetchCalls, 1);
    });

    test('maps 403 to permissionDenied, 404 to notFound, 429 to rateLimited',
        () async {
      Future<PlaylistMetadataStatus> statusFor(int code) async {
        final provider = SpotifyOfficialProvider(_FakeApiClient(
            const SpotifyPlaylistData(id: 'p', name: 'P', tracks: []),
            error: SpotifyApiException('denied', statusCode: code)));
        return (await provider.fetchPlaylist(Uri.parse(_playlistUrl))).status;
      }

      expect(await statusFor(403), PlaylistMetadataStatus.permissionDenied);
      expect(await statusFor(404), PlaylistMetadataStatus.notFound);
      expect(await statusFor(429), PlaylistMetadataStatus.rateLimited);
    });
  });

  group('CachedMigrationProvider', () {
    test('serves previously imported tracks', () async {
      final box = await Hive.openBox('SpotifyMigrations');
      await box.put('37i9dQZF1DXcBWIGoYBM5M', {
        'name': 'Cached Playlist',
        'status': 'completed',
        'migratedAt': 1,
        'items': [
          PlaylistMigrationItem(
            sourceTrack: const SpotifySourceTrack(
                spotifyId: 't1',
                title: 'Blinding Lights',
                artists: ['The Weeknd'],
                isrc: 'USABC'),
          ).toJson(),
        ],
      });
      await box.close();

      final provider = CachedMigrationProvider();
      final result = await provider.fetchPlaylist(Uri.parse(_playlistUrl));

      expect(result.status, PlaylistMetadataStatus.success);
      expect(result.name, 'Cached Playlist');
      expect(result.tracks.single.isrc, 'USABC');
    });

    test('reports notFound when nothing was cached', () async {
      final provider = CachedMigrationProvider();
      final result = await provider.fetchPlaylist(Uri.parse(_playlistUrl));
      expect(result.status, PlaylistMetadataStatus.notFound);
    });
  });

  group('PlaylistMetadataResolver', () {
    test('merges identification from oEmbed with tracks from the cache',
        () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse({
            'title': 'Today\'s Top Hits',
            'thumbnail_url': 'https://i.scdn.co/image/abc',
          });
      final box = await Hive.openBox('SpotifyMigrations');
      await box.put('37i9dQZF1DXcBWIGoYBM5M', {
        'name': 'Cached Name',
        'items': [
          PlaylistMigrationItem(
            sourceTrack: const SpotifySourceTrack(
                spotifyId: 't1',
                title: 'Blinding Lights',
                artists: ['The Weeknd']),
          ).toJson(),
        ],
      });
      await box.close();

      final resolver = PlaylistMetadataResolver([
        SpotifyOEmbedProvider(
            dio: Dio(BaseOptions())..httpClientAdapter = adapter),
        CachedMigrationProvider(),
        SpotifyOfficialProvider(_FakeApiClient(
            const SpotifyPlaylistData(id: 'p', name: 'P', tracks: []),
            session: false)),
      ]);

      final result = await resolver.resolve(Uri.parse(_playlistUrl));

      expect(result.status, PlaylistMetadataStatus.success);
      expect(result.tracks, hasLength(1));
      expect(result.tracksSource, 'cached');
      expect(result.name, 'Today\'s Top Hits');
      expect(result.authenticationRequired, isFalse,
          reason: 'tracks were acquired — no need to nag about auth');
    });

    test('official API tracks win over the cache when a session exists',
        () async {
      final box = await Hive.openBox('SpotifyMigrations');
      await box.put('37i9dQZF1DXcBWIGoYBM5M', {
        'name': 'Old',
        'items': [
          PlaylistMigrationItem(
            sourceTrack: const SpotifySourceTrack(
                spotifyId: 'old1', title: 'Old Track', artists: ['X']),
          ).toJson(),
        ],
      });
      await box.close();

      final resolver = PlaylistMetadataResolver([
        SpotifyOEmbedProvider(),
        CachedMigrationProvider(),
        SpotifyOfficialProvider(_FakeApiClient(const SpotifyPlaylistData(
          id: 'p',
          name: 'Fresh',
          tracks: [
            SpotifySourceTrack(
                spotifyId: 'new1', title: 'New Track', artists: ['Y']),
          ],
        ))),
      ]);

      final result = await resolver.resolve(Uri.parse(_playlistUrl));
      expect(result.status, PlaylistMetadataStatus.success);
      expect(result.tracksSource, 'spotify-official');
      expect(result.tracks.single.title, 'New Track');
    });

    test('identified but no track list -> partialSuccess + auth hint',
        () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) =>
          jsonResponse({'title': 'Some Playlist', 'thumbnail_url': 'x'});

      final resolver = PlaylistMetadataResolver([
        SpotifyOEmbedProvider(
            dio: Dio(BaseOptions())..httpClientAdapter = adapter),
        SpotifyOfficialProvider(_FakeApiClient(
            const SpotifyPlaylistData(id: 'p', name: 'P', tracks: []),
            session: false)),
      ]);

      final result = await resolver.resolve(Uri.parse(_playlistUrl));
      expect(result.status, PlaylistMetadataStatus.partialSuccess);
      expect(result.authenticationRequired, isTrue);
      expect(result.name, 'Some Playlist');
    });

    test('nothing succeeds -> most actionable failure', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse({}, status: 404);
      final resolver = PlaylistMetadataResolver([
        SpotifyOEmbedProvider(
            dio: Dio(BaseOptions())..httpClientAdapter = adapter),
      ]);

      final result = await resolver.resolve(Uri.parse(_playlistUrl));
      expect(result.status, PlaylistMetadataStatus.notFound);
    });
  });

  group('URL normalization through the service', () {
    test('bare ids and spotify: URIs reach the resolver as playlist URLs',
        () async {
      final seen = <Uri>[];
      final resolver = _RecordingResolver(seen);
      final service = PlaylistMigrationService(
        apiClient: _FakeApiClient(
            const SpotifyPlaylistData(id: 'p', name: 'P', tracks: [])),
        resolver: ProviderTrackResolver([_EmptyResolver()]),
        metadataResolver: resolver,
      );

      await service
          .importSpotifyPlaylist('37i9dQZF1DXcBWIGoYBM5M');
      await service
          .importSpotifyPlaylist('spotify:playlist:37i9dQZF1DXcBWIGoYBM5M');
      await service.importSpotifyPlaylist(_playlistUrl);

      expect(seen, hasLength(3));
      for (final uri in seen) {
        expect(
            SpotifyApiClient.parsePlaylistId(uri.toString()),
            '37i9dQZF1DXcBWIGoYBM5M');
      }
    });

    test('invalid input still fails with a useful message', () async {
      final service = PlaylistMigrationService(
        apiClient: _FakeApiClient(
            const SpotifyPlaylistData(id: 'p', name: 'P', tracks: [])),
        resolver: ProviderTrackResolver([_EmptyResolver()]),
        metadataResolver: _RecordingResolver([]),
      );
      await expectLater(
        service.importSpotifyPlaylist('https://open.spotify.com/track/abc'),
        throwsA(isA<SpotifyApiException>()),
      );
    });
  });
}

class _EmptyResolver implements TrackResolver {
  @override
  MusicProvider get provider => MusicProvider.youtubeMusic;

  @override
  Future<List<MediaItem>> searchSongs(String query, {int limit = 10}) async =>
      const [];
}

class _RecordingResolver extends PlaylistMetadataResolver {
  final List<Uri> seen;
  _RecordingResolver(this.seen) : super(const []);

  @override
  Future<PlaylistMetadataResolution> resolve(Uri url) async {
    seen.add(url);
    return const PlaylistMetadataResolution(
      status: PlaylistMetadataStatus.success,
      playlistId: '37i9dQZF1DXcBWIGoYBM5M',
      name: 'P',
      tracks: [],
    );
  }
}
