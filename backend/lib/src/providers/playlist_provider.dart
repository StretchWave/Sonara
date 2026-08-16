import '../models.dart';

/// Input for a resolution attempt. The `url` is already validated to be a
/// Spotify playlist URL by the time it reaches a provider.
class PlaylistResolveInput {
  final String playlistId;
  final String url;

  const PlaylistResolveInput({required this.playlistId, required this.url});
}

/// A backend source that can turn a validated Spotify playlist id into
/// normalized playlist metadata.
///
/// Implementations must not throw for expected failures: they report
/// [ResolveError] (structured) or return a partial result.
abstract interface class PlaylistMetadataProvider {
  /// Stable id, e.g. `cache`, `spotify`.
  String get id;

  /// True when this provider could resolve the playlist (it may still fail
  /// at runtime — e.g. missing credentials).
  bool canResolve(PlaylistResolveInput input);

  /// Resolves the playlist. Throws [ResolveError] on failure.
  Future<PlaylistResolution> resolve(PlaylistResolveInput input);
}
