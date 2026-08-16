/// Structured error codes returned by the resolver API. Raw provider errors
/// are never forwarded to the Flutter client — they are mapped to these.
enum ResolveErrorCode {
  invalidUrl('INVALID_URL'),
  unsupportedUrl('UNSUPPORTED_SPOTIFY_URL'),
  playlistNotFound('PLAYLIST_NOT_FOUND'),
  playlistPrivate('PLAYLIST_PRIVATE'),
  authenticationRequired('AUTHENTICATION_REQUIRED'),
  permissionDenied('PERMISSION_DENIED'),
  providerRateLimited('PROVIDER_RATE_LIMITED'),
  providerUnavailable('PROVIDER_UNAVAILABLE'),
  noMetadataSource('NO_METADATA_SOURCE'),
  networkError('NETWORK_ERROR'),
  internalError('INTERNAL_ERROR'),
  apifyAuth('APIFY_AUTH_ERROR'),
  apifyActorError('APIFY_ACTOR_ERROR'),
  apifyTimeout('APIFY_TIMEOUT'),
  invalidScraperResponse('INVALID_SCRAPER_RESPONSE'),
  playlistEmpty('PLAYLIST_EMPTY');

  final String wire;
  const ResolveErrorCode(this.wire);

  static ResolveErrorCode fromWire(String wire) =>
      values.firstWhere((c) => c.wire == wire,
          orElse: () => ResolveErrorCode.internalError);
}

class ResolveError {
  final ResolveErrorCode code;
  final String message;
  final int? httpStatus;

  const ResolveError(this.code, this.message, {this.httpStatus});

  Map<String, dynamic> toJson() => {
        'code': code.wire,
        'message': message,
      };
}

/// A single normalized track. Provider-specific ids stay source identifiers;
/// nothing here is treated as a permanent canonical identity by the client.
class NormalizedTrack {
  final String sourceTrackId;
  final int position;
  final String title;
  final List<String> artists;
  final String? album;
  final String? albumArtist;
  final int durationMs;
  final String? isrc;
  final String? releaseDate;
  final bool explicit;
  final String? artworkUrl;

  const NormalizedTrack({
    required this.sourceTrackId,
    required this.position,
    required this.title,
    required this.artists,
    this.album,
    this.albumArtist,
    required this.durationMs,
    this.isrc,
    this.releaseDate,
    this.explicit = false,
    this.artworkUrl,
  });

  factory NormalizedTrack.fromJson(Map<String, dynamic> json) =>
      NormalizedTrack(
        sourceTrackId: json['sourceTrackId'] as String? ?? '',
        position: (json['position'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        artists: List<String>.from(json['artists'] ?? const []),
        album: json['album'] as String?,
        albumArtist: json['albumArtist'] as String?,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        isrc: json['isrc'] as String?,
        releaseDate: json['releaseDate'] as String?,
        explicit: json['explicit'] as bool? ?? false,
        artworkUrl: json['artworkUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'sourceTrackId': sourceTrackId,
        'position': position,
        'title': title,
        'artists': artists,
        'album': album,
        'albumArtist': albumArtist,
        'durationMs': durationMs,
        'isrc': isrc,
        'releaseDate': releaseDate,
        'explicit': explicit,
        'artworkUrl': artworkUrl,
      };
}

class NormalizedPlaylist {
  final String id;
  final String name;
  final String? description;
  final String? artworkUrl;
  final int trackCount;

  const NormalizedPlaylist({
    required this.id,
    required this.name,
    this.description,
    this.artworkUrl,
    required this.trackCount,
  });

  factory NormalizedPlaylist.fromJson(Map<String, dynamic> json) =>
      NormalizedPlaylist(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        artworkUrl: json['artworkUrl'] as String?,
        trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'artworkUrl': artworkUrl,
        'trackCount': trackCount,
      };
}

/// The normalized, provider-agnostic resolution result. The Flutter client
/// cannot tell (and does not need to know) which backend source produced it.
class PlaylistResolution {
  final NormalizedPlaylist playlist;
  final List<NormalizedTrack> tracks;

  /// Which backend source supplied the data (e.g. `cache`, `spotify`).
  final String source;

  /// Which method within the source (e.g. `official_api`).
  final String method;

  /// True when served from the backend cache.
  final bool cached;

  final int total;
  final int resolved;
  final int unavailable;
  final List<ResolveWarning> warnings;

  const PlaylistResolution({
    required this.playlist,
    required this.tracks,
    required this.source,
    required this.method,
    this.cached = false,
    required this.total,
    required this.resolved,
    required this.unavailable,
    this.warnings = const [],
  });

  Map<String, dynamic> toJson() => {
        'success': true,
        'source': {'provider': source, 'method': method},
        'playlist': playlist.toJson(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'resolution': {
          'total': total,
          'resolved': resolved,
          'unavailable': unavailable,
        },
        'warnings': warnings.map((w) => w.toJson()).toList(),
        'cached': cached,
      };
}

class ResolveWarning {
  final String code;
  final String message;

  const ResolveWarning(this.code, this.message);

  Map<String, dynamic> toJson() => {'code': code, 'message': message};
}
