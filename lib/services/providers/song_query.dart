import 'package:audio_service/audio_service.dart' show MediaItem;

import 'matching/isrc.dart';

/// Everything a provider needs to locate a track in its own catalog.
///
/// Built from a [MediaItem] (or a bare media id) in the main isolate and
/// passed to providers — including inside background isolates, so keep it
/// free of platform channels and service locator dependencies.
class SongQuery {
  final String mediaId;

  final String title;

  final List<String> artists;

  final String? album;

  /// Album artist, when distinct from the track artist.
  final String? albumArtist;

  final String? isrc;

  final int? durationMs;

  /// YouTube video type (e.g. `MUSIC_VIDEO_TYPE_ATV`). Preserved so
  /// providers can respect the user's exact selection (cover, live, etc.).
  final String? videoType;

  /// Raw version label from metadata (e.g. "Radio Edit", "Deluxe").
  final String? versionLabel;

  /// ISO 3166-1 alpha-2 country code used by some catalogs for
  /// regional availability.
  final String countryCode;

  const SongQuery({
    required this.mediaId,
    this.title = '',
    this.artists = const [],
    this.album,
    this.albumArtist,
    this.isrc,
    this.durationMs,
    this.videoType,
    this.versionLabel,
    this.countryCode = 'US',
  });

  /// Creates a [SongQuery] from a [MediaItem], preserving ISRC, videoType,
  /// and all other available metadata from [MediaItem.extras].
  factory SongQuery.fromMediaItem(
    MediaItem song, {
    String countryCode = 'US',
  }) {
    final extras = song.extras ?? const {};
    return SongQuery(
      mediaId: song.id,
      title: song.title,
      artists: [if (song.artist != null) song.artist!],
      album: song.album,
      albumArtist: extras['albumArtist'] as String?,
      // FIX: Read ISRC from extras — was silently dropped before.
      isrc: normalizeIsrc(extras['isrc'] as String?),
      durationMs: song.duration?.inMilliseconds,
      // FIX: Preserve videoType — was silently dropped before.
      videoType: extras['videoType'] as String?,
      versionLabel: extras['versionLabel'] as String?,
      countryCode: countryCode,
    );
  }

  factory SongQuery.fromJson(Map<String, dynamic> json) => SongQuery(
        mediaId: (json['mediaId'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        artists: (json['artists'] as List?)?.map((e) => '$e').toList() ??
            const [],
        album: json['album'] as String?,
        albumArtist: json['albumArtist'] as String?,
        isrc: json['isrc'] as String?,
        durationMs: json['durationMs'] is int
            ? json['durationMs'] as int
            : null,
        videoType: json['videoType'] as String?,
        versionLabel: json['versionLabel'] as String?,
        countryCode: (json['countryCode'] as String?) ?? 'US',
      );

  Map<String, dynamic> toJson() => {
        'mediaId': mediaId,
        'title': title,
        'artists': artists,
        if (album != null) 'album': album,
        if (albumArtist != null) 'albumArtist': albumArtist,
        if (isrc != null) 'isrc': isrc,
        if (durationMs != null) 'durationMs': durationMs,
        if (videoType != null) 'videoType': videoType,
        if (versionLabel != null) 'versionLabel': versionLabel,
        'countryCode': countryCode,
      };

  /// Returns a copy with the given fields replaced.
  SongQuery copyWith({
    String? mediaId,
    String? title,
    List<String>? artists,
    String? album,
    String? albumArtist,
    String? isrc,
    int? durationMs,
    String? videoType,
    String? versionLabel,
    String? countryCode,
  }) =>
      SongQuery(
        mediaId: mediaId ?? this.mediaId,
        title: title ?? this.title,
        artists: artists ?? this.artists,
        album: album ?? this.album,
        albumArtist: albumArtist ?? this.albumArtist,
        isrc: isrc ?? this.isrc,
        durationMs: durationMs ?? this.durationMs,
        videoType: videoType ?? this.videoType,
        versionLabel: versionLabel ?? this.versionLabel,
        countryCode: countryCode ?? this.countryCode,
      );
}
