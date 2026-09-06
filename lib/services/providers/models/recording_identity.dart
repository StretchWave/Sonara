/// Canonical recording identity — the single source of truth for what
/// recording the user selected, used by both playback and download
/// resolution.
///
/// Every conversion path (MediaItem → RecordingIdentity → SongQuery →
/// JSON → RecordingIdentity) must be lossless: no field silently dropped.
library;

import 'package:audio_service/audio_service.dart' show MediaItem;

import '../matching/isrc.dart';
import '../song_query.dart';
import 'version_type.dart';

/// Immutable identity of a specific recording.
class RecordingIdentity {
  /// YouTube / internal media identifier.
  final String mediaId;

  /// Original YouTube video ID when different from mediaId (e.g. after
  /// a cross-catalog resolve).
  final String? sourceVideoId;

  final String title;

  /// The primary performing artist(s).
  final List<String> primaryArtists;

  /// Featured / guest artists.
  final List<String> featuredArtists;

  final String? album;
  final String? albumArtist;

  /// Track duration in milliseconds.
  final int? durationMs;

  /// International Standard Recording Code (normalized 12-char uppercase).
  final String? isrc;

  /// YouTube video type (e.g. `MUSIC_VIDEO_TYPE_ATV` for official audio).
  final String? videoType;

  /// Classified version type of this recording.
  final VersionType versionType;

  /// Raw version label from metadata (e.g. "Deluxe Edition", "Radio Edit").
  final String? versionLabel;

  final int? releaseYear;
  final int? discNumber;
  final int? trackNumber;

  /// Explicit content flag: true = explicit, false = clean, null = unknown.
  final bool? explicitStatus;

  /// The provider this recording was originally discovered from.
  final String? originalProvider;

  /// ISO 3166-1 alpha-2 country code.
  final String countryCode;

  const RecordingIdentity({
    required this.mediaId,
    this.sourceVideoId,
    this.title = '',
    this.primaryArtists = const [],
    this.featuredArtists = const [],
    this.album,
    this.albumArtist,
    this.durationMs,
    this.isrc,
    this.videoType,
    this.versionType = VersionType.unknown,
    this.versionLabel,
    this.releaseYear,
    this.discNumber,
    this.trackNumber,
    this.explicitStatus,
    this.originalProvider,
    this.countryCode = 'US',
  });

  /// The first primary artist, or empty string when absent.
  String get primaryArtist =>
      primaryArtists.isNotEmpty ? primaryArtists.first : '';

  /// All artists combined (primary + featured) for display.
  String get displayArtist {
    final all = [...primaryArtists, ...featuredArtists];
    return all.join(', ');
  }

  /// All artists combined for matching (primary + featured).
  List<String> get allArtists => [...primaryArtists, ...featuredArtists];

  /// Whether this recording is official song audio (eligible for catalog
  /// substitution) vs. a specific user-selected video.
  bool get isOfficialAudio =>
      videoType == null ||
      videoType!.isEmpty ||
      videoType == 'MUSIC_VIDEO_TYPE_ATV';

  // ---------------------------------------------------------------------------
  // Factories
  // ---------------------------------------------------------------------------

