import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '/models/playlist.dart';
import '/services/metadata/playlist_metadata_provider.dart';
import '/services/spotify/playlist_migration_item.dart';
import '/services/spotify/playlist_migration_service.dart';
import '/services/spotify/spotify_source_track.dart';
import '/services/spotify/track_matcher.dart';
import '../Playlist/playlist_screen_controller.dart';
import '/services/supabase/playlist_sync_service.dart';

/// UI phases of the migration flow.
enum MigrationPhase {
  setup,
  importing,

  /// The playlist was identified but its track list needs Spotify access.
  authRequired,
  reimport,
  resolving,
  review,
  migrating,
  done,
}

/// Sorting options for imported tracks.
enum ImportSortType { playlistOrder, title, artist, duration }

/// Filter for the review list.
enum ReviewFilter { all, needsReview, matched, unavailable }

/// How to handle a previously stored migration of the same playlist.
enum ReimportChoice { reuseMatches, reResolveAll, startFresh }

/// What step of the resolve pipeline is currently running.
enum ResolutionStage { enriching, matching, lyrics }

/// Every N resolved items the progress record is written to disk, so a crash
/// or cancellation mid-import never loses more than a handful of tracks.
const int kPersistEvery = 10;

class SpotifyImportController extends GetxController {
  final PlaylistMigrationService service;

  SpotifyImportController({PlaylistMigrationService? service})
      : service = service ?? PlaylistMigrationService();

