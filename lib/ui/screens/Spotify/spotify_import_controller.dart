import 'dart:async';

import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/playlist.dart';
import '/services/metadata/playlist_metadata_provider.dart';
import '/services/spotify/playlist_migration_item.dart';
import '/services/spotify/playlist_migration_service.dart';
import '/services/spotify/spotify_source_track.dart';
import '/services/spotify/track_matcher.dart';

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
  final service = PlaylistMigrationService();

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

  /// Tracks visible under the current review filter.
  List<PlaylistMigrationItem> get filteredItems {
    switch (reviewFilter.value) {
      case ReviewFilter.all:
        return items;
      case ReviewFilter.needsReview:
        return items.where((e) => e.needsReview).toList();
      case ReviewFilter.matched:
        return items.where((e) => e.hasMatch).toList();
      case ReviewFilter.unavailable:
        return items
            .where((e) => e.status == MigrationStatus.unmatched ||
                e.status == MigrationStatus.failed ||
                e.status == MigrationStatus.skipped)
            .toList();
    }
  }

  /// Matches eligible for the destination, honoring the confidence filter.
  List<PlaylistMigrationItem> get eligibleItems => items
      .where((e) => service.passesConfidenceFilter(e, confidenceFilter.value))
      .toList();

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

    // 1) Enrich tracks that lack an ISRC (MusicBrainz). Best-effort:
    //    failures are ignored and cached results are instant.
    if (Hive.box('AppPrefs')
            .get('spotifyAutoEnrichTracks', defaultValue: true) ==
        true) {
      stage.value = ResolutionStage.enriching;
      await service.enrichWithMusicBrainz(
        target,
        onProgress: (completed, total) {
          // Enrichment happens before matching, so its progress must move
          // the same counter the UI shows — otherwise the import looks
          // stuck at 0 while the ISRC lookups run.
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

  Future<void> _persist() async {
    if (playlistId.value.isEmpty) return;
    try {
      await service.persistProgress(
        spotifyPlaylistId: playlistId.value,
        spotifyPlaylistName: playlistName.value,
        items: items.toList(),
      );
    } catch (_) {
      // Persistence must never break the migration flow.
    }
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
      await service.completeMigration(
        spotifyPlaylistId: playlistId.value,
        spotifyPlaylistName: playlistName.value,
        items: items.toList(),
      );
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
  }
}