  /// Creates from a [MediaItem], preserving all available metadata.
  factory RecordingIdentity.fromMediaItem(MediaItem item) {
    final extras = item.extras ?? const {};
    final artists = <String>[];
    final featured = <String>[];

    // Parse artist string into primary/featured.
    final rawArtist = item.artist ?? '';
    _parseArtists(rawArtist, artists, featured);

    // Also check extras['artists'] for structured artist data.
    final extrasArtists = extras['artists'];
    if (extrasArtists is List && artists.isEmpty) {
      for (final a in extrasArtists) {
        final name = a is Map ? a['name']?.toString() : a?.toString();
        if (name != null && name.isNotEmpty && !artists.contains(name)) {
          artists.add(name);
        }
      }
    }

    final title = item.title;
    final album = item.album;

    // Parse track details (e.g. "3/12").
    final trackDetails = (extras['trackDetails'] as String?)?.split('/');
    final trackNumber = int.tryParse(trackDetails?[0] ?? '');

    return RecordingIdentity(
      mediaId: item.id,
      sourceVideoId: extras['sourceVideoId'] as String?,
      title: title,
      primaryArtists: artists,
      featuredArtists: featured,
      album: album,
      albumArtist: extras['albumArtist'] as String?,
      durationMs: item.duration?.inMilliseconds,
      isrc: normalizeIsrc(extras['isrc'] as String?),
      videoType: extras['videoType'] as String?,
      versionType: VersionClassifier.classify(title, album),
      versionLabel: extras['versionLabel'] as String?,
      releaseYear: _parseYear(extras['year']),
      discNumber: extras['discNumber'] is int
          ? extras['discNumber'] as int
          : null,
      trackNumber: trackNumber,
      explicitStatus: extras['explicit'] is bool
          ? extras['explicit'] as bool
          : null,
      originalProvider: extras['originalProvider'] as String?,
      countryCode: (extras['countryCode'] as String?) ?? 'US',
    );
  }

  /// Creates from a [SongQuery], preserving all fields.
  factory RecordingIdentity.fromSongQuery(SongQuery query) {
    final artists = <String>[];
    final featured = <String>[];

    if (query.artists.length == 1) {
      _parseArtists(query.artists.first, artists, featured);
    } else {
      artists.addAll(query.artists);
    }

    return RecordingIdentity(
      mediaId: query.mediaId,
      title: query.title,
      primaryArtists: artists,
      featuredArtists: featured,
      album: query.album,
      albumArtist: query.albumArtist,
      durationMs: query.durationMs,
      isrc: normalizeIsrc(query.isrc),
      videoType: query.videoType,
      versionType: VersionClassifier.classify(query.title, query.album),
      versionLabel: query.versionLabel,
      countryCode: query.countryCode,
    );
  }

  /// Converts to a [SongQuery] without losing data.
  SongQuery toSongQuery() => SongQuery(
        mediaId: mediaId,
        title: title,
        artists: allArtists,
        album: album,
        albumArtist: albumArtist,
        isrc: isrc,
        durationMs: durationMs,
        videoType: videoType,
        versionLabel: versionLabel,
        countryCode: countryCode,
      );

  /// Returns a copy with the given fields replaced.
  RecordingIdentity copyWith({
    String? mediaId,
    String? sourceVideoId,
    String? title,
    List<String>? primaryArtists,
    List<String>? featuredArtists,
    String? album,
    String? albumArtist,
    int? durationMs,
    String? isrc,
    String? videoType,
    VersionType? versionType,
    String? versionLabel,
    int? releaseYear,
    int? discNumber,
    int? trackNumber,
    bool? explicitStatus,
    String? originalProvider,
    String? countryCode,
  }) =>
      RecordingIdentity(
        mediaId: mediaId ?? this.mediaId,
        sourceVideoId: sourceVideoId ?? this.sourceVideoId,
        title: title ?? this.title,
        primaryArtists: primaryArtists ?? this.primaryArtists,
        featuredArtists: featuredArtists ?? this.featuredArtists,
        album: album ?? this.album,
        albumArtist: albumArtist ?? this.albumArtist,
        durationMs: durationMs ?? this.durationMs,
        isrc: isrc ?? this.isrc,
        videoType: videoType ?? this.videoType,
        versionType: versionType ?? this.versionType,
        versionLabel: versionLabel ?? this.versionLabel,
        releaseYear: releaseYear ?? this.releaseYear,
        discNumber: discNumber ?? this.discNumber,
        trackNumber: trackNumber ?? this.trackNumber,
        explicitStatus: explicitStatus ?? this.explicitStatus,
        originalProvider: originalProvider ?? this.originalProvider,
        countryCode: countryCode ?? this.countryCode,
      );

