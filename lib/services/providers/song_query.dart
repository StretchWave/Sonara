import 'package:audio_service/audio_service.dart' show MediaItem;

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

  final String? isrc;

  final int? durationMs;

  /// ISO 3166-1 alpha-2 country code used by some catalogs for
  /// regional availability.
  final String countryCode;

  const SongQuery({
    required this.mediaId,
    this.title = '',
    this.artists = const [],
    this.album,
    this.isrc,
    this.durationMs,
    this.countryCode = 'US',
  });

  factory SongQuery.fromMediaItem(
    MediaItem song, {
    String countryCode = 'US',
  }) =>
      SongQuery(
        mediaId: song.id,
        title: song.title,
        artists: [if (song.artist != null) song.artist!],
        album: song.album,
        durationMs: song.duration?.inMilliseconds,
        countryCode: countryCode,
      );

  factory SongQuery.fromJson(Map<String, dynamic> json) => SongQuery(
        mediaId: (json['mediaId'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        artists: (json['artists'] as List?)?.map((e) => '$e').toList() ??
            const [],
        album: json['album'] as String?,
        isrc: json['isrc'] as String?,
        durationMs: json['durationMs'] is int
            ? json['durationMs'] as int
            : null,
        countryCode: (json['countryCode'] as String?) ?? 'US',
      );

  Map<String, dynamic> toJson() => {
        'mediaId': mediaId,
        'title': title,
        'artists': artists,
        'album': album,
        'isrc': isrc,
        'durationMs': durationMs,
        'countryCode': countryCode,
      };
}
