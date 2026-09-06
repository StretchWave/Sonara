import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/models/playlist.dart';
import '/services/lyrics/lrclib_api.dart';
import '/services/metadata/musicbrainz_client.dart';
import '/services/metadata/playlist_metadata_resolver.dart';
import '/services/music_service.dart';
import '/ui/screens/Library/library_controller.dart';
import 'playlist_migration_item.dart';
import 'provider_track_resolver.dart';
import 'spotify_api_client.dart';
import 'spotify_source_track.dart';
import 'track_matcher.dart';

/// How many tracks are resolved concurrently. Bounded so large playlists
/// never fire an unlimited number of provider requests at once.
const int kMaxConcurrentResolutions = 8;

/// Pacing between sequential LRCLIB requests (LRCLIB asks for ~1 req/s).
const Duration kLrcLibPacing = Duration(milliseconds: 400);

/// Pacing between MusicBrainz batches. MusicBrainz asks for at least
/// 1 request/second; the enrichment pool issues a small batch, then waits
/// this long before the next batch, keeping the aggregate rate close to the
/// limit while cutting wall-clock time for large playlists.
const Duration kMusicBrainzPacing = Duration(milliseconds: 700);

/// Outcome of a destination action (liked songs / playlist insertion).
class MigrationResult {
  final int added;
  final int alreadyExists;
  final int failed;

  const MigrationResult({
    required this.added,
    required this.alreadyExists,
    required this.failed,
  });

  int get total => added + alreadyExists + failed;
}

/// Which matches are eligible for a destination action.
enum ConfidenceFilter {
  high,
  highAndMedium,
  all,
}

/// Result of comparing a stored migration against a fresh import.
class ReimportAnalysis {
  final List<PlaylistMigrationItem> unchanged;
  final List<PlaylistMigrationItem> changed;
  final List<SpotifySourceTrack> added;

  const ReimportAnalysis({
    required this.unchanged,
    required this.changed,
    required this.added,
  });

  int get total => unchanged.length + changed.length + added.length;
}

/// Orchestrates the whole migration flow:
///  import playlist -> resolve (cached, bounded) -> lyrics -> review ->
///  destination -> persist.
class PlaylistMigrationService {
  final SpotifyApiClient _apiClient;
  final ProviderTrackResolver _resolver;
  final LrcLibClient _lrcLib;
  final MusicBrainzClient _musicBrainz;
  late final PlaylistMetadataResolver _metadataResolver;

  PlaylistMigrationService({
    SpotifyApiClient? apiClient,
    ProviderTrackResolver? resolver,
    LrcLibClient? lrcLib,
    MusicBrainzClient? musicBrainz,
    PlaylistMetadataResolver? metadataResolver,
  })  : _apiClient = apiClient ?? SpotifyApiClient(),
        _resolver = resolver ??
            ProviderTrackResolver([
              if (Get.isRegistered<MusicServices>())
                YoutubeMusicTrackResolver(Get.find<MusicServices>()),
            ]),
        _lrcLib = lrcLib ?? LrcLibClient(),
        _musicBrainz = musicBrainz ?? MusicBrainzClient() {
    _metadataResolver = metadataResolver ??
        PlaylistMetadataResolver.defaultFor(_apiClient);
  }

  SpotifyApiClient get apiClient => _apiClient;

  /// Long-lived Hive box handles. Opening and closing a box inside every
  /// concurrent `_resolveOne` races (one task closes the box another is
  /// using), so boxes stay open for the service lifetime and are only
  /// re-opened after a teardown (`Hive.close()` in tests) closed them.
  final Map<String, Box> _boxes = {};

  Future<Box> _openBox(String name) async {
    final existing = _boxes[name];
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox(name);
    _boxes[name] = box;
    return box;
  }

  // ---------------------------------------------------------------------
  // Import (multi-source metadata acquisition)
  // ---------------------------------------------------------------------