  // ---------------------------------------------------------------------------
  // JSON serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'mediaId': mediaId,
        if (sourceVideoId != null) 'sourceVideoId': sourceVideoId,
        'title': title,
        'primaryArtists': primaryArtists,
        'featuredArtists': featuredArtists,
        if (album != null) 'album': album,
        if (albumArtist != null) 'albumArtist': albumArtist,
        if (durationMs != null) 'durationMs': durationMs,
        if (isrc != null) 'isrc': isrc,
        if (videoType != null) 'videoType': videoType,
        'versionType': versionType.name,
        if (versionLabel != null) 'versionLabel': versionLabel,
        if (releaseYear != null) 'releaseYear': releaseYear,
        if (discNumber != null) 'discNumber': discNumber,
        if (trackNumber != null) 'trackNumber': trackNumber,
        if (explicitStatus != null) 'explicit': explicitStatus,
        if (originalProvider != null) 'originalProvider': originalProvider,
        'countryCode': countryCode,
      };

  factory RecordingIdentity.fromJson(Map<String, dynamic> json) {
    final versionName = json['versionType'] as String?;
    final versionType = versionName != null
        ? VersionType.values.where((v) => v.name == versionName).firstOrNull ??
            VersionType.unknown
        : VersionType.unknown;

    return RecordingIdentity(
      mediaId: (json['mediaId'] as String?) ?? '',
      sourceVideoId: json['sourceVideoId'] as String?,
      title: (json['title'] as String?) ?? '',
      primaryArtists: _stringList(json['primaryArtists']),
      featuredArtists: _stringList(json['featuredArtists']),
      album: json['album'] as String?,
      albumArtist: json['albumArtist'] as String?,
      durationMs: json['durationMs'] as int?,
      isrc: normalizeIsrc(json['isrc'] as String?),
      videoType: json['videoType'] as String?,
      versionType: versionType,
      versionLabel: json['versionLabel'] as String?,
      releaseYear: json['releaseYear'] as int?,
      discNumber: json['discNumber'] as int?,
      trackNumber: json['trackNumber'] as int?,
      explicitStatus: json['explicit'] as bool?,
      originalProvider: json['originalProvider'] as String?,
      countryCode: (json['countryCode'] as String?) ?? 'US',
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static List<String> _stringList(dynamic value) {
    if (value is List) return value.map((e) => '$e').toList();
    return const [];
  }

  static int? _parseYear(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Parses a combined artist string like "Artist feat. Guest & Other"
  /// into primary and featured artist lists.
  static void _parseArtists(
    String raw,
    List<String> primary,
    List<String> featured,
  ) {
    if (raw.isEmpty) return;

    // Split on common featuring patterns.
    final featPatterns = RegExp(
      r'\s+(?:feat\.?|ft\.?|featuring)\s+',
      caseSensitive: false,
    );

    final parts = raw.split(featPatterns);
    if (parts.isEmpty) return;

    // First part is the primary artist(s).
    final primaryPart = parts[0].trim();
    // Split primary by common separators: ", ", " & ", " x ", " and ".
    final primarySplit = primaryPart.split(RegExp(r'\s*[,&]\s*|\s+x\s+'));
    for (final a in primarySplit) {
      final trimmed = a.trim();
      if (trimmed.isNotEmpty && !primary.contains(trimmed)) {
        primary.add(trimmed);
      }
    }

    // Remaining parts are featured.
    for (var i = 1; i < parts.length; i++) {
      final featPart = parts[i].trim();
      final featSplit = featPart.split(RegExp(r'\s*[,&]\s*|\s+x\s+'));
      for (final a in featSplit) {
        final trimmed = a.trim();
        if (trimmed.isNotEmpty && !featured.contains(trimmed)) {
          featured.add(trimmed);
        }
      }
    }
  }

  @override
  String toString() =>
      'RecordingIdentity($mediaId, "$title" by ${displayArtist.isEmpty ? "?" : displayArtist})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingIdentity &&
          mediaId == other.mediaId &&
          title == other.title &&
          isrc == other.isrc;

  @override
  int get hashCode => Object.hash(mediaId, title, isrc);
}
