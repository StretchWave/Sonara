import 'matching/track_candidate.dart';
import 'resolved_stream.dart';
import 'song_query.dart';

/// A streamable music catalog (Qobuz, Tidal, Amazon, YouTube Music, ...).
///
/// Providers never hold user credentials: like MetroFuse, they resolve
/// streams through user-configured resolver instances/endpoints.
abstract class AudioSourceProvider {
  const AudioSourceProvider();

  /// Stable identifier used in settings and match overrides, e.g. "qobuz".
  String get id;

  /// Resolves a playable stream for [query]. Returns a non-playable
  /// [ResolvedStream] with a human-readable [ResolvedStream.statusMSG]
  /// instead of throwing when the track cannot be matched or streamed.
  Future<ResolvedStream> resolve(SongQuery query);

  /// Lists candidate matches in this catalog so the user can manually
  /// correct an automatic match.
  Future<List<TrackCandidate>> searchCandidates(SongQuery query) async =>
      const [];

  /// Drops cached streams/tracks for [mediaId] (e.g. after a re-resolve).
  void invalidate(String mediaId) {}
}