  /// Extracts the playlist id from a URL / URI / bare id and runs the
  /// metadata provider stack (public metadata -> cache -> official API).
  /// The result distinguishes success, partial access and every failure
  /// kind — the UI never sees a bare "Spotify import failed".
  Future<PlaylistMetadataResolution> importSpotifyPlaylist(
      String urlOrId) async {
    final trimmed = urlOrId.trim();
    final playlistId = SpotifyApiClient.parsePlaylistId(trimmed);
    if (playlistId == null) {
      throw SpotifyApiException(
          SpotifyApiClient.invalidPlaylistReason(trimmed) ??
              'Could not read a Spotify playlist from "$trimmed"');
    }
    // Providers expect a URL they can handle: bare ids and spotify: URIs
    // are normalized to a playlist URL.
    final uri = Uri.parse(trimmed.startsWith('http')
        ? trimmed
        : 'https://open.spotify.com/playlist/$playlistId');
    return _metadataResolver.resolve(uri);
  }

  // ---------------------------------------------------------------------
  // Resolution (cached, bounded concurrency, cancellable)
  // ---------------------------------------------------------------------

  /// Resolves every track with bounded concurrency, updating each item's
  /// status as it goes. [onProgress] is called after every item finishes so
  /// the UI can update live. [shouldCancel] is polled between batches.
  /// [forceRefresh] bypasses the resolution cache ("Re-resolve everything").
  Future<void> resolveAll(
    List<PlaylistMigrationItem> items, {
    void Function(int completed, int total)? onProgress,
    bool Function()? shouldCancel,
    bool forceRefresh = false,
  }) async {
    var completed = 0;
    for (var i = 0; i < items.length; i += kMaxConcurrentResolutions) {
      if (shouldCancel?.call() ?? false) return;
      final batch = items.sublist(
          i, math.min(i + kMaxConcurrentResolutions, items.length));
      await Future.wait(batch.map((item) async {
        await _resolveOne(item, forceRefresh: forceRefresh);
        completed++;
        onProgress?.call(completed, items.length);
      }));
    }
  }

  /// Re-runs resolution for tracks that still need review.
  Future<void> rematchItems(
    List<PlaylistMigrationItem> items, {
    void Function(int completed, int total)? onProgress,
    bool Function()? shouldCancel,
  }) {
    return resolveAll(
      items.where((e) => e.needsReview).toList(),
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    );
  }

  /// Resolves a single track (manual "Search again").
  Future<void> resolveOne(PlaylistMigrationItem item) =>
      _resolveOne(item, forceRefresh: true);

  Future<void> _resolveOne(PlaylistMigrationItem item,
      {bool forceRefresh = false}) async {
    if (item.sourceTrack.title.isEmpty) {
      item.status = MigrationStatus.skipped;
      return;
    }
    item.status = MigrationStatus.searching;
    try {
      // Cache reuse — same recording, previously resolved.
      if (!forceRefresh) {
        final cached = await _cachedResolution(item);
        if (cached != null) {
          _applyOutcome(item, cached);
          return;
        }
      }

      final outcome = await _resolver.resolve(item.sourceTrack);
      final best = outcome.best;
      if (best == null) {
        _applyOutcome(item, null);
      } else {
        _applyOutcome(item, best);
        await _storeResolutionCache(item);
      }
    } catch (e) {
      item.status = MigrationStatus.failed;
      item.error = e.toString();
    }
  }

  void _applyOutcome(PlaylistMigrationItem item, TrackCandidate? best) {
    item.resolvedAt = DateTime.now().millisecondsSinceEpoch;
    item.matchedTrack = best?.track;
    item.matchedProvider = best?.provider;
    item.matchScore = best?.score ?? 0;
    item.confidence = best?.confidence ?? MatchConfidence.unmatched;
    item.status = switch (best?.confidence) {
      MatchConfidence.high => MigrationStatus.matched,
      MatchConfidence.medium || MatchConfidence.low =>
        MigrationStatus.lowConfidence,
      _ => MigrationStatus.unmatched,
    };
    if (item.status == MigrationStatus.unmatched) {
      item.matchedTrack = null;
      item.matchedProvider = null;
      item.matchScore = 0;
      item.confidence = MatchConfidence.unmatched;
    }
  }

