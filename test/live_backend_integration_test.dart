import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/metadata/backend_playlist_provider.dart';
import 'package:sonara/services/metadata/playlist_metadata_provider.dart';

/// End-to-end check against a running Sonara resolver backend.
///
/// Requires `cd backend && dart run bin/server.dart` (or the deployed
/// backend). The test is skipped with a clear message when no backend is
/// reachable, so it never breaks a normal `flutter test` run.
const _realPlaylist =
    'https://open.spotify.com/playlist/2olvvUCFTyyMBe6jrpyRvI?si=88c449d5989d4369';

void main() {
  test('resolves a real public Spotify playlist without any credentials',
      () async {
    // Uses the provider's own runtime URL resolution (dart-define, Hive
    // override, then the built-in default) — exactly what the shipped app
    // does on every launch path.
    final provider = BackendPlaylistProvider();
    final dio = Dio(BaseOptions(
      baseUrl: provider.baseUrl,
      connectTimeout: const Duration(seconds: 25),
      receiveTimeout: const Duration(seconds: 35),
    ));
    try {
      await dio.get('/health');
    } catch (_) {
      markTestSkipped(
          'Backend at ${provider.baseUrl} is not reachable');
      return;
    }

    final result = await provider.fetchPlaylist(Uri.parse(_realPlaylist));

    expect(result.status, PlaylistMetadataStatus.success,
        reason: 'message: ${result.message}');
    expect(result.name, isNotNull);
    expect(result.tracks, isNotEmpty);
    final first = result.tracks.first;
    expect(first.title, isNotEmpty);
    expect(first.artists, isNotEmpty);
    expect(first.durationMs, greaterThan(0));
    // Spotify ids are preserved for downstream matching.
    expect(first.spotifyId, hasLength(22));
  });
}
