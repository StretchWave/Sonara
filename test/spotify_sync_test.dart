import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:sonara/models/playlist.dart';
import 'package:sonara/services/metadata/musicbrainz_client.dart';
import 'package:sonara/services/metadata/playlist_metadata_provider.dart';
import 'package:sonara/services/metadata/playlist_metadata_resolver.dart';
import 'package:sonara/services/spotify/playlist_migration_item.dart';
import 'package:sonara/services/spotify/playlist_migration_service.dart';
import 'package:sonara/services/spotify/provider_track_resolver.dart';
import 'package:sonara/services/spotify/spotify_api_client.dart';
import 'package:sonara/services/spotify/spotify_source_track.dart';
import 'package:sonara/services/spotify/track_matcher.dart';

class FakeTrackResolver implements TrackResolver {
  final Map<String, List<MediaItem>> results;

  FakeTrackResolver({Map<String, List<MediaItem>>? results})
      : results = results ?? {};

  @override
  MusicProvider get provider => MusicProvider.youtubeMusic;

  @override
  Future<List<MediaItem>> searchSongs(String query, {int limit = 10}) async {
    if (results.containsKey(query)) return results[query]!;
    for (final entry in results.entries) {
      if (query.contains(entry.key)) return entry.value;
    }
    return const [];
  }
}

class FakeSpotifyApiClient extends SpotifyApiClient {
  SpotifyPlaylistData data;
  FakeSpotifyApiClient(this.data);

  @override
  bool get isConfigured => true;

  @override
  Future<SpotifyPlaylistData> fetchPlaylist(String playlistId) async => data;
}

class FakeMetadataResolver extends PlaylistMetadataResolver {
  final SpotifyPlaylistData data;
  FakeMetadataResolver(this.data) : super(const []);

  @override
  Future<PlaylistMetadataResolution> resolve(Uri uri) async {
    return PlaylistMetadataResolution(
      status: PlaylistMetadataStatus.success,
      name: data.name,
      tracks: data.tracks,
      tracksSource: 'fake',
    );
  }
}

class FakeMusicBrainzClient extends MusicBrainzClient {
  @override
  Future<MusicBrainzRecording?> findRecording({
    required String title,
    required String artist,
    String? album,
    int? durationMs,
  }) async =>
      null;
}

MediaItem track(String id, String title, String artist, int seconds,
        {Map<String, dynamic>? extras}) =>
    MediaItem(
      id: id,
      title: title,
      artist: artist,
      duration: Duration(seconds: seconds),
      artUri: Uri.parse('https://example.com/$id.jpg'),
      extras: extras ?? const {},
    );

