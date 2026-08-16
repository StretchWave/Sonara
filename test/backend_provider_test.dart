import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/metadata/backend_playlist_provider.dart';
import 'package:sonara/services/metadata/playlist_metadata_provider.dart';
import 'package:sonara/services/metadata/playlist_metadata_resolver.dart';
import 'package:sonara/services/spotify/spotify_api_client.dart';

import 'helpers/fake_dio_adapter.dart';

const _playlistUrl = 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M';

BackendPlaylistProvider providerWith(FakeDioAdapter adapter) =>
    BackendPlaylistProvider(
      dio: Dio(BaseOptions(baseUrl: 'http://backend.test'))
        ..httpClientAdapter = adapter,
      baseUrl: 'http://backend.test',
    );

Map<String, dynamic> successBody() => {
      'success': true,
      'source': {'provider': 'spotify', 'method': 'official_api'},
      'playlist': {
        'id': '37i9dQZF1DXcBWIGoYBM5M',
        'name': 'Phonks to Download',
        'trackCount': 2,
      },
      'tracks': [
        {
          'sourceTrackId': 't1',
          'position': 0,
          'title': 'Blinding Lights',
          'artists': ['The Weeknd'],
          'album': 'After Hours',
          'albumArtist': 'The Weeknd',
          'durationMs': 200000,
          'isrc': 'USUMV2403154',
          'releaseDate': '2020-03-20',
          'explicit': true,
          'artworkUrl': 'https://i.scdn.co/image/art',
        },
        {
          'sourceTrackId': 't2',
          'position': 1,
          'title': 'Starboy',
          'artists': ['The Weeknd'],
          'album': 'Starboy',
          'durationMs': 230000,
        },
      ],
      'resolution': {'total': 2, 'resolved': 2, 'unavailable': 0},
      'warnings': <Object>[],
      'cached': false,
    };

