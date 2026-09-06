import 'package:audio_service/audio_service.dart';

import 'spotify_source_track.dart';
import 'track_matcher.dart';

/// Lifecycle of one track during a playlist migration.
enum MigrationStatus {
  pending,
  searching,
  matched,
  lowConfidence,
  unmatched,
  failed,
  skipped,
}

/// State of the LRCLIB lyrics lookup for a migrated track.
enum LyricsStatus {
  none,
  synced,
  plain,
  instrumental,
  notFound,
  failed,
}

/// Lyrics payload attached to a migration item.
class MigrationLyrics {
  LyricsStatus status;
  String? synced;
  String? plain;
  int? lrclibId;
  bool instrumental;
  int? retrievedAt;

  MigrationLyrics({
    this.status = LyricsStatus.none,
    this.synced,
    this.plain,
    this.lrclibId,
    this.instrumental = false,
    this.retrievedAt,
  });

  factory MigrationLyrics.fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) return MigrationLyrics();
    return MigrationLyrics(
      status: LyricsStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => LyricsStatus.none),
      synced: json['synced'] as String?,
      plain: json['plain'] as String?,
      lrclibId: (json['lrclibId'] as num?)?.toInt(),
      instrumental: json['instrumental'] as bool? ?? false,
      retrievedAt: (json['retrievedAt'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'synced': synced,
        'plain': plain,
        'lrclibId': lrclibId,
        'instrumental': instrumental,
        'retrievedAt': retrievedAt,
      };
}

/// One Spotify track plus everything learned about its migration:
/// the source metadata, the chosen provider match, the score and the
/// candidate list offered for manual review.
class PlaylistMigrationItem {
  /// Mutable so enrichment (MusicBrainz ISRC lookup) can upgrade the source
  /// metadata before matching.
  SpotifySourceTrack sourceTrack;

  /// Stable hash of the source metadata used to detect changed tracks on
  /// re-imports and to key the resolution cache. Recomputes on enrichment.
  String metadataHash;

  MigrationStatus status;
  MediaItem? matchedTrack;
  MusicProvider? matchedProvider;
  double matchScore;
  MatchConfidence confidence;
  List<TrackCandidate> candidates;
  String? error;

  /// True when the match was chosen by the user rather than automatically.
  bool manualOverride;

  /// When the resolution finished.
  int? resolvedAt;

  /// LRCLIB lookup result for the resolved track.
  MigrationLyrics lyrics;

  PlaylistMigrationItem({
    required this.sourceTrack,
    String? metadataHash,
    this.status = MigrationStatus.pending,
    this.matchedTrack,
    this.matchedProvider,
    this.matchScore = 0,
    this.confidence = MatchConfidence.unmatched,
    List<TrackCandidate>? candidates,
    this.error,
    this.manualOverride = false,
    this.resolvedAt,
    MigrationLyrics? lyrics,
  })  : metadataHash = metadataHash ?? computeMetadataHash(sourceTrack),
        candidates = candidates ?? [],
        lyrics = lyrics ?? MigrationLyrics();

  /// Replaces the source metadata (e.g. after ISRC enrichment) and keeps
  /// the metadata hash in sync so cache keys stay correct.
  void replaceSource(SpotifySourceTrack track) {
    sourceTrack = track;
    metadataHash = computeMetadataHash(track);
  }

  /// True when a usable (possibly tentative) match exists.
  bool get hasMatch => matchedTrack != null;

  bool get needsReview =>
      status == MigrationStatus.lowConfidence ||
      status == MigrationStatus.unmatched ||
      status == MigrationStatus.failed;

  factory PlaylistMigrationItem.fromJson(Map<dynamic, dynamic> json) =>
      PlaylistMigrationItem(
        sourceTrack: SpotifySourceTrack.fromJson(
            (json['source'] ?? json['sourceTrack']) as Map),
        metadataHash: json['metadataHash'] as String?,
        status: MigrationStatus.values
            .firstWhere((s) => s.name == json['status'],
                orElse: () => MigrationStatus.pending),
        matchedTrack: json['matchedTrack'] != null
            ? MediaItem(
                id: json['matchedTrack']['id'],
                album: json['matchedTrack']['album'],
                title: json['matchedTrack']['title'],
                artist: json['matchedTrack']['artist'],
                duration: json['matchedTrack']['duration'] != null
                    ? Duration(
                        milliseconds:
                            (json['matchedTrack']['duration'] as num).toInt())
                    : null,
                artUri: Uri.tryParse(
                    (json['matchedTrack']['artUri'] as String?) ?? ''),
                extras: (json['matchedTrack']['extras'] as Map?)
                        ?.map((k, v) => MapEntry(k.toString(), v)) ??
                    const {},
              )
            : null,
        matchedProvider: json['matchedProvider'] != null
            ? MusicProvider.values.firstWhere(
                (p) => p.name == json['matchedProvider'],
                orElse: () => MusicProvider.youtubeMusic)
            : null,
        matchScore: (json['matchScore'] as num?)?.toDouble() ?? 0,
        confidence: MatchConfidence.values.firstWhere(
            (c) => c.name == json['confidence'],
            orElse: () => MatchConfidence.unmatched),
        manualOverride: json['manualOverride'] as bool? ?? false,
        resolvedAt: (json['resolvedAt'] as num?)?.toInt(),
        lyrics: MigrationLyrics.fromJson(
            json['lyrics'] as Map<dynamic, dynamic>?),
      );

  Map<String, dynamic> toJson() => {
        'source': sourceTrack.toJson(),
        'metadataHash': metadataHash,
        'status': status.name,
        'matchedTrack': matchedTrack != null
            ? {
                'id': matchedTrack!.id,
                'album': matchedTrack!.album,
                'title': matchedTrack!.title,
                'artist': matchedTrack!.artist,
                'duration': matchedTrack!.duration?.inMilliseconds,
                'artUri': matchedTrack!.artUri?.toString(),
                'extras': matchedTrack!.extras,
              }
            : null,
        'matchedProvider': matchedProvider?.name,
        'matchScore': matchScore,
        'confidence': confidence.name,
        'manualOverride': manualOverride,
        'resolvedAt': resolvedAt,
        'lyrics': lyrics.toJson(),
      };
}

/// Stable hash of the source metadata that identifies the recording
/// independently of the Spotify ID — used for change detection and cache
/// keys. Two identical recordings produce the same hash.
String computeMetadataHash(SpotifySourceTrack t) {
  final parts = [
    t.title.toLowerCase().trim(),
    t.artists.map((a) => a.toLowerCase().trim()).join('|'),
    t.album?.toLowerCase().trim() ?? '',
    t.durationMs.toString(),
    t.isrc?.toUpperCase().trim() ?? '',
  ];
  var hash = 0;
  for (final part in parts) {
    for (final rune in part.runes) {
      hash = (hash * 31 + rune) & 0x7fffffff;
    }
  }
  return hash.toRadixString(16);
}
