import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/spotify/playlist_migration_item.dart';
import 'package:harmonymusic/services/spotify/playlist_migration_service.dart';
import 'package:harmonymusic/services/spotify/provider_track_resolver.dart';
import 'package:harmonymusic/services/spotify/spotify_api_client.dart';
import 'package:harmonymusic/services/spotify/spotify_source_track.dart';
import 'package:harmonymusic/services/spotify/track_matcher.dart';
import 'package:hive/hive.dart';

/// Fake resolver that maps search queries to fixed results and can be told
/// to throw or to record concurrency.
class FakeTrackResolver implements TrackResolver {
  final Map<String, List<MediaItem>> results;
  final Set<String> failingTitles;
  final Duration delay;
  int maxInFlight = 0;
  int _inFlight = 0;

  FakeTrackResolver({
    Map<String, List<MediaItem>>? results,
    this.failingTitles = const {},
    this.delay = Duration.zero,
  }) : results = results ?? {};

  @override
  MusicProvider get provider => MusicProvider.youtubeMusic;

  @override
  Future<List<MediaItem>> searchSongs(String query, {int limit = 10}) async {
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    _inFlight--;
    if (failingTitles.any((t) => query.toLowerCase().contains(t.toLowerCase()))) {
      return const [];
    }
    return results[query] ?? const [];
  }
}

class FakeSpotifyApiClient extends SpotifyApiClient {
  final SpotifyPlaylistData data;
  FakeSpotifyApiClient(this.data);

  @override
  bool get isConfigured => true;

  @override
  Future<SpotifyPlaylistData> fetchPlaylist(String playlistId) async => data;
}

MediaItem track(String id, String title, String artist, int seconds,
        {String? album, Map<String, dynamic>? extras}) =>
    MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: Duration(seconds: seconds),
      artUri: Uri.parse('https://example.com/$id.jpg'),
      extras: extras ?? const {},
    );

