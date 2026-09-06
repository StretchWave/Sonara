import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart' show Key;
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/media_Item_builder.dart';
import '../../models/playlist.dart';
import '../../ui/screens/Library/library_controller.dart';
import '../../ui/screens/Playlist/playlist_screen_controller.dart';
import '../../utils/helper.dart';
import 'supabase_service.dart';

/// Service managing optional background cloud synchronization of playlists
/// with Supabase.
///
/// Synchronization is conservative and offline-first:
/// 1. Local Hive storage is always modified first.
/// 2. Cloud operations execute in the background if the user is authenticated.
/// 3. Offline errors are caught and logged silently without disrupting the user.
/// 4. Conflicts are resolved using updated_at timestamps (newest wins).
/// 5. Logging out never deletes local playlists.
class PlaylistSyncService extends GetxService {
  final SupabaseService _supabaseService = Get.find<SupabaseService>();

  final isSyncing = false.obs;
  final syncError = ''.obs;
  final lastSyncedAt = Rxn<DateTime>();

  // Set of built-in system playlist IDs that should never sync to cloud
  // (LIBFAV / Liked Songs is synced)
  static const Set<String> _systemPlaylistIds = {
    "LIBRP",
    "SongsCache",
    "SongDownloads",
    "LIBTP",
  };

  @override
  void onInit() {
    super.onInit();
    // When user logs in, trigger an initial full synchronization
    ever(_supabaseService.isLoggedIn, (bool loggedIn) {
      if (loggedIn) {
        syncAll();
      }
    });

    // Load last synced timestamp from AppPrefs if available
    try {
      final prefs = Hive.box("AppPrefs");
      final savedSync = prefs.get("supabaseLastSyncedAt");
      if (savedSync != null && savedSync is String) {
        lastSyncedAt.value = DateTime.tryParse(savedSync);
      }
    } catch (_) {}
  }

  bool _canSync() {
    return _supabaseService.isLoggedIn.value &&
        _supabaseService.client != null &&
        _supabaseService.userId.value.isNotEmpty;
  }

  bool isSyncablePlaylist(Playlist playlist) {
    if (_systemPlaylistIds.contains(playlist.playlistId)) return false;
    if (playlist.isPipedPlaylist) return false;
    return true;
  }

