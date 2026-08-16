import 'package:audio_service/audio_service.dart';

import '/services/music_service.dart';
import 'spotify_source_track.dart';
import 'track_matcher.dart';

/// Raised when a provider search fails (network, throttling, ...).
class ProviderSearchException implements Exception {
  final String providerName;
  final Object? cause;
  ProviderSearchException(this.providerName, [this.cause]);
  @override
  String toString() =>
      '$providerName search failed${cause != null ? ': $cause' : ''}';
}

/// Search adapter for a single music provider.
abstract class TrackResolver {
  MusicProvider get provider;

  /// Searches the provider for songs matching [query] and returns the raw
  /// candidate tracks (not yet scored).
  Future<List<MediaItem>> searchSongs(String query, {int limit = 10});
}

/// YouTube Music resolver backed by the app's InnerTube client.
class YoutubeMusicTrackResolver implements TrackResolver {
  final MusicServices musicServices;

  YoutubeMusicTrackResolver(this.musicServices);

  @override
  MusicProvider get provider => MusicProvider.youtubeMusic;

  @override
  Future<List<MediaItem>> searchSongs(String query, {int limit = 10}) async {
    try {
      final result = await musicServices.search(query,
          filter: 'songs', limit: limit);
      return List<MediaItem>.from(result['Songs'] ?? const []);
    } on Exception catch (e) {
      throw ProviderSearchException(provider.displayName, e);
    }
  }
}

/// Result of resolving a single source track across providers.
class ResolveOutcome {
  final List<TrackCandidate> candidates;
  final TrackCandidate? best;

  const ResolveOutcome({required this.candidates, this.best});
}

/// Resolves Spotify tracks against the configured providers.
///
/// Uses the strategy list from [generateSearchQueries]: the first strategy
/// that yields a high-confidence match stops further provider requests, so a
/// confident match never triggers unnecessary API calls.
class ProviderTrackResolver {
  final List<TrackResolver> _resolvers;

  ProviderTrackResolver(this._resolvers);

  /// Scored candidates from every provider, deduplicated by track id and
  /// sorted by score (then provider preference), best first.
  Future<ResolveOutcome> resolve(
    SpotifySourceTrack source, {
    int maxCandidates = 10,
  }) async {
    final queries = generateSearchQueries(source);
    final all = <TrackCandidate>[];
    final seenIds = <String>{};

    for (final query in queries) {
      final candidates = await _searchAllProviders(source, query);
      for (final c in candidates) {
        if (seenIds.add(c.track.id)) {
          all.add(c);
        }
      }
      // Stop as soon as one strategy yields a high-confidence match.
      if (candidates.isNotEmpty && candidates.first.confidence == MatchConfidence.high) {
        break;
      }
    }

    all.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final ai = providerPriority.indexOf(a.provider);
      final bi = providerPriority.indexOf(b.provider);
      return ai.compareTo(bi);
    });

    final top = all.take(maxCandidates).toList();
    return ResolveOutcome(
      candidates: top,
      best: top.isEmpty ? null : top.first,
    );
  }

  Future<List<TrackCandidate>> _searchAllProviders(
      SpotifySourceTrack source, String query) async {
    final results = <TrackCandidate>[];
    for (final resolver in _resolvers) {
      try {
        final tracks = await resolver.searchSongs(query);
        for (final track in tracks) {
          final score = scoreTrack(source, track);
          results.add(TrackCandidate(
            provider: resolver.provider,
            track: track,
            score: score,
            confidence: MatchConfidence.fromScore(score),
          ));
        }
      } on ProviderSearchException {
        // A failing provider must not abort resolution — other providers
        // (and other strategies) still get a chance.
        continue;
      }
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }
}