void main() {
  group('BackendPlaylistProvider', () {
    test('maps a successful backend response to track metadata', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (o) {
        expect(o.path, '/api/playlist/resolve');
        final body = o.data as Map;
        expect(body['url'], _playlistUrl);
        return jsonResponse(successBody());
      };
      final provider = providerWith(adapter);

      final result = await provider.fetchPlaylist(Uri.parse(_playlistUrl));

      expect(result.status, PlaylistMetadataStatus.success);
      expect(result.name, 'Phonks to Download');
      expect(result.tracks, hasLength(2));
      final first = result.tracks.first;
      expect(first.spotifyId, 't1');
      expect(first.title, 'Blinding Lights');
      expect(first.artists, ['The Weeknd']);
      expect(first.album, 'After Hours');
      expect(first.albumArtist, 'The Weeknd');
      expect(first.durationMs, 200000);
      expect(first.isrc, 'USUMV2403154');
      expect(first.releaseDate?.year, 2020);
      expect(first.explicit, isTrue);
      expect(first.artworkUrl, 'https://i.scdn.co/image/art');
    });

    test('maps structured backend errors to statuses', () async {
      Future<PlaylistMetadataStatus> statusFor(
          String code, int httpStatus) async {
        final adapter = FakeDioAdapter();
        adapter.handler = (_) => jsonResponse({
              'success': false,
              'error': {'code': code, 'message': 'x'},
            }, status: httpStatus);
        final provider = providerWith(adapter);
        return (await provider.fetchPlaylist(Uri.parse(_playlistUrl))).status;
      }

      expect(await statusFor('UNSUPPORTED_SPOTIFY_URL', 400),
          PlaylistMetadataStatus.unsupported);
      expect(await statusFor('PLAYLIST_NOT_FOUND', 404),
          PlaylistMetadataStatus.notFound);
      expect(await statusFor('PLAYLIST_PRIVATE', 403),
          PlaylistMetadataStatus.permissionDenied);
      expect(await statusFor('PERMISSION_DENIED', 403),
          PlaylistMetadataStatus.permissionDenied);
      expect(await statusFor('AUTHENTICATION_REQUIRED', 401),
          PlaylistMetadataStatus.authenticationRequired);
      expect(await statusFor('PROVIDER_RATE_LIMITED', 429),
          PlaylistMetadataStatus.rateLimited);
      expect(await statusFor('NO_METADATA_SOURCE', 502),
          PlaylistMetadataStatus.networkError);
      expect(await statusFor('INTERNAL_ERROR', 500),
          PlaylistMetadataStatus.networkError);
      // Apify-backed failures are backend-side and transient: they must
      // never surface as auth-required (the user is not asked to log in).
      expect(await statusFor('APIFY_AUTH_ERROR', 502),
          PlaylistMetadataStatus.networkError);
      expect(await statusFor('APIFY_ACTOR_ERROR', 502),
          PlaylistMetadataStatus.networkError);
      expect(await statusFor('APIFY_TIMEOUT', 503),
          PlaylistMetadataStatus.networkError);
      expect(await statusFor('INVALID_SCRAPER_RESPONSE', 502),
          PlaylistMetadataStatus.networkError);
      expect(await statusFor('PLAYLIST_EMPTY', 404),
          PlaylistMetadataStatus.networkError);
    });

    test('network failures map to networkError', () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => throw DioException.connectionTimeout(
          timeout: const Duration(seconds: 5),
          requestOptions: RequestOptions(path: '/api/playlist/resolve'));
      final provider = providerWith(adapter);

      final result = await provider.fetchPlaylist(Uri.parse(_playlistUrl));
      expect(result.status, PlaylistMetadataStatus.networkError);
      expect(result.message, contains('backend'));
    });

    test('can be explicitly disabled with an empty base URL', () {
      final provider = BackendPlaylistProvider(
        dio: Dio(BaseOptions(baseUrl: '')),
        baseUrl: '',
      );
      expect(provider.canHandle(Uri.parse(_playlistUrl)), isFalse);
    });

    test('defaults to the built-in backend URL when nothing is configured',
        () {
      // No dart-define and no Hive box open: the runtime default applies,
      // so IDE builds that drop dart-defines still reach the resolver.
      expect(BackendPlaylistProvider.resolveBackendUrl(),
          BackendPlaylistProvider.defaultBackendUrl);
      expect(BackendPlaylistProvider.isConfigured, isTrue);
      // An explicit override always wins.
      expect(BackendPlaylistProvider.resolveBackendUrl(override: ''),
          isEmpty);
    });

    test('rejects non-playlist URLs', () {
      final provider = providerWith(FakeDioAdapter());
      expect(provider.canHandle(Uri.parse('https://open.spotify.com/album/abc')),
          isFalse);
    });
  });

  group('resolver chain', () {
    test('backend result satisfies the chain without any Spotify auth',
        () async {
      final adapter = FakeDioAdapter();
      adapter.handler = (_) => jsonResponse(successBody());
      final backend = providerWith(adapter);

      // No session anywhere — the app-side PKCE provider would say
      // authenticationRequired, but the backend result wins.
      final resolver = PlaylistMetadataResolver([
        backend,
        _NoSessionOfficialProvider(),
      ]);

      final result =
          await resolver.resolve(Uri.parse(_playlistUrl));

      expect(result.status, PlaylistMetadataStatus.success);
      expect(result.tracks, hasLength(2));
      expect(result.tracksSource, 'sonara-backend');
      expect(result.authenticationRequired, isFalse);
    });
  });
}

class _NoSessionOfficialProvider implements PlaylistMetadataProvider {
  @override
  String get id => 'spotify-official';

  @override
  String get displayName => 'Spotify account';

  @override
  bool canHandle(Uri url) =>
      SpotifyApiClient.parsePlaylistId(url.toString()) != null;

  @override
  Future<PlaylistMetadataResult> fetchPlaylist(Uri url) async =>
      PlaylistMetadataResult(
        status: PlaylistMetadataStatus.authenticationRequired,
        playlistId: SpotifyApiClient.parsePlaylistId(url.toString()),
        message: 'no session',
      );
}