  Future<TrackCandidate?> _cachedResolution(
      PlaylistMigrationItem item) async {
    final box = await _openBox('SpotifyResolutionCache');
    final source = item.sourceTrack;
    final keys = [
      if (source.isrc != null && source.isrc!.isNotEmpty)
        'isrc:${source.isrc!.toUpperCase()}',
      'hash:${item.metadataHash}',
    ];
    for (final key in keys) {
      final cached = box.get(key);
      if (cached is Map) {
        final track = MediaItem(
          id: cached['id'],
          album: cached['album'],
          title: cached['title'],
          artist: cached['artist'],
          duration: cached['duration'] != null
              ? Duration(milliseconds: (cached['duration'] as num).toInt())
              : null,
          artUri: Uri.tryParse((cached['artUri'] as String?) ?? ''),
          extras: (cached['extras'] as Map?)
                  ?.map((k, v) => MapEntry(k.toString(), v)) ??
              const {},
        );
        final providerName = cached['provider'] as String?;
        return TrackCandidate(
          provider: MusicProvider.values.firstWhere(
              (p) => p.name == providerName,
              orElse: () => MusicProvider.youtubeMusic),
          track: track,
          score: (cached['score'] as num?)?.toDouble() ?? 0,
          confidence: MatchConfidence.values.firstWhere(
              (c) => c.name == cached['confidence'],
              orElse: () => MatchConfidence.unmatched),
        );
      }
    }
    return null;
  }

  Future<void> _storeResolutionCache(PlaylistMigrationItem item) async {
    final match = item.matchedTrack;
    if (match == null) return;
    final box = await _openBox('SpotifyResolutionCache');
    final payload = {
      'id': match.id,
      'album': match.album,
      'title': match.title,
      'artist': match.artist,
      'duration': match.duration?.inMilliseconds,
      'artUri': match.artUri?.toString(),
      'extras': match.extras,
      'provider': item.matchedProvider?.name,
      'score': item.matchScore,
      'confidence': item.confidence.name,
      'resolvedAt': DateTime.now().millisecondsSinceEpoch,
    };
    final source = item.sourceTrack;
    final keys = [
      if (source.isrc != null && source.isrc!.isNotEmpty)
        'isrc:${source.isrc!.toUpperCase()}',
      'hash:${item.metadataHash}',
    ];
    for (final key in keys) {
      await box.put(key, payload);
    }
  }

  // ---------------------------------------------------------------------
  // MusicBrainz enrichment (sequential, paced, cached, best-effort)
  // ---------------------------------------------------------------------

