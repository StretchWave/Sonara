import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:sonara/models/media_Item_builder.dart';
import 'package:sonara/models/playlist.dart';
import 'package:sonara/services/supabase/playlist_sync_service.dart';
import 'package:sonara/services/supabase/supabase_service.dart';

void main() {
  setUp(() {
    Get.reset();
    Get.put(SupabaseService());
  });

  group('Supabase Playlist Cloud Sync Architecture Tests', () {
    test('System and offline playlists are never marked as syncable', () {
      final syncService = PlaylistSyncService();

      // System default playlists
      final recent = Playlist(
        title: "Recently Played",
        playlistId: "LIBRP",
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false,
      );
      final favorites = Playlist(
        title: "Favorites",
        playlistId: "LIBFAV",
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false,
      );
      final cache = Playlist(
        title: "Cached",
        playlistId: "SongsCache",
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false,
      );
      final downloads = Playlist(
        title: "Downloads",
        playlistId: "SongDownloads",
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false,
      );
      final topPlayed = Playlist(
        title: "Top Played",
        playlistId: "LIBTP",
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false,
      );

      // Piped playlist
      final piped = Playlist(
        title: "Piped List",
        playlistId: "piped123",
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isPipedPlaylist: true,
      );

      // User custom local playlist
      final customLocal = Playlist(
        title: "My Roadtrip Hits",
        playlistId: "LIB171234567890",
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
        isCloudPlaylist: false,
        isPipedPlaylist: false,
      );

      expect(syncService.isSyncablePlaylist(recent), isFalse);
      expect(syncService.isSyncablePlaylist(favorites), isTrue);
      expect(syncService.isSyncablePlaylist(cache), isFalse);
      expect(syncService.isSyncablePlaylist(downloads), isFalse);
      expect(syncService.isSyncablePlaylist(topPlayed), isFalse);
      expect(syncService.isSyncablePlaylist(piped), isFalse);
      expect(syncService.isSyncablePlaylist(customLocal), isTrue);
    });

    test('MediaItem serialization preserves 100% of track metadata for cloud storage', () {
      final track = MediaItem(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        album: 'Whenever You Need Somebody',
        duration: const Duration(seconds: 213),
        artUri: Uri.parse('https://example.com/rick.jpg'),
        extras: {
          'url': 'https://youtube.com/watch?v=dQw4w9WgXcQ',
          'length': '3:33',
          'album': {'id': 'ALB123', 'name': 'Whenever You Need Somebody'},
          'artists': [{'name': 'Rick Astley'}],
          'date': '1987',
          'trackDetails': 'Official Music Video',
          'year': '1987',
          'videoType': 'video',
        },
      );

      final jsonMap = MediaItemBuilder.toJson(track);
      expect(jsonMap['videoId'], equals('dQw4w9WgXcQ'));
      expect(jsonMap['title'], equals('Never Gonna Give You Up'));
      expect(jsonMap['duration'], equals(213));
      expect(jsonMap['length'], equals('3:33'));
      expect(jsonMap['videoType'], equals('video'));

      // Reconstruct track locally
      final reconstructed = MediaItemBuilder.fromJson(jsonMap);
      expect(reconstructed.id, equals(track.id));
      expect(reconstructed.title, equals(track.title));
      expect(reconstructed.artist, equals(track.artist));
      expect(reconstructed.album, equals(track.album));
      expect(reconstructed.duration?.inSeconds, equals(213));
      expect(reconstructed.extras?['videoType'], equals('video'));
    });

    test('Playlist JSON serialization preserves custom attributes', () {
      final plst = Playlist(
        title: 'Cyberpunk Vibes',
        playlistId: 'LIB99887766',
        description: 'Synthwave & Electronic',
        thumbnailUrl: 'https://example.com/cover.png',
        isPipedPlaylist: false,
        isCloudPlaylist: false,
      );

      final json = plst.toJson();
      expect(json['title'], equals('Cyberpunk Vibes'));
      expect(json['playlistId'], equals('LIB99887766'));
      expect(json['description'], equals('Synthwave & Electronic'));
      expect(json['isCloudPlaylist'], isFalse);
      expect(json['isPipedPlaylist'], isFalse);

      final restored = Playlist.fromJson(json);
      expect(restored.title, equals('Cyberpunk Vibes'));
      expect(restored.playlistId, equals('LIB99887766'));
      expect(restored.description, equals('Synthwave & Electronic'));
      expect(restored.isCloudPlaylist, isFalse);
    });
  });
}