SpotifySourceTrack src(String id, String title,
        {List<String> artists = const ['Artist 1'], int durationMs = 180000}) =>
    SpotifySourceTrack(
      spotifyId: id,
      title: title,
      artists: artists,
      durationMs: durationMs,
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('spotify_sync_test');
    Hive.init(tempDir.path);
    await Hive.openBox('AppPrefs');
    await Hive.openBox('LIBFAV');
    await Hive.openBox('LibraryPlaylists');
    await Hive.openBox('SpotifyMigrations');
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  group('Playlist Model Spotify Extensions', () {
    test('serializes and deserializes spotifyPlaylistId and lastSpotifySyncedAt',
        () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final playlist = Playlist(
        title: 'My Spotify Hits',
        playlistId: 'LIB123',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        spotifyPlaylistId: 'spotify_pl_999',
        lastSpotifySyncedAt: now,
      );

      expect(playlist.isSpotifyConnected, isTrue);

      final json = playlist.toJson();
      expect(json['spotifyPlaylistId'], 'spotify_pl_999');
      expect(json['lastSpotifySyncedAt'], now);

      final restored = Playlist.fromJson(json);
      expect(restored.spotifyPlaylistId, 'spotify_pl_999');
      expect(restored.lastSpotifySyncedAt, now);
      expect(restored.isSpotifyConnected, isTrue);
    });

    test('isSpotifyConnected is false when id is null or empty', () {
      final p1 = Playlist(
        title: 'Regular Playlist',
        playlistId: 'LIB1',
        thumbnailUrl: '',
      );
      expect(p1.isSpotifyConnected, isFalse);

      final p2 = Playlist(
        title: 'Empty ID Playlist',
        playlistId: 'LIB2',
        thumbnailUrl: '',
        spotifyPlaylistId: '',
      );
      expect(p2.isSpotifyConnected, isFalse);
    });

    test('copyWith updates or preserves spotify fields', () {
      final p = Playlist(
        title: 'Original',
        playlistId: 'LIB1',
        thumbnailUrl: '',
        spotifyPlaylistId: 'sp1',
        lastSpotifySyncedAt: 1000,
      );

      final copied = p.copyWith(lastSpotifySyncedAt: 2000);
      expect(copied.spotifyPlaylistId, 'sp1');
      expect(copied.lastSpotifySyncedAt, 2000);

      final disconnected = p.copyWith(spotifyPlaylistId: '');
      expect(disconnected.spotifyPlaylistId, '');
    });
  });

  group('PlaylistMigrationService.createPlaylist with Spotify connection', () {
    test('stores spotifyPlaylistId and lastSpotifySyncedAt in Hive', () async {
      final service = PlaylistMigrationService(
        apiClient: FakeSpotifyApiClient(
          const SpotifyPlaylistData(id: 'sp1', name: 'SP', tracks: []),
        ),
        resolver: ProviderTrackResolver([FakeTrackResolver()]),
      );

      final items = [
        PlaylistMigrationItem(
          sourceTrack: src('s1', 'Track 1'),
          matchedTrack: track('yt1', 'Track 1', 'Artist 1', 180),
        ),
      ];

      final result = await service.createPlaylist(
        'Connected Playlist',
        items,
        spotifyPlaylistId: 'spotify_playlist_123',
      );

      expect(result.added, 1);

      final metaBox = await Hive.openBox('LibraryPlaylists');
      expect(metaBox.values.length, 1);
      final savedJson = Map<String, dynamic>.from(metaBox.values.first as Map);
      expect(savedJson['title'], 'Connected Playlist');
      expect(savedJson['spotifyPlaylistId'], 'spotify_playlist_123');
      expect(savedJson['lastSpotifySyncedAt'], isNotNull);
      await metaBox.close();
    });
  });

  group('PlaylistMigrationService.syncFromSpotify', () {
    const validSpotifyId = '37i9dQZF1DXcBWIGoYBM5M';
    const unseenSpotifyId = '2222222222222222222222';

    test('returns up to date when no new tracks exist on Spotify', () async {
      final fakeApi = FakeSpotifyApiClient(
        SpotifyPlaylistData(
          id: validSpotifyId,
          name: 'Pop Hits',
          tracks: [src('s1', 'Song 1')],
        ),
      );
      final service = PlaylistMigrationService(
        apiClient: fakeApi,
        resolver: ProviderTrackResolver([FakeTrackResolver()]),
        metadataResolver: FakeMetadataResolver(fakeApi.data),
        musicBrainz: FakeMusicBrainzClient(),
      );

      // Pre-populate migration record as having already synced 's1'
      await service.completeMigration(
        spotifyPlaylistId: validSpotifyId,
        spotifyPlaylistName: 'Pop Hits',
        items: [
          PlaylistMigrationItem(
            sourceTrack: src('s1', 'Song 1'),
            matchedTrack: track('yt1', 'Song 1', 'Artist 1', 180),
            status: MigrationStatus.matched,
          ),
        ],
      );

      final syncResult = await service.syncFromSpotify(
        spotifyPlaylistId: validSpotifyId,
        localPlaylistId: 'local_1',
      );

      expect(syncResult.isUpToDate, isTrue);
      expect(syncResult.added, 0);
      expect(syncResult.alreadyUpToDate, 1);
    });

    test('detects new tracks, resolves them, and appends to local playlist',
        () async {
      final fakeApi = FakeSpotifyApiClient(
        SpotifyPlaylistData(
          id: validSpotifyId,
          name: 'Pop Hits',
          tracks: [
            src('s1', 'Song 1'),
            src('s2', 'Song 2'), // newly added song
          ],
        ),
      );

      final fakeResolver = FakeTrackResolver(
        results: {
          'Song 2': [track('yt2', 'Song 2', 'Artist 1', 180)],
        },
      );

      final service = PlaylistMigrationService(
        apiClient: fakeApi,
        resolver: ProviderTrackResolver([fakeResolver]),
        metadataResolver: FakeMetadataResolver(fakeApi.data),
        musicBrainz: FakeMusicBrainzClient(),
      );

      // Pre-populate migration record with only s1
      await service.completeMigration(
        spotifyPlaylistId: validSpotifyId,
        spotifyPlaylistName: 'Pop Hits',
        items: [
          PlaylistMigrationItem(
            sourceTrack: src('s1', 'Song 1'),
            matchedTrack: track('yt1', 'Song 1', 'Artist 1', 180),
            status: MigrationStatus.matched,
          ),
        ],
      );

      // Pre-populate local playlist with song 1
      final localBox = await Hive.openBox('local_1');
      await localBox.put(0, {'id': 'yt1', 'title': 'Song 1'});
      await localBox.close();

      // Perform sync
      final syncResult = await service.syncFromSpotify(
        spotifyPlaylistId: validSpotifyId,
        localPlaylistId: 'local_1',
      );

      expect(syncResult.error, isNull);
      expect(syncResult.added, 1);

      // Verify local playlist now has both songs
      final updatedBox = await Hive.openBox('local_1');
      expect(updatedBox.length, 2);
      expect(updatedBox.get(1)['videoId'], 'yt2');
      await updatedBox.close();

      // Verify stored migration now has both items
      final stored = await service.loadMigration(validSpotifyId);
      expect(stored, isNotNull);
      final storedItems = stored!['items'] as List;
      expect(storedItems.length, 2);
    });

    test('returns error when no stored migration exists', () async {
      final fakeApi = FakeSpotifyApiClient(
        SpotifyPlaylistData(
          id: unseenSpotifyId,
          name: 'Unknown',
          tracks: [src('s1', 'Song 1')],
        ),
      );
      final service = PlaylistMigrationService(
        apiClient: fakeApi,
        resolver: ProviderTrackResolver([FakeTrackResolver()]),
        metadataResolver: FakeMetadataResolver(fakeApi.data),
        musicBrainz: FakeMusicBrainzClient(),
      );

      final syncResult = await service.syncFromSpotify(
        spotifyPlaylistId: unseenSpotifyId,
        localPlaylistId: 'local_1',
      );

      expect(syncResult.error, isNotNull);
      expect(syncResult.error, contains('No previous migration record'));
    });
  });
}