  /// Looks up an ISRC (and release date) for every track that lacks one via
  /// MusicBrainz, using a small bounded pool with pacing between batches to
  /// respect the API's ~1 req/s limit while cutting wall-clock time.
  /// Results are cached by metadata hash; enrichment is best-effort — a
  /// failure never aborts the import, it just leaves the track without an
  /// ISRC.
  Future<void> enrichWithMusicBrainz(
    List<PlaylistMigrationItem> items, {
    void Function(int completed, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    const poolSize = 2;
    var completed = 0;
    var madeNetworkCalls = false;
    var index = 0;
    while (index < items.length) {
      if (shouldCancel?.call() ?? false) return;
      final batch = <PlaylistMigrationItem>[];
      while (index < items.length && batch.length < poolSize) {
        final item = items[index++];
        final source = item.sourceTrack;
        if (source.title.isNotEmpty &&
            (source.isrc == null || source.isrc!.isEmpty)) {
          batch.add(item);
        } else {
          // No enrichment needed (empty title or ISRC already present).
          completed++;
          onProgress?.call(completed, items.length);
        }
      }
      if (batch.isEmpty) continue;
      // Only pace before a batch when the previous one actually talked to
      // MusicBrainz — cache hits flow through instantly.
      if (madeNetworkCalls) {
        await Future.delayed(kMusicBrainzPacing);
      }
      final hits = await Future.wait(batch.map(_enrichOne));
      madeNetworkCalls = hits.any((h) => h);
      completed += batch.length;
      onProgress?.call(completed, items.length);
    }
  }

  /// The cached MusicBrainz enrichment for [item], or null when absent.
  Future<Map?> _cachedEnrichment(PlaylistMigrationItem item) async {
    final box = await _openBox('MusicBrainzCache');
    final cached = box.get('mb:${item.metadataHash}');
    return cached is Map ? cached : null;
  }

  /// Enriches one track. Returns true when a real MusicBrainz request was
  /// made (cache hits return false — useful for pacing decisions).
  Future<bool> _enrichOne(PlaylistMigrationItem item) async {
    final source = item.sourceTrack;
    final box = await _openBox('MusicBrainzCache');
    final cacheKey = 'mb:${item.metadataHash}';
    final cached = await _cachedEnrichment(item);
    if (cached != null) {
      final isrc = cached['isrc'] as String?;
      if (isrc != null && isrc.isNotEmpty) {
        item.replaceSource(source.copyWith(
          isrc: isrc,
          releaseDate:
              DateTime.tryParse((cached['releaseDate'] as String?) ?? '') ??
                  source.releaseDate,
        ));
      }
      return false;
    }

    try {
      final result = await _musicBrainz.findRecording(
        title: source.title,
        artist: source.artists.isNotEmpty ? source.artists.first : '',
        album: source.album,
        durationMs: source.durationMs > 0 ? source.durationMs : null,
      );
      final isrc =
          (result == null || result.isrcs.isEmpty) ? null : result.isrcs.first;
      final releaseDate = result?.releaseDate;
      await box.put(cacheKey, {
        'isrc': isrc,
        'releaseDate': releaseDate,
        'retrievedAt': DateTime.now().millisecondsSinceEpoch,
      });
      if (isrc != null && isrc.isNotEmpty) {
        item.replaceSource(source.copyWith(
          isrc: isrc,
          releaseDate: releaseDate != null
              ? DateTime.tryParse(releaseDate) ?? source.releaseDate
              : source.releaseDate,
        ));
      }
      return true;
    } on MusicBrainzRateLimited catch (e) {
      // One polite retry after Retry-After, then give up quietly.
      await Future.delayed(e.retryAfter);
      try {
        final result = await _musicBrainz.findRecording(
          title: source.title,
          artist: source.artists.isNotEmpty ? source.artists.first : '',
          album: source.album,
          durationMs: source.durationMs > 0 ? source.durationMs : null,
        );
        final isrc = (result == null || result.isrcs.isEmpty)
            ? null
            : result.isrcs.first;
        if (isrc != null && isrc.isNotEmpty) {
          item.replaceSource(source.copyWith(isrc: isrc));
        }
      } catch (_) {
        // Rate limited again — skip this track's enrichment.
      }
      return true;
    } catch (_) {
      // Best-effort: any failure leaves the track un-enriched.
      return true;
    }
  }

  // ---------------------------------------------------------------------
  // LRCLIB lyrics (sequential, paced, cached)
  // ---------------------------------------------------------------------

  /// Fetches lyrics for every matched track sequentially with pacing,
  /// honoring LRCLIB rate limits and caching by ISRC / track id.
  /// [onProgress] fires per item; [shouldCancel] is polled between items.
  Future<void> resolveLyrics(
    List<PlaylistMigrationItem> items, {
    void Function(int completed, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    var completed = 0;
    for (var i = 0; i < items.length; i++) {
      if (shouldCancel?.call() ?? false) return;
      final item = items[i];
      if (item.matchedTrack != null && i > 0 &&
          // Cached lyrics make no LRCLIB request — only pace before a
          // real lookup, so repeat imports are instant.
          !await _hasCachedLyrics(item)) {
        await Future.delayed(kLrcLibPacing);
      }
      await _resolveLyricsFor(item);
      completed++;
      onProgress?.call(completed, items.length);
    }
  }

  /// True when [item]'s lyrics will be served from cache (or there is no
  /// matched track), so no LRCLIB request — and thus no pacing — is needed.
  Future<bool> _hasCachedLyrics(PlaylistMigrationItem item) async {
    final track = item.matchedTrack;
    if (track == null) return true;
    final source = item.sourceTrack;
    final isrcKey =
        source.isrc != null && source.isrc!.isNotEmpty ? source.isrc! : null;
    final lyricsBox = await _openBox('lyrics');
    if (isrcKey != null && lyricsBox.get('lrclib:$isrcKey') is Map) {
      return true;
    }
    final playback = lyricsBox.get(track.id);
    return playback is Map && playback.containsKey('synced');
  }

  Future<void> _resolveLyricsFor(PlaylistMigrationItem item) async {
    final track = item.matchedTrack;
    if (track == null) {
      item.lyrics.status = LyricsStatus.none;
      return;
    }

    // Cache by ISRC, then by matched track id (playback cache).
    final source = item.sourceTrack;
    final isrcKey =
        source.isrc != null && source.isrc!.isNotEmpty ? source.isrc! : null;
    final lyricsBox = await _openBox('lyrics');
    final cached = isrcKey != null ? lyricsBox.get('lrclib:$isrcKey') : null;
    if (cached is Map) {
      _applyCachedLyrics(item, cached);
      return;
    }
    final playbackCached = lyricsBox.get(track.id);
    if (playbackCached is Map && playbackCached.containsKey('synced')) {
      item.lyrics.status = LyricsStatus.synced;
      item.lyrics.synced = playbackCached['synced'] as String?;
      item.lyrics.plain = playbackCached['plainLyrics'] as String?;
      return;
    }

    try {
      final found = await _fetchLyricsWithRateLimit(item);
      if (found == null) {
        item.lyrics.status = LyricsStatus.notFound;
        return;
      }
      if (found.instrumental && !found.hasSynced && !found.hasPlain) {
        item.lyrics.status = LyricsStatus.instrumental;
        item.lyrics.instrumental = true;
      } else if (LrcLibClient.validateSyncedLyrics(found.syncedLyrics,
              durationMs: source.durationMs) !=
          null) {
        item.lyrics.status = LyricsStatus.synced;
        item.lyrics.synced = found.syncedLyrics;
        item.lyrics.plain = found.plainLyrics;
      } else if (found.hasPlain) {
        item.lyrics.status = LyricsStatus.plain;
        item.lyrics.plain = found.plainLyrics;
      } else {
        item.lyrics.status = LyricsStatus.notFound;
        return;
      }
      item.lyrics.lrclibId = found.id;
      item.lyrics.retrievedAt = DateTime.now().millisecondsSinceEpoch;

      // Write both caches.
      final box = await _openBox('lyrics');
      if (isrcKey != null && isrcKey.isNotEmpty) {
        await box.put('lrclib:$isrcKey', {
          'synced': item.lyrics.synced,
          'plainLyrics': item.lyrics.plain,
          'instrumental': item.lyrics.instrumental,
          'lrclibId': item.lyrics.lrclibId,
          'retrievedAt': item.lyrics.retrievedAt,
        });
      }
      if (item.lyrics.status == LyricsStatus.synced ||
          item.lyrics.status == LyricsStatus.plain) {
        await box.put(track.id, {
          'synced': item.lyrics.synced,
          'plainLyrics': item.lyrics.plain,
        });
      }
    } catch (e) {
      item.lyrics.status = LyricsStatus.failed;
    }
  }

  void _applyCachedLyrics(PlaylistMigrationItem item, Map cached) {
    if (cached['instrumental'] == true) {
      item.lyrics.status = LyricsStatus.instrumental;
      item.lyrics.instrumental = true;
    } else if ((cached['synced'] as String?)?.isNotEmpty == true) {
      item.lyrics.status = LyricsStatus.synced;
      item.lyrics.synced = cached['synced'] as String?;
      item.lyrics.plain = cached['plainLyrics'] as String?;
    } else if ((cached['plainLyrics'] as String?)?.isNotEmpty == true) {
      item.lyrics.status = LyricsStatus.plain;
      item.lyrics.plain = cached['plainLyrics'] as String?;
    } else {
      item.lyrics.status = LyricsStatus.notFound;
    }
    item.lyrics.lrclibId = (cached['lrclibId'] as num?)?.toInt();
    item.lyrics.retrievedAt = (cached['retrievedAt'] as num?)?.toInt();
  }

  /// One metadata lookup, falling back to a scored search; honors
  /// Retry-After on 429 (single retry, then gives up rather than hammering).
  Future<LrcLyrics?> _fetchLyricsWithRateLimit(
      PlaylistMigrationItem item) async {
    final source = item.sourceTrack;
    final artist = source.artists.isNotEmpty ? source.artists.first : '';

    Future<LrcLyrics?> lookup() => _lrcLib.fetchByMetadata(
          trackName: source.title,
          artistName: artist,
          albumName: source.album,
          durationMs: source.durationMs,
        );

    LrcLyrics? result;
    try {
      result = await lookup();
    } on LrcLibRateLimited catch (e) {
      await Future.delayed(e.retryAfter);
      try {
        result = await lookup();
      } on LrcLibRateLimited {
        return null; // still limited — do not keep hammering
      }
    }
    if (result != null) return result;

    // 404 (or empty) — secondary scored search.
    final candidates = await _searchLrcCandidates(item);
    return candidates.isEmpty ? null : candidates.first;
  }

  Future<List<LrcLyrics>> _searchLrcCandidates(
      PlaylistMigrationItem item) async {
    final source = item.sourceTrack;
    final artist = source.artists.isNotEmpty ? source.artists.first : '';
    try {
      final results = await _lrcLib.search(
        trackName: source.title,
        artistName: artist,
        albumName: source.album,
        durationMs: source.durationMs,
      );
      final scored = <(double, LrcLyrics)>[
        for (final candidate in results)
          (
            scoreLrcCandidate(
              trackName: source.title,
              artists: source.artists,
              albumName: source.album,
              durationMs: source.durationMs,
              candidate: candidate,
            ),
            candidate,
          ),
      ]..sort((a, b) => b.$1.compareTo(a.$1));
      // Only accept sufficiently confident candidates — never a random hit.
      return scored
          .where((e) => e.$1 >= 0.75)
          .map((e) => e.$2)
          .take(3)
          .toList();
    } on LrcLibRateLimited {
      return const [];
    }
  }

  // ---------------------------------------------------------------------
  // Persistence / re-import
  // ---------------------------------------------------------------------

  /// Saves the current migration progress (call periodically during
  /// resolution so a crash or cancellation never loses everything).
  Future<void> persistProgress({
    required String spotifyPlaylistId,
    required String spotifyPlaylistName,
    required List<PlaylistMigrationItem> items,
    String? artworkUrl,
    bool completed = false,
  }) async {
    final box = await _openBox('SpotifyMigrations');
    await box.put(spotifyPlaylistId, {
      'name': spotifyPlaylistName,
      'status': completed ? 'completed' : 'in_progress',
      'migratedAt': DateTime.now().millisecondsSinceEpoch,
      'artworkUrl': artworkUrl,
      'items': items.map((e) => e.toJson()).toList(),
    });
  }

  /// Loads a previously stored migration for a playlist, if any.
  Future<Map<dynamic, dynamic>?> loadMigration(String spotifyPlaylistId) async {
    final box = await _openBox('SpotifyMigrations');
    final value = box.get(spotifyPlaylistId);
    return value is Map ? Map<dynamic, dynamic>.from(value) : null;
  }

  /// Rebuilds migration items from a stored record.
  List<PlaylistMigrationItem> itemsFromStored(Map<dynamic, dynamic> stored) {
    final raw = stored['items'] as List? ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => PlaylistMigrationItem.fromJson(e))
        .toList();
  }

  /// Compares a stored migration against the freshly imported tracks:
  /// unchanged (same id + metadata hash), changed (same id, different
  /// metadata) and added (new track ids). Removed tracks are simply absent
  /// from the fresh list.
  ReimportAnalysis analyzeReimport(
    List<PlaylistMigrationItem> storedItems,
    List<SpotifySourceTrack> freshTracks,
  ) {
    final byId = <String, PlaylistMigrationItem>{
      for (final item in storedItems)
        if (item.sourceTrack.spotifyId.isNotEmpty)
          item.sourceTrack.spotifyId: item,
    };
    final unchanged = <PlaylistMigrationItem>[];
    final changed = <PlaylistMigrationItem>[];
    final added = <SpotifySourceTrack>[];
    for (final track in freshTracks) {
      final stored = byId[track.spotifyId];
      if (stored == null) {
        added.add(track);
        continue;
      }
      if (stored.metadataHash == computeMetadataHash(track)) {
        unchanged.add(stored);
      } else {
        // Keep the stored match as a candidate but flag as changed.
        changed.add(stored);
      }
    }
    return ReimportAnalysis(unchanged: unchanged, changed: changed, added: added);
  }

  // ---------------------------------------------------------------------
  // Destinations
  // ---------------------------------------------------------------------

  /// Applies a manually chosen candidate to an item and persists the choice.
  Future<void> applyManualMatch(
      PlaylistMigrationItem item, TrackCandidate candidate) async {
    item.matchedTrack = candidate.track;
    item.matchedProvider = candidate.provider;
    item.matchScore = candidate.score;
    item.confidence = candidate.confidence;
    item.status = MigrationStatus.matched;
    item.manualOverride = true;
    item.resolvedAt = DateTime.now().millisecondsSinceEpoch;
    await _storeResolutionCache(item);
  }

  bool passesConfidenceFilter(PlaylistMigrationItem item, ConfidenceFilter f) {
    if (!item.hasMatch) return false;
    if (item.manualOverride) return true;
    return switch (f) {
      ConfidenceFilter.high => item.confidence == MatchConfidence.high,
      ConfidenceFilter.highAndMedium =>
        item.confidence == MatchConfidence.high ||
            item.confidence == MatchConfidence.medium,
      ConfidenceFilter.all => true,
    };
  }

  /// Adds the matched tracks to Liked Songs, preserving provider source
  /// info through the existing MediaItem-based library.
  Future<MigrationResult> migrateToLiked(
      List<PlaylistMigrationItem> items) async {
    final box = await Hive.openBox('LIBFAV');
    var added = 0, already = 0, failed = 0;
    try {
      for (final item in items) {
        final track = item.matchedTrack;
        if (track == null) {
          failed++;
          continue;
        }
        try {
          if (box.containsKey(track.id)) {
            already++;
          } else {
            await box.put(track.id, MediaItemBuilder.toJson(track));
            added++;
          }
        } catch (_) {
          failed++;
        }
      }
    } finally {
      await box.close();
    }
    return MigrationResult(
        added: added, alreadyExists: already, failed: failed);
  }

  /// Creates a local playlist with the matched tracks in source order.
  Future<MigrationResult> createPlaylist(
    String name,
    List<PlaylistMigrationItem> items, {
    String? artworkUrl,
  }) async {
    final matched = items.where((e) => e.hasMatch).toList();
    final playlist = Playlist(
      title: name.trim().isEmpty ? 'Spotify Import' : name.trim(),
      playlistId: 'LIB${DateTime.now().millisecondsSinceEpoch}',
      thumbnailUrl: artworkUrl ??
          (matched.isNotEmpty
              ? matched.first.matchedTrack!.artUri.toString()
              : Playlist.thumbPlaceholderUrl),
      description: 'Imported from Spotify',
      isCloudPlaylist: false,
    );

    final metaBox = await Hive.openBox('LibraryPlaylists');
    await metaBox.put(playlist.playlistId, playlist.toJson());
    await metaBox.close();

    final tracksBox = await Hive.openBox(playlist.playlistId);
    var index = 0;
    for (final item in matched) {
      try {
        await tracksBox.put(
            index++, MediaItemBuilder.toJson(item.matchedTrack!));
      } catch (_) {
        // Keep going: a broken track must not abort playlist creation.
      }
    }
    await tracksBox.close();

    // Keep the in-memory library in sync when the controller is alive.
    if (Get.isRegistered<LibraryPlaylistsController>()) {
      Get.find<LibraryPlaylistsController>().refreshLib();
    }
    return MigrationResult(
        added: matched.length,
        alreadyExists: 0,
        failed: items.length - matched.length);
  }

  /// Appends the matched tracks to an existing local playlist, skipping
  /// tracks that are already present.
  Future<MigrationResult> addToExistingPlaylist(
      Playlist playlist, List<PlaylistMigrationItem> items) async {
    final box = await Hive.openBox(playlist.playlistId);
    var added = 0, already = 0, failed = 0;
    try {
      final existingIds = box.values
          .map((e) => e is Map ? (e['id']?.toString() ?? '') : '')
          .where((id) => id.isNotEmpty)
          .toSet();
      var index = box.length;
      for (final item in items) {
        final track = item.matchedTrack;
        if (track == null) {
          failed++;
          continue;
        }
        if (existingIds.contains(track.id)) {
          already++;
          continue;
        }
        try {
          await box.put(index++, MediaItemBuilder.toJson(track));
          existingIds.add(track.id);
          added++;
        } catch (_) {
          failed++;
        }
      }
    } finally {
      await box.close();
    }
    return MigrationResult(
        added: added, alreadyExists: already, failed: failed);
  }

  /// Completes the migration record after a destination action.
  Future<void> completeMigration({
    required String spotifyPlaylistId,
    required String spotifyPlaylistName,
    required List<PlaylistMigrationItem> items,
    String? artworkUrl,
  }) {
    return persistProgress(
      spotifyPlaylistId: spotifyPlaylistId,
      spotifyPlaylistName: spotifyPlaylistName,
      items: items,
      artworkUrl: artworkUrl,
      completed: true,
    );
  }
}
