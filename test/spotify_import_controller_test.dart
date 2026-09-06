import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:sonara/services/spotify/playlist_migration_item.dart';
import 'package:sonara/services/spotify/spotify_source_track.dart';
import 'package:sonara/services/spotify/track_matcher.dart';
import 'package:sonara/ui/screens/Spotify/spotify_import_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SpotifyImportController controller;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('spotify_import_test');
    Hive.init(tempDir.path);
    await Hive.openBox('AppPrefs');
    await Hive.openBox('SpotifyMigrations');

    // Mock WakelockPlus platform channel
    const channel = MethodChannel('wakelock_plus');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    Get.reset();
    controller = SpotifyImportController();
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    Get.reset();
  });

  group('SpotifyImportController - Saved Migrations', () {
    test('loadSavedMigrations reads migrations from Hive and sorts descending',
        () async {
      final box = Hive.box('SpotifyMigrations');
      await box.put('playlist_1', {
        'name': 'Old Playlist',
        'status': 'completed',
        'migratedAt': 1000,
        'artworkUrl': 'https://example.com/art1.jpg',
        'items': [
          {'status': 'matched'},
          {'status': 'matched'},
        ],
      });
      await box.put('playlist_2', {
        'name': 'New Playlist',
        'status': 'in_progress',
        'migratedAt': 2000,
        'artworkUrl': 'https://example.com/art2.jpg',
        'items': [
          {'status': 'matched'},
          {'status': 'unmatched'},
          {'status': 'pending'},
        ],
      });

      await controller.loadSavedMigrations();

      expect(controller.savedMigrations, hasLength(2));
      // Most recent first
      expect(controller.savedMigrations[0]['id'], 'playlist_2');
      expect(controller.savedMigrations[0]['name'], 'New Playlist');
      expect(controller.savedMigrations[0]['totalTracks'], 3);
      expect(controller.savedMigrations[0]['matchedTracks'], 1);
      expect(controller.savedMigrations[0]['status'], 'in_progress');

      expect(controller.savedMigrations[1]['id'], 'playlist_1');
      expect(controller.savedMigrations[1]['name'], 'Old Playlist');
      expect(controller.savedMigrations[1]['totalTracks'], 2);
      expect(controller.savedMigrations[1]['matchedTracks'], 2);
      expect(controller.savedMigrations[1]['status'], 'completed');
    });

    test('openSavedMigration restores state and transitions to review phase',
        () async {
      final box = Hive.box('SpotifyMigrations');
      await box.put('playlist_abc', {
        'name': 'Roadtrip Hits',
        'status': 'completed',
        'migratedAt': 123456,
        'artworkUrl': 'https://example.com/roadtrip.jpg',
        'items': [
          {
            'sourceTrack': {
              'spotifyId': 'track_1',
              'title': 'Song 1',
              'artists': ['Artist 1'],
            },
            'status': 'matched',
            'matchedTrack': {
              'id': 'yt_1',
              'title': 'Song 1',
              'artist': 'Artist 1',
            },
          },
        ],
      });

      await controller.openSavedMigration('playlist_abc');

      expect(controller.playlistId.value, 'playlist_abc');
      expect(controller.playlistName.value, 'Roadtrip Hits');
      expect(controller.playlistArtwork.value, 'https://example.com/roadtrip.jpg');
      expect(controller.items, hasLength(1));
      expect(controller.totalTracks.value, 1);
      expect(controller.completedTracks.value, 1);
      expect(controller.phase.value, MigrationPhase.review);
    });

    test('deleteSavedMigration removes record from Hive and updates list',
        () async {
      final box = Hive.box('SpotifyMigrations');
      await box.put('playlist_to_delete', {
        'name': 'To Delete',
        'status': 'completed',
        'migratedAt': 500,
        'items': [],
      });

      await controller.loadSavedMigrations();
      expect(controller.savedMigrations, hasLength(1));

      await controller.deleteSavedMigration('playlist_to_delete');
      expect(controller.savedMigrations, isEmpty);
      expect(box.containsKey('playlist_to_delete'), isFalse);
    });
  });

  group('SpotifyImportController - Sorting', () {
    test('filteredItems and eligibleItems sort by playlist order, title, artist, duration', () {
      final item1 = PlaylistMigrationItem(
        sourceTrack: const SpotifySourceTrack(
          spotifyId: '1',
          title: 'Zebra',
          artists: ['Bob'],
          trackNumber: 2,
          durationMs: 300000,
        ),
      )
        ..status = MigrationStatus.matched
        ..confidence = MatchConfidence.high
        ..matchedTrack = const MediaItem(
          id: 'yt_1',
          title: 'Zebra',
          artist: 'Bob',
          duration: Duration(milliseconds: 300000),
        );

      final item2 = PlaylistMigrationItem(
        sourceTrack: const SpotifySourceTrack(
          spotifyId: '2',
          title: 'Apple',
          artists: ['Charlie'],
          trackNumber: 1,
          durationMs: 120000,
        ),
      )
        ..status = MigrationStatus.matched
        ..confidence = MatchConfidence.high
        ..matchedTrack = const MediaItem(
          id: 'yt_2',
          title: 'Apple',
          artist: 'Charlie',
          duration: Duration(milliseconds: 120000),
        );

      final item3 = PlaylistMigrationItem(
        sourceTrack: const SpotifySourceTrack(
          spotifyId: '3',
          title: 'Mango',
          artists: ['Alice'],
          trackNumber: 3,
          durationMs: 200000,
        ),
      )
        ..status = MigrationStatus.matched
        ..confidence = MatchConfidence.high
        ..matchedTrack = const MediaItem(
          id: 'yt_3',
          title: 'Mango',
          artist: 'Alice',
          duration: Duration(milliseconds: 200000),
        );

      controller.items.assignAll([item1, item2, item3]);

      // 1. Default: playlist order ascending (trackNumber: 1, 2, 3)
      expect(controller.sortType.value, ImportSortType.playlistOrder);
      expect(controller.sortAscending.value, isTrue);
      expect(controller.filteredItems.map((e) => e.sourceTrack.spotifyId).toList(),
          ['2', '1', '3']);
      expect(controller.eligibleItems.map((e) => e.sourceTrack.spotifyId).toList(),
          ['2', '1', '3']);

      // 2. Sort by Title ascending (Apple, Mango, Zebra)
      controller.setSort(ImportSortType.title, ascending: true);
      expect(controller.filteredItems.map((e) => e.sourceTrack.title).toList(),
          ['Apple', 'Mango', 'Zebra']);
      expect(controller.eligibleItems.map((e) => e.sourceTrack.title).toList(),
          ['Apple', 'Mango', 'Zebra']);

      // 3. Toggle to Title descending (Zebra, Mango, Apple)
      controller.setSort(ImportSortType.title);
      expect(controller.sortAscending.value, isFalse);
      expect(controller.filteredItems.map((e) => e.sourceTrack.title).toList(),
          ['Zebra', 'Mango', 'Apple']);

      // 4. Sort by Artist ascending (Alice, Bob, Charlie)
      controller.setSort(ImportSortType.artist, ascending: true);
      expect(controller.filteredItems.map((e) => e.sourceTrack.artists.first).toList(),
          ['Alice', 'Bob', 'Charlie']);

      // 5. Sort by Duration ascending (120k, 200k, 300k -> 2, 3, 1)
      controller.setSort(ImportSortType.duration, ascending: true);
      expect(controller.filteredItems.map((e) => e.sourceTrack.spotifyId).toList(),
          ['2', '3', '1']);
    });
  });
}