SpotifySourceTrack src(String id, String title,
        {List<String> artists = const ['The Weeknd'],
        String? album = 'After Hours',
        int durationMs = 200000,
        String? isrc}) =>
    SpotifySourceTrack(
      spotifyId: id,
      title: title,
      artists: artists,
      album: album,
      durationMs: durationMs,
      isrc: isrc,
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('migration_test');
    Hive.init(tempDir.path);
    await Hive.openBox('AppPrefs');
    await Hive.openBox('LIBFAV');
    await Hive.openBox('LibraryPlaylists');
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  group('resolveAll', () {
    test('matches all tracks with high confidence', () async {
      final resolver = FakeTrackResolver(results: {
        '"Blinding Lights" "The Weeknd"': [track('yt1', 'Blinding Lights', 'The Weeknd', 200)],
        '"Starboy" "The Weeknd"': [track('yt2', 'Starboy', 'The Weeknd', 200)],
      });
      final service = PlaylistMigrationService(
          apiClient: FakeSpotifyApiClient(
              const SpotifyPlaylistData(id: 'p1', name: 'P', tracks: [])),
          resolver: ProviderTrackResolver([resolver]));

      final items = [
        PlaylistMigrationItem(sourceTrack: src('s1', 'Blinding Lights')),
        PlaylistMigrationItem(sourceTrack: src('s2', 'Starboy')),
      ];
      final progress = <int>[];
      await service.resolveAll(items, onProgress: (c, t) => progress.add(c));

      expect(items[0].status, MigrationStatus.matched);
      expect(items[0].matchedTrack?.id, 'yt1');
      expect(items[0].confidence, MatchConfidence.high);
      expect(items[1].status, MigrationStatus.matched);
      expect(progress, [1, 2]);
    });

    test('stops searching after a high-confidence match (early exit)', () async {
      var searches = 0;
      final resolver = _CountingResolver((q) {
        searches++;
        return [track('yt1', 'Blinding Lights', 'The Weeknd', 200)];
      });
      final service = PlaylistMigrationService(
          apiClient: FakeSpotifyApiClient(
              const SpotifyPlaylistData(id: 'p1', name: 'P', tracks: [])),
          resolver: ProviderTrackResolver([resolver]));
      final items = [
        PlaylistMigrationItem(sourceTrack: src('s1', 'Blinding Lights')),
      ];
      await service.resolveAll(items);
      expect(searches, 1, reason: 'one strategy should be enough');
    });

    test('marks tracks as unmatched when nothing fits', () async {
      final service = PlaylistMigrationService(
          apiClient: FakeSpotifyApiClient(
              const SpotifyPlaylistData(id: 'p1', name: 'P', tracks: [])),
          resolver: ProviderTrackResolver([
            FakeTrackResolver(results: {
              '"Blinding Lights" "The Weeknd"': [
                track('yt9', 'Shape of You', 'Ed Sheeran', 234)
              ],
            })
          ]));
      final items = [
        PlaylistMigrationItem(sourceTrack: src('s1', 'Blinding Lights')),
      ];
      await service.resolveAll(items);
      expect(items[0].status, MigrationStatus.unmatched);
      expect(items[0].hasMatch, isFalse);
      expect(items[0].hasMatch, isFalse);
    });

    test('one failing track does not abort the rest', () async {
      final resolver = FakeTrackResolver(
        results: {
          '"Blinding Lights" "The Weeknd"': [
            track('yt1', 'Blinding Lights', 'The Weeknd', 200)
          ],
          '"Starboy" "The Weeknd"': [track('yt2', 'Starboy', 'The Weeknd', 222)],
        },
        failingTitles: {'Starboy'},
      );
      final service = PlaylistMigrationService(
          apiClient: FakeSpotifyApiClient(
              const SpotifyPlaylistData(id: 'p1', name: 'P', tracks: [])),
          resolver: ProviderTrackResolver([resolver]));
      final items = [
        PlaylistMigrationItem(sourceTrack: src('s1', 'Blinding Lights')),
        PlaylistMigrationItem(sourceTrack: src('s2', 'Starboy')),
        PlaylistMigrationItem(sourceTrack: src('s3', 'After Hours')),
      ];
      await service.resolveAll(items);
      expect(items[0].status, MigrationStatus.matched);
      expect(items[1].status, MigrationStatus.unmatched);
      expect(items[2].status, MigrationStatus.unmatched);
    });

    test('skips tracks without metadata', () async {
      final service = PlaylistMigrationService(
          apiClient: FakeSpotifyApiClient(
              const SpotifyPlaylistData(id: 'p1', name: 'P', tracks: [])),
          resolver: ProviderTrackResolver([FakeTrackResolver()]));
      final items = [
        PlaylistMigrationItem(
            sourceTrack:
                const SpotifySourceTrack(spotifyId: '', title: '', artists: [])),
      ];
      await service.resolveAll(items);
      expect(items[0].status, MigrationStatus.skipped);
    });

    test('bounded concurrency on large playlists', () async {
      final resolver = FakeTrackResolver(
        results: {
          for (var i = 0; i < 12; i++)
            '"Song $i" "Artist"': [track('yt$i', 'Song $i', 'Artist', 200)],
        },
        delay: const Duration(milliseconds: 20),
      );
      final service = PlaylistMigrationService(
          apiClient: FakeSpotifyApiClient(
              const SpotifyPlaylistData(id: 'p1', name: 'P', tracks: [])),
          resolver: ProviderTrackResolver([resolver]));
      final items = [
        for (var i = 0; i < 12; i++)
          PlaylistMigrationItem(
              sourceTrack: src('s$i', 'Song $i',
                  artists: ['Artist'], album: null)),
      ];
      await service.resolveAll(items);
      expect(resolver.maxInFlight, lessThanOrEqualTo(kMaxConcurrentResolutions));
      expect(items.every((e) => e.status == MigrationStatus.matched), isTrue);
    });
  });

  group('migrateToLiked', () {
    test('adds matched tracks and skips duplicates', () async {
      final service = PlaylistMigrationService(
          apiClient: FakeSpotifyApiClient(
              const SpotifyPlaylistData(id: 'p1', name: 'P', tracks: [])),
          resolver: ProviderTrackResolver([FakeTrackResolver()]));
      final box = await Hive.openBox('LIBFAV');
      await box.put('yt2', {'id': 'yt2'});
      await box.close();

      final items = [
        PlaylistMigrationItem(
            sourceTrack: src('s1', 'A'), matchedTrack: track('yt1', 'A', 'X', 180)),
        PlaylistMigrationItem(
            sourceTrack: src('s2', 'B'), matchedTrack: track('yt2', 'B', 'X', 190)),
        PlaylistMigrationItem(sourceTrack: src('s3', 'C')),
      ];
      final result = await service.migrateToLiked(items);
      expect(result.added, 1);
      expect(result.alreadyExists, 1);
      expect(result.failed, 1);

      final favs = await Hive.openBox('LIBFAV');
      expect(favs.containsKey('yt1'), isTrue);
      expect(favs.containsKey('yt2'), isTrue);
      await favs.close();
    });

    test('preserves provider source info in liked entries', () async {
      final service = PlaylistMigrationService(
          apiClient: FakeSpotifyApiClient(
              const SpotifyPlaylistData(id: 'p1', name: 'P', tracks: [])),
          resolver: ProviderTrackResolver([FakeTrackResolver()]));
      final items = [
        PlaylistMigrationItem(
            sourceTrack: src('s1', 'A'),
            matchedTrack: track('yt1', 'A', 'X', 180,
                extras: {'album': {'name': 'Album X', 'id': 'al1'}}),
            matchedProvider: MusicProvider.youtubeMusic),
      ];
      await service.migrateToLiked(items);
      final favs = await Hive.openBox('LIBFAV');
      final json = favs.get('yt1');
      expect(json['album'], {'name': 'Album X', 'id': 'al1'});
      expect(json['videoId'], 'yt1');
      await favs.close();
    });
  });

  group('createPlaylist', () {
    test('creates a local playlist with tracks in source order', () async {
      final service = PlaylistMigrationService(
          apiClient: FakeSpotifyApiClient(
              const SpotifyPlaylistData(id: 'p1', name: 'P', tracks: [])),
          resolver: ProviderTrackResolver([FakeTrackResolver()]));
      final items = [
        PlaylistMigrationItem(
            sourceTrack: src('s1', 'A'), matchedTrack: track('yt1', 'A', 'X', 180)),
        PlaylistMigrationItem(sourceTrack: src('s2', 'B')),
        PlaylistMigrationItem(
            sourceTrack: src('s3', 'C'), matchedTrack: track('yt3', 'C', 'X', 200)),
      ];
      final result = await service.createPlaylist('My Spotify', items);
      expect(result.added, 2);

      final meta = await Hive.openBox('LibraryPlaylists');
      final plist = meta.values.first;
      expect(plist['title'], 'My Spotify');
      final pid = plist['playlistId'] as String;
      await meta.close();

      final songsBox = await Hive.openBox(pid);
      expect(songsBox.length, 2);
      expect(songsBox.get(0)['videoId'], 'yt1');
      expect(songsBox.get(1)['videoId'], 'yt3');
      await songsBox.close();
    });

    test('defaults the name when empty', () async {
      final service = PlaylistMigrationService(
          apiClient: FakeSpotifyApiClient(
              const SpotifyPlaylistData(id: 'p1', name: 'P', tracks: [])),
          resolver: ProviderTrackResolver([FakeTrackResolver()]));
      await service.createPlaylist('   ', [
        PlaylistMigrationItem(
            sourceTrack: src('s1', 'A'), matchedTrack: track('yt1', 'A', 'X', 180)),
      ]);
      final meta = await Hive.openBox('LibraryPlaylists');
      expect(meta.values.first['title'], 'Spotify Import');
      await meta.close();
    });
  });

  group('addToExistingPlaylist', () {
    test('appends new tracks and avoids duplicates', () async {
      final service = PlaylistMigrationService(
          apiClient: FakeSpotifyApiClient(
              const SpotifyPlaylistData(id: 'p1', name: 'P', tracks: [])),
          resolver: ProviderTrackResolver([FakeTrackResolver()]));
      final existing = await Hive.openBox('existingPl');
      await existing.put(0, {'id': 'yt1'});
      await existing.close();

      final items = [
        PlaylistMigrationItem(
            sourceTrack: src('s1', 'A'), matchedTrack: track('yt1', 'A', 'X', 180)),
        PlaylistMigrationItem(
            sourceTrack: src('s2', 'B'), matchedTrack: track('yt2', 'B', 'X', 190)),
      ];
      final result = await service.addToExistingPlaylist(
          Playlist(
              title: 'Existing', playlistId: 'existingPl', thumbnailUrl: ''),
          items);
      expect(result.added, 1);
      expect(result.alreadyExists, 1);

      final box = await Hive.openBox('existingPl');
      expect(box.length, 2);
      expect(box.get(1)['videoId'], 'yt2');
      await box.close();
    });
  });

  group('persistMigration', () {
    test('stores source + match metadata for rematching', () async {
      final service = PlaylistMigrationService(
          apiClient: FakeSpotifyApiClient(
              const SpotifyPlaylistData(id: 'p1', name: 'P', tracks: [])),
          resolver: ProviderTrackResolver([FakeTrackResolver()]));
      final items = [
        PlaylistMigrationItem(
            sourceTrack: src('s1', 'A', isrc: 'US123'),
            matchedTrack: track('yt1', 'A', 'X', 180),
            matchedProvider: MusicProvider.youtubeMusic,
            matchScore: 0.98,
            confidence: MatchConfidence.high,
            status: MigrationStatus.matched),
      ];
      await service.persistProgress(
          spotifyPlaylistId: 'p1',
          spotifyPlaylistName: 'My Playlist',
          items: items);

      final stored = await service.loadMigration('p1');
      expect(stored, isNotNull);
      expect(stored!['name'], 'My Playlist');
      final storedItems = stored['items'] as List;
      final first = storedItems.first as Map;
      expect(first['source']['isrc'], 'US123');
      expect(first['source']['spotifyId'], 's1');
      expect(first['matchedTrack']['id'], 'yt1');
      expect(first['matchScore'], 0.98);
      expect(first['confidence'], 'high');
    });
  });
}

/// Resolver that counts searches and returns a fixed list.
class _CountingResolver implements TrackResolver {
  final List<MediaItem> Function(String query) handler;
  _CountingResolver(this.handler);

  @override
  MusicProvider get provider => MusicProvider.youtubeMusic;

  @override
  Future<List<MediaItem>> searchSongs(String query, {int limit = 10}) async =>
      handler(query);
}
