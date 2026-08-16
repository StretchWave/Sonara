/// Provider-independent representation of a Spotify track.
///
/// Kept deliberately free of any provider-specific playback details so the
/// migration layer can match it against any supported music provider.
class SpotifySourceTrack {
  final String spotifyId;
  final String title;
  final List<String> artists;
  final String? album;
  final String? albumArtist;
  final int durationMs;
  final String? isrc;
  final DateTime? releaseDate;
  final bool explicit;
  final int? trackNumber;
  final String? artworkUrl;

  const SpotifySourceTrack({
    required this.spotifyId,
    required this.title,
    required this.artists,
    this.album,
    this.albumArtist,
    this.durationMs = 0,
    this.isrc,
    this.releaseDate,
    this.explicit = false,
    this.trackNumber,
    this.artworkUrl,
  });

  /// Copy with optional field overrides (used by enrichment — e.g. an ISRC
  /// discovered via MusicBrainz).
  SpotifySourceTrack copyWith({
    String? spotifyId,
    String? title,
    List<String>? artists,
    String? album,
    String? albumArtist,
    int? durationMs,
    String? isrc,
    DateTime? releaseDate,
    bool? explicit,
    int? trackNumber,
    String? artworkUrl,
  }) =>
      SpotifySourceTrack(
        spotifyId: spotifyId ?? this.spotifyId,
        title: title ?? this.title,
        artists: artists ?? this.artists,
        album: album ?? this.album,
        albumArtist: albumArtist ?? this.albumArtist,
        durationMs: durationMs ?? this.durationMs,
        isrc: isrc ?? this.isrc,
        releaseDate: releaseDate ?? this.releaseDate,
        explicit: explicit ?? this.explicit,
        trackNumber: trackNumber ?? this.trackNumber,
        artworkUrl: artworkUrl ?? this.artworkUrl,
      );

  factory SpotifySourceTrack.fromJson(Map<dynamic, dynamic> json) =>
      SpotifySourceTrack(
        spotifyId: json['spotifyId'] as String,
        title: json['title'] as String,
        artists: List<String>.from(json['artists'] ?? const []),
        album: json['album'] as String?,
        albumArtist: json['albumArtist'] as String?,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        isrc: json['isrc'] as String?,
        releaseDate: json['releaseDate'] != null
            ? DateTime.tryParse(json['releaseDate'] as String)
            : null,
        explicit: json['explicit'] as bool? ?? false,
        trackNumber: (json['trackNumber'] as num?)?.toInt(),
        artworkUrl: json['artworkUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'spotifyId': spotifyId,
        'title': title,
        'artists': artists,
        'album': album,
        'albumArtist': albumArtist,
        'durationMs': durationMs,
        'isrc': isrc,
        'releaseDate': releaseDate?.toIso8601String(),
        'explicit': explicit,
        'trackNumber': trackNumber,
        'artworkUrl': artworkUrl,
      };
}