  /// Stored / completed migrations loaded from Hive for one-tap review/export.
  final savedMigrations = <Map<String, dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    loadSavedMigrations();
  }

  // -- setup --------------------------------------------------------------
  final phase = MigrationPhase.setup.obs;
  final urlInput = ''.obs;
  final errorMessage = RxnString();

  /// Shown on the auth-required phase (playlist identified but its track
  /// list could not be acquired automatically).
  final authMessage = RxnString();

  // -- import -------------------------------------------------------------
  final playlistId = ''.obs;
  final playlistName = ''.obs;
  final playlistArtwork = RxnString();
  final totalTracks = 0.obs;

  /// The freshly fetched source tracks, kept for order-preserving re-import
  /// reconciliation.
  List<SpotifySourceTrack>? _freshTracks;

  // -- re-import detection ------------------------------------------------
  final reimportRecord = Rxn<Map<dynamic, dynamic>>();
  final reimport = Rxn<ReimportAnalysis>();

  // -- resolution ---------------------------------------------------------
  final RxList<PlaylistMigrationItem> items = RxList();
  final completedTracks = 0.obs;
  final isResolving = false.obs;
  final stage = ResolutionStage.matching.obs;
  final lyricsDone = 0.obs;
  final lyricsTotal = 0.obs;
  final cancelRequested = false.obs;
  final wasCancelled = false.obs;

  // -- review -------------------------------------------------------------
  final reviewFilter = ReviewFilter.all.obs;
  final confidenceFilter = ConfidenceFilter.highAndMedium.obs;

  // -- destination --------------------------------------------------------
  final isMigrating = false.obs;
  final lastResult = Rxn<MigrationResult>();
  final lastDestination = ''.obs;

  bool get isConfigured => service.apiClient.isConfigured;

  int get matchedCount =>
      items.where((e) => e.status == MigrationStatus.matched).length;

  int get uncertainCount => items
      .where((e) => e.status == MigrationStatus.lowConfidence)
      .length;

  int get unavailableCount => items
      .where((e) => e.status == MigrationStatus.unmatched ||
          e.status == MigrationStatus.failed ||
          e.status == MigrationStatus.skipped)
      .length;

  int get searchingCount =>
      items.where((e) => e.status == MigrationStatus.searching).length;

  // -- sorting -------------------------------------------------------------
  final sortType = ImportSortType.playlistOrder.obs;
  final sortAscending = true.obs;

  void setSort(ImportSortType type, {bool? ascending}) {
    if (type == sortType.value && ascending == null) {
      sortAscending.value = !sortAscending.value;
    } else {
      sortType.value = type;
      sortAscending.value = ascending ?? true;
    }
  }

  List<PlaylistMigrationItem> _applySort(List<PlaylistMigrationItem> list) {
    final sorted = List<PlaylistMigrationItem>.from(list);
    sorted.sort((a, b) {
      int cmp = 0;
      switch (sortType.value) {
        case ImportSortType.playlistOrder:
          final numA = a.sourceTrack.trackNumber ?? 0;
          final numB = b.sourceTrack.trackNumber ?? 0;
          cmp = numA.compareTo(numB);
          break;
        case ImportSortType.title:
          final titleA =
              (a.matchedTrack?.title ?? a.sourceTrack.title).toLowerCase();
          final titleB =
              (b.matchedTrack?.title ?? b.sourceTrack.title).toLowerCase();
          cmp = titleA.compareTo(titleB);
          break;
        case ImportSortType.artist:
          final artistA = (a.matchedTrack?.artist ??
                  a.sourceTrack.artists.join(', '))
              .toLowerCase();
          final artistB = (b.matchedTrack?.artist ??
                  b.sourceTrack.artists.join(', '))
              .toLowerCase();
          cmp = artistA.compareTo(artistB);
          break;
        case ImportSortType.duration:
          final durA = a.matchedTrack?.duration?.inMilliseconds ??
              a.sourceTrack.durationMs;
          final durB = b.matchedTrack?.duration?.inMilliseconds ??
              b.sourceTrack.durationMs;
          cmp = durA.compareTo(durB);
          break;
      }
      return sortAscending.value ? cmp : -cmp;
    });
    return sorted;
  }

  /// Tracks visible under the current review filter, sorted according to [sortType].
  List<PlaylistMigrationItem> get filteredItems {
    final List<PlaylistMigrationItem> base;
    switch (reviewFilter.value) {
      case ReviewFilter.all:
        base = items;
        break;
      case ReviewFilter.needsReview:
        base = items.where((e) => e.needsReview).toList();
        break;
      case ReviewFilter.matched:
        base = items.where((e) => e.hasMatch).toList();
        break;
      case ReviewFilter.unavailable:
        base = items
            .where((e) =>
                e.status == MigrationStatus.unmatched ||
                e.status == MigrationStatus.failed ||
                e.status == MigrationStatus.skipped)
            .toList();
        break;
    }
    return _applySort(base);
  }

  /// Matches eligible for the destination, honoring the confidence filter and sorted order.
  List<PlaylistMigrationItem> get eligibleItems {
    final base = items
        .where((e) => service.passesConfidenceFilter(e, confidenceFilter.value))
        .toList();
    return _applySort(base);
  }

  // -- lyrics summary -----------------------------------------------------
  int get lyricsSyncedCount =>
      items.where((e) => e.lyrics.status == LyricsStatus.synced).length;

  int get lyricsPlainCount =>
      items.where((e) => e.lyrics.status == LyricsStatus.plain).length;

  int get lyricsInstrumentalCount =>
      items.where((e) => e.lyrics.status == LyricsStatus.instrumental).length;

  int get lyricsUnavailableCount =>
      items.where((e) => e.lyrics.status == LyricsStatus.notFound).length;

  int get lyricsFailedCount =>
      items.where((e) => e.lyrics.status == LyricsStatus.failed).length;

  // -----------------------------------------------------------------------
  // Import
  // -----------------------------------------------------------------------

  /// Runs the multi-source metadata acquisition. No Spotify sign-in is
  /// required up front: public metadata and the local cache are tried
  /// first, and authentication is only requested when the track list
  /// actually needs it.
  Future<void> importPlaylist() async {
    errorMessage.value = null;
    authMessage.value = null;
    final url = urlInput.value.trim();
    if (url.isEmpty) {
      errorMessage.value = 'Enter a Spotify playlist URL or ID';
      return;
    }
    try {
      phase.value = MigrationPhase.importing;
      final resolution = await service.importSpotifyPlaylist(url);
      playlistId.value = resolution.playlistId ?? '';
      playlistName.value = resolution.name ?? '';
      playlistArtwork.value = resolution.artworkUrl;
      final tracks = resolution.tracks;
      totalTracks.value = tracks.length;
      wasCancelled.value = false;

      if (tracks.isEmpty) {
        // Identified but no track list could be acquired automatically.
        if (resolution.authenticationRequired ||
            resolution.status == PlaylistMetadataStatus.partialSuccess) {
          authMessage.value = resolution.message ??
              'Could not load this playlist\u2019s tracks automatically';
          phase.value = MigrationPhase.authRequired;
        } else {
          errorMessage.value =
              resolution.message ?? 'Could not acquire this playlist';
          phase.value = MigrationPhase.setup;
        }
        return;
      }
      _freshTracks = tracks;

      // Repeated import: surface the stored migration before resolving.
      final stored = await service.loadMigration(playlistId.value);
      if (stored != null) {
        final storedItems = service.itemsFromStored(stored);
        reimportRecord.value = stored;
        reimport.value = service.analyzeReimport(storedItems, tracks);
        // Keep the stored items alive so the re-import view can report on
        // what was previously resolved.
        items.value = storedItems;
        phase.value = MigrationPhase.reimport;
      } else {
        reimportRecord.value = null;
        reimport.value = null;
        items.value = tracks
            .map((t) => PlaylistMigrationItem(sourceTrack: t))
            .toList();
        await resolveAll();
      }
    } catch (e) {
      errorMessage.value = 'Import failed: $e';
      phase.value = MigrationPhase.setup;
    }
  }

  /// Applies the user's choice for a repeated import.
  Future<void> chooseReimport(ReimportChoice choice) async {
    final analysis = reimport.value;
    if (analysis == null) return;

    switch (choice) {
      case ReimportChoice.startFresh:
        // Discard the stored record; previous matches are forgotten
        // (the metadata resolution cache still applies on re-resolution).
        final box = await Hive.openBox('SpotifyMigrations');
        await box.delete(playlistId.value);
        await box.close();
        items.value = _freshTracks
                ?.map((t) => PlaylistMigrationItem(sourceTrack: t))
                .toList() ??
            [];
        await resolveAll();
      case ReimportChoice.reuseMatches:
        // Unchanged tracks keep their previous matches; new and changed
        // tracks are re-resolved.
        items.value = _freshItemsFromStored(analysis);
        final resolveIds = <String>{
          ...analysis.changed.map((e) => e.sourceTrack.spotifyId),
          ...analysis.added.map((t) => t.spotifyId),
        };
        final toResolve = items
            .where((e) => resolveIds.contains(e.sourceTrack.spotifyId))
            .toList();
        await resolveAll(only: toResolve);
      case ReimportChoice.reResolveAll:
        // Keep the stored metadata/lyrics but force fresh provider
        // resolution for every track (cache bypassed).
        items.value = _freshItemsFromStored(analysis);
        await resolveAll(forceRefresh: true);
    }
  }

  /// Stored items (unchanged + changed) merged back into the fresh playlist
  /// order; tracks that were removed from the Spotify playlist are dropped.
  List<PlaylistMigrationItem> _freshItemsFromStored(
      ReimportAnalysis analysis) {
    final storedById = <String, PlaylistMigrationItem>{
      for (final item in [...analysis.unchanged, ...analysis.changed])
        if (item.sourceTrack.spotifyId.isNotEmpty)
          item.sourceTrack.spotifyId: item,
    };
    final result = <PlaylistMigrationItem>[];
    for (final track in _freshTracks ?? const <SpotifySourceTrack>[]) {
      final stored = storedById.remove(track.spotifyId);
      result.add(stored ?? PlaylistMigrationItem(sourceTrack: track));
    }
    return result;
  }

  // -----------------------------------------------------------------------
  // Resolution
  // -----------------------------------------------------------------------

  /// Runs the resolve pipeline for [only] (default: every item):
  ///  1. ISRC enrichment via MusicBrainz (sequential, cached, best-effort)
  ///  2. provider matching with bounded concurrency
  ///  3. LRCLIB lyrics, sequential and rate-limit aware
  /// Progress is persisted incrementally so a crash never loses everything.
  Future<void> resolveAll(
      {List<PlaylistMigrationItem>? only, bool forceRefresh = false}) async {
    final target = only ?? items.toList();
    if (target.isEmpty) {
      phase.value = MigrationPhase.review;
      return;
    }
    isResolving.value = true;
    cancelRequested.value = false;
    phase.value = MigrationPhase.resolving;
    completedTracks.value = items.length - target.length;

    try {
      await WakelockPlus.enable();
    } catch (_) {}

    try {
      // 1) Enrich tracks that lack an ISRC (MusicBrainz). Best-effort:
      //    failures are ignored and cached results are instant.
      if (Hive.box('AppPrefs')
              .get('spotifyAutoEnrichTracks', defaultValue: true) ==
          true) {
        stage.value = ResolutionStage.enriching;
        await service.enrichWithMusicBrainz(
          target,
          onProgress: (completed, total) {
            completedTracks.value = items.length - target.length + completed;
            items.refresh();
          },
          shouldCancel: () => cancelRequested.value,
        );
      }

      if (cancelRequested.value) {
        wasCancelled.value = true;
        isResolving.value = false;
        phase.value = MigrationPhase.review;
        await _persist();
        return;
      }

      // 2) Provider matching.
      stage.value = ResolutionStage.matching;
      await service.resolveAll(
        target,
        forceRefresh: forceRefresh,
        onProgress: (completed, total) {
          completedTracks.value = items.length - target.length + completed;
          items.refresh();
          _maybePersist(completed);
        },
        shouldCancel: () => cancelRequested.value,
      );

      if (!cancelRequested.value) {
        final lyricsTarget = items
            .where((e) =>
                e.matchedTrack != null && e.lyrics.status == LyricsStatus.none)
            .toList();
        if (lyricsTarget.isNotEmpty &&
            Hive.box('AppPrefs')
                    .get('spotifyAutoFetchLyrics', defaultValue: true) ==
                true) {
          stage.value = ResolutionStage.lyrics;
          lyricsDone.value = 0;
          lyricsTotal.value = lyricsTarget.length;
          await service.resolveLyrics(
            lyricsTarget,
            onProgress: (completed, total) {
              lyricsDone.value = completed;
              items.refresh();
            },
            shouldCancel: () => cancelRequested.value,
          );
        }
      }

      wasCancelled.value = cancelRequested.value;
      isResolving.value = false;
      stage.value = ResolutionStage.matching;
      phase.value = MigrationPhase.review;
      // Final persistence (completed or partial — both are resumable).
      await _persist();
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  /// Requests cancellation; the resolver stops between batches, in-flight
  /// requests finish safely and everything resolved so far is preserved.
  void cancel() => cancelRequested.value = true;

  /// Re-runs resolution for tracks that still need review.
  Future<void> retryUnmatched() async {
    final pending = items.where((e) => e.needsReview).toList();
    if (pending.isEmpty) return;
    // Clear stale state so they are genuinely re-resolved.
    for (final item in pending) {
      item.matchedTrack = null;
      item.matchedProvider = null;
      item.matchScore = 0;
      item.confidence = MatchConfidence.unmatched;
      item.status = MigrationStatus.pending;
      item.error = null;
    }
    await resolveAll(only: pending);
  }

  Future<void> applyManualMatch(
      PlaylistMigrationItem item, TrackCandidate candidate) async {
    await service.applyManualMatch(item, candidate);
    items.refresh();
  }

  /// Marks a track as intentionally skipped (it is excluded from
  /// destinations but stays in the review list).
  void skipTrack(PlaylistMigrationItem item) {
    item.status = MigrationStatus.skipped;
    items.refresh();
  }

  /// Persists progress at most every [kPersistEvery] completed items.
  int _lastPersisted = 0;

  void _maybePersist(int completed) {
    if (completed - _lastPersisted < kPersistEvery) return;
    _lastPersisted = completed;
    unawaited(_persist());
  }

  Future<void> _persist({bool completed = false}) async {
    if (playlistId.value.isEmpty) return;
    try {
      final isDone = completed ||
          (totalTracks.value > 0 && completedTracks.value >= totalTracks.value);
      await service.persistProgress(
        spotifyPlaylistId: playlistId.value,
        spotifyPlaylistName: playlistName.value,
        items: items.toList(),
        artworkUrl: playlistArtwork.value,
        completed: isDone,
      );
      await loadSavedMigrations();
    } catch (_) {
      // Persistence must never break the migration flow.
    }
  }

  /// Loads all stored migrations from Hive for easy access on the setup screen.
  Future<void> loadSavedMigrations() async {
    try {
      final box = await Hive.openBox('SpotifyMigrations');
      final list = <Map<String, dynamic>>[];
      for (final key in box.keys) {
        final val = box.get(key);
        if (val is Map) {
          final itemsRaw = val['items'] as List? ?? const [];
          final total = itemsRaw.length;
          final matched = itemsRaw
              .where((i) => i is Map && i['status'] == 'matched')
              .length;
          list.add({
            'id': key.toString(),
            'name': (val['name'] as String?) ?? 'Spotify Playlist',
            'status': (val['status'] as String?) ?? 'in_progress',
            'migratedAt': (val['migratedAt'] as num?)?.toInt() ?? 0,
            'artworkUrl': val['artworkUrl'] as String?,
            'totalTracks': total,
            'matchedTracks': matched,
          });
        }
      }
      list.sort((a, b) =>
          ((b['migratedAt'] as num?)?.toInt() ?? 0)
              .compareTo((a['migratedAt'] as num?)?.toInt() ?? 0));
      savedMigrations.value = list;
    } catch (_) {}
  }

  /// Opens a previously stored migration directly into the Review screen
  /// so the user can review tracks and choose a destination without re-resolving.
  Future<void> openSavedMigration(String id) async {
    final stored = await service.loadMigration(id);
    if (stored == null) return;
    final storedItems = service.itemsFromStored(stored);
    playlistId.value = id;
    playlistName.value = stored['name'] as String? ?? 'Spotify Playlist';
    playlistArtwork.value = stored['artworkUrl'] as String? ??
        (storedItems.isNotEmpty
            ? storedItems.first.sourceTrack.artworkUrl
            : null);
    items.value = storedItems;
    totalTracks.value = storedItems.length;
    completedTracks.value = storedItems
        .where((e) =>
            e.status != MigrationStatus.pending &&
            e.status != MigrationStatus.searching)
        .length;
    wasCancelled.value = false;
    phase.value = MigrationPhase.review;
  }

  /// Deletes a saved migration from Hive.
  Future<void> deleteSavedMigration(String id) async {
    try {
      final box = await Hive.openBox('SpotifyMigrations');
      await box.delete(id);
      await loadSavedMigrations();
    } catch (_) {}
  }

  // -----------------------------------------------------------------------
  // Destinations
  // -----------------------------------------------------------------------

  Future<void> migrateToLiked() => _runDestination(
        'likedSongs'.tr,
        () => service.migrateToLiked(eligibleItems),
      );

  Future<void> createPlaylist(String name) => _runDestination(
        name,
        () => service.createPlaylist(name, eligibleItems,
            artworkUrl: playlistArtwork.value),
      );

  Future<void> addToExistingPlaylist(Playlist playlist) =>
      _runDestination(
        playlist.title,
        () => service.addToExistingPlaylist(playlist, eligibleItems),
      );

  Future<void> _runDestination(
      String destination, Future<MigrationResult> Function() action) async {
    if (eligibleItems.isEmpty) {
      lastResult.value =
          const MigrationResult(added: 0, alreadyExists: 0, failed: 0);
      return;
    }
    isMigrating.value = true;
    try {
      lastDestination.value = destination;
      lastResult.value = await action();
      if (destination == 'addToLikedSongs'.tr || destination == 'likedSongs'.tr) {
        try {
          if (Get.isRegistered<PlaylistScreenController>(
              tag: const Key("LIBFAV").hashCode.toString())) {
            final plCtrl = Get.find<PlaylistScreenController>(
                tag: const Key("LIBFAV").hashCode.toString());
            plCtrl.fetchSongsfromDatabase("LIBFAV");
          }
          if (Get.isRegistered<PlaylistSyncService>()) {
            Get.find<PlaylistSyncService>().syncAllFavoritesFromLocal();
          }
        } catch (_) {}
      }
      await service.completeMigration(
        spotifyPlaylistId: playlistId.value,
        spotifyPlaylistName: playlistName.value,
        items: items.toList(),
        artworkUrl: playlistArtwork.value,
      );
      await loadSavedMigrations();
      phase.value = MigrationPhase.done;
    } catch (e) {
      lastResult.value = null;
      errorMessage.value = 'Migration failed: $e';
    } finally {
      isMigrating.value = false;
    }
  }

  void reset() {
    phase.value = MigrationPhase.setup;
    items.clear();
    playlistId.value = '';
    playlistName.value = '';
    playlistArtwork.value = null;
    totalTracks.value = 0;
    completedTracks.value = 0;
    lyricsDone.value = 0;
    lyricsTotal.value = 0;
    _freshTracks = null;
    lastResult.value = null;
    lastDestination.value = '';
    errorMessage.value = null;
    authMessage.value = null;
    reimportRecord.value = null;
    reimport.value = null;
    wasCancelled.value = false;
    reviewFilter.value = ReviewFilter.all;
    confidenceFilter.value = ConfidenceFilter.highAndMedium;
    sortType.value = ImportSortType.playlistOrder;
    sortAscending.value = true;
  }
}
