import '/services/spotify/spotify_source_track.dart';

/// Outcome of a metadata source, kept distinct so the UI never collapses
/// every failure into "Spotify import failed".
enum PlaylistMetadataStatus {
  /// Full track list (+ metadata) acquired.
  success,

  /// Some metadata acquired (e.g. playlist title/artwork) but not the full
  /// track list.
  partialSuccess,

  /// The provider needs credentials the user has not provided (yet).
  authenticationRequired,

  /// The URL is not something this provider can handle.
  unsupported,

  /// The playlist does not exist (or was deleted).
  notFound,

  /// The source rate-limited the request.
  rateLimited,

  /// Transient network failure / timeout.
  networkError,

  /// The source refused access (private playlist, wrong account, ...).
  permissionDenied,
}

/// Unified result of one metadata acquisition attempt.
class PlaylistMetadataResult {
  final PlaylistMetadataStatus status;
  final String? playlistId;
  final String? name;
  final String? description;
  final String? artworkUrl;
  final String? owner;

  /// The acquired track metadata (may be empty on partial results).
  final List<SpotifySourceTrack> tracks;

  /// Short human-readable message for failures / hints.
  final String? message;

  const PlaylistMetadataResult({
    required this.status,
    this.playlistId,
    this.name,
    this.description,
    this.artworkUrl,
    this.owner,
    this.tracks = const [],
    this.message,
  });

  bool get hasTracks => tracks.isNotEmpty;

  PlaylistMetadataResult copyWith({
    PlaylistMetadataStatus? status,
    String? playlistId,
    String? name,
    String? description,
    String? artworkUrl,
    String? owner,
    List<SpotifySourceTrack>? tracks,
    String? message,
  }) =>
      PlaylistMetadataResult(
        status: status ?? this.status,
        playlistId: playlistId ?? this.playlistId,
        name: name ?? this.name,
        description: description ?? this.description,
        artworkUrl: artworkUrl ?? this.artworkUrl,
        owner: owner ?? this.owner,
        tracks: tracks ?? this.tracks,
        message: message ?? this.message,
      );
}

/// A source that can turn a playlist URL into canonical playlist metadata.
///
/// The migration engine depends on this interface — never on Spotify OAuth
/// directly. Providers are tried in priority order by
/// [PlaylistMetadataResolver] and their results are merged.
abstract interface class PlaylistMetadataProvider {
  /// Stable machine id, e.g. `oembed`, `spotify-official`, `cached`.
  String get id;

  /// Human-readable name for the metadata-sources UI.
  String get displayName;

  /// True when this provider understands the given URL (or can look up the
  /// playlist id from it).
  bool canHandle(Uri url);

  /// Acquires playlist metadata. Must never throw: failures are reported
  /// through [PlaylistMetadataResult.status].
  Future<PlaylistMetadataResult> fetchPlaylist(Uri url);
}