  /// Performs a full bidirectional sync between local Hive storage and Supabase.
  Future<void> syncAll() async {
    if (!_canSync() || isSyncing.value) return;

    isSyncing.value = true;
    syncError.value = '';

    try {
      final client = _supabaseService.client!;
      final userId = _supabaseService.userId.value;

      // 1. Fetch remote playlists
      final remoteRows = await client
          .from('playlists')
          .select()
          .eq('user_id', userId);

      final Map<String, Map<String, dynamic>> remoteMap = {};
      for (final row in remoteRows) {
        remoteMap[row['id'].toString()] = Map<String, dynamic>.from(row);
      }

      // 2. Open local playlists & sync metadata
      final libBox = await Hive.openBox("LibraryPlaylists");
      final syncMetaBox = await Hive.openBox("PlaylistSyncMetadata");

      final Map<String, Playlist> localMap = {};
      for (final key in libBox.keys) {
        try {
          final data = libBox.get(key);
          if (data != null) {
            final playlist = Playlist.fromJson(data);
            if (isSyncablePlaylist(playlist)) {
              localMap[playlist.playlistId] = playlist;
            }
          }
        } catch (e) {
          printERROR("Error reading local playlist $key: $e");
        }
      }

      // 3. Process remote playlists: download missing or resolve conflicts
      for (final entry in remoteMap.entries) {
        final remoteId = entry.key;
        final remoteData = entry.value;
        final remoteUpdatedAt = DateTime.tryParse(
                remoteData['updated_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);

        if (!localMap.containsKey(remoteId)) {
          // Playlist exists in cloud but not locally -> Download it
          await _downloadRemotePlaylist(client, remoteId, remoteData, libBox);
          await syncMetaBox.put(remoteId, {
            'updated_at': remoteUpdatedAt.toIso8601String(),
            'synced_at': DateTime.now().toIso8601String(),
          });
        } else {
          // Exists both locally and in cloud -> Check timestamps
          final meta = syncMetaBox.get(remoteId);
          final localUpdatedAt = meta != null && meta['updated_at'] != null
              ? DateTime.tryParse(meta['updated_at'].toString()) ??
                  DateTime.fromMillisecondsSinceEpoch(0)
              : DateTime.fromMillisecondsSinceEpoch(0);

          if (remoteUpdatedAt.isAfter(localUpdatedAt)) {
            // Cloud is newer -> Update local copy
            await _downloadRemotePlaylist(client, remoteId, remoteData, libBox);
            await syncMetaBox.put(remoteId, {
              'updated_at': remoteUpdatedAt.toIso8601String(),
              'synced_at': DateTime.now().toIso8601String(),
            });
          } else if (localUpdatedAt.isAfter(remoteUpdatedAt)) {
            // Local is newer -> Upload to cloud
            final localPlaylist = localMap[remoteId]!;
            final songsBox = await Hive.openBox(remoteId);
            final tracks = songsBox.values
                .map<MediaItem?>((item) => MediaItemBuilder.fromJson(item))
                .whereType<MediaItem>()
                .toList();
            await songsBox.close();

            await _uploadPlaylistToCloud(client, userId, localPlaylist, tracks);
            await syncMetaBox.put(remoteId, {
              'updated_at': localUpdatedAt.toIso8601String(),
              'synced_at': DateTime.now().toIso8601String(),
            });
          }
        }
      }

      // 4. Process local-only playlists: upload to cloud
      for (final entry in localMap.entries) {
        final localId = entry.key;
        if (!remoteMap.containsKey(localId)) {
          final localPlaylist = entry.value;
          final songsBox = await Hive.openBox(localId);
          final tracks = songsBox.values
              .map<MediaItem?>((item) => MediaItemBuilder.fromJson(item))
              .whereType<MediaItem>()
              .toList();
          await songsBox.close();

          await _uploadPlaylistToCloud(client, userId, localPlaylist, tracks);
          final nowIso = DateTime.now().toIso8601String();
          await syncMetaBox.put(localId, {
            'updated_at': nowIso,
            'synced_at': nowIso,
          });
        }
      }

      // Sync Favorites (Liked Songs)
      await _syncFavorites(client, userId);

      await libBox.close();
      await syncMetaBox.close();

      // Refresh in-memory UI
      if (Get.isRegistered<LibraryPlaylistsController>()) {
        Get.find<LibraryPlaylistsController>().refreshLib();
      }

      final now = DateTime.now();
      lastSyncedAt.value = now;
      syncError.value = '';
      try {
        final prefs = Hive.box("AppPrefs");
        prefs.put("supabaseLastSyncedAt", now.toIso8601String());
      } catch (_) {}
    } catch (e) {
      printERROR("PlaylistSyncService.syncAll error: $e");
      final errStr = e.toString();
      if (errStr.contains('PGRST205') ||
          errStr.toLowerCase().contains("could not find the table")) {
        syncError.value =
            "Tables not created yet. Run supabase/schema.sql in the Supabase SQL Editor.";
      } else {
        syncError.value = errStr;
      }
    } finally {
      isSyncing.value = false;
    }
  }

  /// Downloads a cloud playlist and its tracks into local Hive boxes.
  Future<void> _downloadRemotePlaylist(
    SupabaseClient client,
    String playlistId,
    Map<String, dynamic> remoteData,
    Box libBox,
  ) async {
    final playlist = Playlist(
      title: remoteData['name'] ?? 'Playlist',
      playlistId: playlistId,
      description: remoteData['description'] ?? 'Cloud Playlist',
      thumbnailUrl: remoteData['cover_url'] ?? Playlist.thumbPlaceholderUrl,
      isCloudPlaylist: false,
      isPipedPlaylist: false,
    );
    await libBox.put(playlistId, playlist.toJson());

    // Fetch tracks
    final trackRows = await client
        .from('playlist_tracks')
        .select()
        .eq('playlist_id', playlistId)
        .order('position', ascending: true);

    final songsBox = await Hive.openBox(playlistId);
    await songsBox.clear();
    for (int i = 0; i < trackRows.length; i++) {
      final trackData = trackRows[i]['track_data'];
      if (trackData != null) {
        await songsBox.put(i, trackData);
      }
    }
    await songsBox.close();
  }

  /// Uploads or replaces a playlist and all its tracks in Supabase.
  Future<void> _uploadPlaylistToCloud(
    SupabaseClient client,
    String userId,
    Playlist playlist,
    List<MediaItem> tracks,
  ) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();

    // Upsert playlist metadata
    await client.from('playlists').upsert({
      'id': playlist.playlistId,
      'user_id': userId,
      'name': playlist.title,
      'description': playlist.description ?? '',
      'cover_url': playlist.thumbnailUrl,
      'updated_at': nowIso,
    });

    // Delete existing tracks and insert new tracks in bulk
    await client
        .from('playlist_tracks')
        .delete()
        .eq('playlist_id', playlist.playlistId);

    if (tracks.isNotEmpty) {
      final List<Map<String, dynamic>> trackRows = [];
      for (int i = 0; i < tracks.length; i++) {
        final track = tracks[i];
        trackRows.add({
          'id': "${playlist.playlistId}_$i",
          'playlist_id': playlist.playlistId,
          'user_id': userId,
          'track_id': track.id,
          'position': i,
          'track_data': MediaItemBuilder.toJson(track),
          'updated_at': nowIso,
        });
      }
      await client.from('playlist_tracks').insert(trackRows);
    }
  }

  /// Background upload for a newly created playlist
  Future<void> uploadNewPlaylist(
      Playlist playlist, List<MediaItem>? tracks) async {
    if (!_canSync() || !isSyncablePlaylist(playlist)) return;
    try {
      final client = _supabaseService.client!;
      final userId = _supabaseService.userId.value;
      await _uploadPlaylistToCloud(
          client, userId, playlist, tracks ?? <MediaItem>[]);
      _recordLocalSyncTime(playlist.playlistId);
    } catch (e) {
      printERROR("uploadNewPlaylist background sync error: $e");
    }
  }

  /// Background update for playlist metadata (e.g. title rename, cover)
  Future<void> updatePlaylistMetadata(Playlist playlist) async {
    if (!_canSync() || !isSyncablePlaylist(playlist)) return;
    try {
      final client = _supabaseService.client!;
      final userId = _supabaseService.userId.value;
      final nowIso = DateTime.now().toUtc().toIso8601String();
      await client.from('playlists').upsert({
        'id': playlist.playlistId,
        'user_id': userId,
        'name': playlist.title,
        'description': playlist.description ?? '',
        'cover_url': playlist.thumbnailUrl,
        'updated_at': nowIso,
      });
      _recordLocalSyncTime(playlist.playlistId);
    } catch (e) {
      printERROR("updatePlaylistMetadata background sync error: $e");
    }
  }

  /// Background sync of tracks when tracks are added, removed, or reordered
  Future<void> syncTracks(String playlistId, List<MediaItem> tracks) async {
    if (!_canSync()) return;
    if (_systemPlaylistIds.contains(playlistId)) return;
    try {
      final client = _supabaseService.client!;
      final userId = _supabaseService.userId.value;
      final nowIso = DateTime.now().toUtc().toIso8601String();

      // Update updated_at on the playlist row
      await client.from('playlists').update({
        'updated_at': nowIso,
      }).eq('id', playlistId);

      // Replace tracks
      await client
          .from('playlist_tracks')
          .delete()
          .eq('playlist_id', playlistId);

      if (tracks.isNotEmpty) {
        final List<Map<String, dynamic>> trackRows = [];
        for (int i = 0; i < tracks.length; i++) {
          final track = tracks[i];
          trackRows.add({
            'id': "${playlistId}_$i",
            'playlist_id': playlistId,
            'user_id': userId,
            'track_id': track.id,
            'position': i,
            'track_data': MediaItemBuilder.toJson(track),
            'updated_at': nowIso,
          });
        }
        await client.from('playlist_tracks').insert(trackRows);
      }
      _recordLocalSyncTime(playlistId);
    } catch (e) {
      printERROR("syncTracks background sync error: $e");
    }
  }

  /// Background delete of playlist from cloud
  Future<void> deleteCloudPlaylist(String playlistId) async {
    if (!_canSync()) return;
    if (_systemPlaylistIds.contains(playlistId)) return;
    try {
      final client = _supabaseService.client!;
      await client.from('playlists').delete().eq('id', playlistId);
      final syncMetaBox = await Hive.openBox("PlaylistSyncMetadata");
      await syncMetaBox.delete(playlistId);
      await syncMetaBox.close();
    } catch (e) {
      printERROR("deleteCloudPlaylist background sync error: $e");
    }
  }

  /// Helper to record local updated_at and synced_at in PlaylistSyncMetadata
  Future<void> _recordLocalSyncTime(String playlistId) async {
    try {
      final syncMetaBox = await Hive.openBox("PlaylistSyncMetadata");
      final nowIso = DateTime.now().toIso8601String();
      await syncMetaBox.put(playlistId, {
        'updated_at': nowIso,
        'synced_at': nowIso,
      });
      await syncMetaBox.close();
    } catch (_) {}
  }

  /// Bidirectionally syncs liked songs (Favorites / LIBFAV) between cloud and local Hive
  Future<void> _syncFavorites(SupabaseClient client, String userId) async {
    try {
      final nowIso = DateTime.now().toUtc().toIso8601String();

      // 1. Ensure LIBFAV playlist entry exists in cloud
      await client.from('playlists').upsert({
        'id': 'LIBFAV',
        'user_id': userId,
        'name': 'Favorites',
        'description': 'Liked Songs',
        'cover_url': Playlist.thumbPlaceholderUrl,
        'updated_at': nowIso,
      });

      // 2. Fetch cloud favorites
      final cloudTracks = await client
          .from('playlist_tracks')
          .select()
          .eq('playlist_id', 'LIBFAV')
          .order('position', ascending: true);

      final Map<String, dynamic> cloudSongMap = {};
      for (final row in cloudTracks) {
        final trackId = row['track_id'].toString();
        cloudSongMap[trackId] = row['track_data'];
      }

      // 3. Open local LIBFAV box
      final favBox = await Hive.openBox("LIBFAV");

      // Merge: Add missing cloud favorites to local LIBFAV box
      for (final entry in cloudSongMap.entries) {
        if (!favBox.containsKey(entry.key) && entry.value != null) {
          await favBox.put(entry.key, entry.value);
        }
      }

      // Merge: Upload any local favorite not yet in cloud
      final List<Map<String, dynamic>> toUpload = [];
      var pos = cloudSongMap.length;
      for (final key in favBox.keys) {
        final songId = key.toString();
        if (!cloudSongMap.containsKey(songId)) {
          final songData = favBox.get(key);
          if (songData != null) {
            toUpload.add({
              'id': 'LIBFAV_$songId',
              'playlist_id': 'LIBFAV',
              'user_id': userId,
              'track_id': songId,
              'position': pos++,
              'track_data': songData,
              'updated_at': nowIso,
            });
          }
        }
      }

      if (toUpload.isNotEmpty) {
        await client.from('playlist_tracks').upsert(toUpload);
      }

      // Refresh active Favorites playlist screen if currently open
      try {
        final plCtrl = Get.find<PlaylistScreenController>(
            tag: const Key("LIBFAV").hashCode.toString());
        plCtrl.fetchSongsfromDatabase("LIBFAV");
      } catch (_) {}
    } catch (e) {
      printERROR("PlaylistSyncService._syncFavorites error: $e");
    }
  }

  /// Syncs a single favorite (liked) song addition or removal in real-time
  Future<void> syncFavoriteSong(MediaItem song, {required bool isAdded}) async {
    if (!_canSync()) return;
    try {
      final client = _supabaseService.client!;
      final userId = _supabaseService.userId.value;
      final nowIso = DateTime.now().toUtc().toIso8601String();

      // Ensure LIBFAV playlist entry exists in playlists table
      await client.from('playlists').upsert({
        'id': 'LIBFAV',
        'user_id': userId,
        'name': 'Favorites',
        'description': 'Liked Songs',
        'cover_url': Playlist.thumbPlaceholderUrl,
        'updated_at': nowIso,
      });

      if (isAdded) {
        await client.from('playlist_tracks').upsert({
          'id': 'LIBFAV_${song.id}',
          'playlist_id': 'LIBFAV',
          'user_id': userId,
          'track_id': song.id,
          'position': 0,
          'track_data': MediaItemBuilder.toJson(song),
          'updated_at': nowIso,
        });
      } else {
        await client
            .from('playlist_tracks')
            .delete()
            .eq('playlist_id', 'LIBFAV')
            .eq('track_id', song.id);
      }
    } catch (e) {
      printERROR("syncFavoriteSong error: $e");
    }
  }

  /// Syncs all local favorites to cloud after batch deletion in Favorites screen
  Future<void> syncAllFavoritesFromLocal() async {
    if (!_canSync()) return;
    try {
      final client = _supabaseService.client!;
      final userId = _supabaseService.userId.value;
      final nowIso = DateTime.now().toUtc().toIso8601String();

      final favBox = await Hive.openBox("LIBFAV");
      await client
          .from('playlist_tracks')
          .delete()
          .eq('playlist_id', 'LIBFAV');

      final List<Map<String, dynamic>> toUpload = [];
      var pos = 0;
      for (final key in favBox.keys) {
        final songId = key.toString();
        final songData = favBox.get(key);
        if (songData != null) {
          toUpload.add({
            'id': 'LIBFAV_$songId',
            'playlist_id': 'LIBFAV',
            'user_id': userId,
            'track_id': songId,
            'position': pos++,
            'track_data': songData,
            'updated_at': nowIso,
          });
        }
      }

      if (toUpload.isNotEmpty) {
        await client.from('playlist_tracks').insert(toUpload);
      }
    } catch (e) {
      printERROR("syncAllFavoritesFromLocal error: $e");
    }
  }
}
