import 'matching/track_candidate.dart';
import 'models/match_decision.dart';
import 'models/provider_capabilities.dart';
import 'models/provider_error.dart';
import 'models/provider_id.dart';
import 'models/provider_result.dart';
import 'resolved_stream.dart';
import 'song_query.dart';

/// A streamable music catalog (Qobuz, Tidal, Amazon, YouTube Music, ...).
///
/// Providers never hold user credentials: like MetroFuse, they resolve
/// streams through user-configured resolver instances/endpoints.
abstract class AudioSourceProvider {
  const AudioSourceProvider();

  /// Stable string identifier used in settings and match overrides, e.g. "qobuz".
  String get id;

  /// Strongly typed identifier for this provider.
  ProviderId get typedProviderId =>
      ProviderId.fromStableId(id) ?? ProviderId.youtubeMusic;

  /// The capabilities declared by this provider.
  ProviderCapabilities get capabilities =>
      ProviderCapabilities.forProvider(typedProviderId);

  /// Resolves a playable stream for [query]. Returns a non-playable
  /// [ResolvedStream] with a human-readable [ResolvedStream.statusMSG]
  /// instead of throwing when the track cannot be matched or streamed.
  Future<ResolvedStream> resolve(SongQuery query);

  /// Resolves [query] and returns a structured [ProviderResult] containing
  /// the stream, match decision, latency metrics, and any error details.
  Future<ProviderResult> resolveResult(SongQuery query) async {
    final sw = Stopwatch()..start();
    try {
      final stream = await resolve(query);
      sw.stop();
      final withId = stream.withProviderId(id);
      if (withId.playable) {
        return ProviderResult.success(
          providerId: id,
          stream: withId,
          matchDecision: const MatchDecision(
            accepted: true,
            verificationLevel: VerificationLevel.likely,
          ),
          latencyMs: sw.elapsedMilliseconds,
        );
      }
      return ProviderResult.rejected(
        providerId: id,
        matchDecision: MatchDecision.rejected(
          withId.statusMSG.isNotEmpty ? withId.statusMSG : 'Stream not playable',
        ),
        latencyMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      sw.stop();
      return ProviderResult.failure(
        providerId: id,
        error: ProviderError.fromException(id, e),
        latencyMs: sw.elapsedMilliseconds,
      );
    }
  }

  /// Lists candidate matches in this catalog so the user can manually
  /// correct an automatic match.
  Future<List<TrackCandidate>> searchCandidates(SongQuery query) async =>
      const [];

  /// Drops cached streams/tracks for [mediaId] (e.g. after a re-resolve).
  void invalidate(String mediaId) {}
}
