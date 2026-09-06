import 'audio_source_provider.dart';
import 'matching/track_candidate.dart';
import 'song_query.dart';
import 'stream_route_config.dart';
import 'stream_router.dart';

/// One provider's candidate list for the manual match-correction dialog.
class ProviderCandidateGroup {
  const ProviderCandidateGroup({
    required this.providerId,
    required this.displayName,
    required this.candidates,
  });

  final String providerId;

  final String displayName;

  final List<TrackCandidate> candidates;
}

/// Collects manual-match candidates from every configured catalog provider.
///
/// Pass [router] to inject a custom provider chain (used by tests); when
/// omitted, the router is built from the current settings (Hive).
Future<List<ProviderCandidateGroup>> collectCorrectionCandidates(
  SongQuery query, {
  StreamRouter? router,
}) async {
  final resolved =
      router ?? StreamRouter.build(StreamRouteConfig.fromSettings());
  final groups = <ProviderCandidateGroup>[];
  for (final provider in resolved.providers) {
    final displayName = _displayName(provider);
    if (displayName == null) continue;
    List<TrackCandidate> candidates;
    try {
      candidates = await provider.searchCandidates(query);
    } catch (_) {
      // A failing resolver shouldn't block the other providers.
      candidates = const [];
    }
    groups.add(ProviderCandidateGroup(
      providerId: provider.id,
      displayName: displayName,
      candidates: candidates,
    ));
  }
  return groups;
}

String? _displayName(AudioSourceProvider provider) {
  final pid = provider.typedProviderId;
  if (pid.isCatalogProvider) {
    return pid.displayName;
  }
  return null;
}
