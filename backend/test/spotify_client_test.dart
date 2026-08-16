import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sonara_backend/src/models.dart';
import 'package:sonara_backend/src/spotify_client.dart';
import 'package:test/test.dart';

/// Fake adapter serving canned responses and counting requests.
class FakeAdapter implements HttpClientAdapter {
  FutureOr<ResponseBody> Function(RequestOptions options)? handler;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requestCount++;
    final h = handler;
    if (h == null) return ResponseBody.fromString('{}', 500);
    return h(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(Object body, {int status = 200}) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

SpotifyClient clientWith(FakeAdapter adapter, {String? id, String? secret}) =>
    SpotifyClient(
      dio: Dio(BaseOptions())..httpClientAdapter = adapter,
      clientId: id ?? 'cid',
      clientSecret: secret ?? 'csecret',
    );

Map<String, dynamic> trackJson(String id, String title,
        {int? durationMs, String? isrc, bool explicit = false}) =>
    {
      'track': {
        'id': id,
        'name': title,
        'artists': [
          {'name': 'The Weeknd'}
        ],
        'album': {
          'name': 'After Hours',
          'artists': [
            {'name': 'The Weeknd'}
          ],
          'release_date': '2020-03-20',
          'images': [
            {'url': 'https://i.scdn.co/image/small'},
            {'url': 'https://i.scdn.co/image/large'},
          ],
        },
        'duration_ms': durationMs ?? 200000,
        'track_number': 1,
        'explicit': explicit,
        'external_ids': {'isrc': isrc},
      },
    };

void main() {
  group('token management', () {
    test('fetches a token once and reuses it within the expiry window',
        () async {
      final adapter = FakeAdapter();
      var tokenCalls = 0;
      adapter.handler = (o) {
        if (o.path.contains('api/token')) {
          tokenCalls++;
          return json({'access_token': 'tok-1', 'expires_in': 3600});
        }
        return json({'tracks': {'total': 1, 'next': null, 'items': [
          trackJson('t1', 'Blinding Lights'),
        ]}});
      };
      final client = clientWith(adapter);

      await client.fetchPlaylistTracks('p1');
      await client.fetchPlaylistTracks('p1');

      expect(tokenCalls, 1);
      expect(adapter.requestCount, 3); // 1 token + 2 playlist fetches
    });

    test('throws SpotifyNotConfigured without credentials', () async {
      final client = SpotifyClient(dio: Dio(BaseOptions()));
      expect(client.isConfigured, isFalse);
      await expectLater(client.fetchPlaylistTracks('p1'),
          throwsA(isA<SpotifyNotConfigured>()));
    });
  });

  group('fetchPlaylistTracks', () {
    test('normalizes tracks and follows pagination', () async {
      final adapter = FakeAdapter();
      adapter.handler = (o) {
        if (o.path.contains('api/token')) {
          return json({'access_token': 'tok', 'expires_in': 3600});
        }
        if (o.path.contains('next-page')) {
          return json({'items': [trackJson('t3', 'Save Your Tears')]});
        }
        return json({
          'tracks': {
            'total': 3,
            'next': 'https://api.spotify.com/v1/next-page',
            'items': [
              trackJson('t1', 'Blinding Lights',
                  durationMs: 200000, isrc: 'USUMV2403154'),
              null, // unavailable track
            ],
          }
        });
      };
      final client = clientWith(adapter);

      final tracks = await client.fetchPlaylistTracks('p1');

      expect(tracks, hasLength(3));
      expect(tracks[0].sourceTrackId, 't1');
      expect(tracks[0].position, 0);
      expect(tracks[0].title, 'Blinding Lights');
      expect(tracks[0].artists, ['The Weeknd']);
      expect(tracks[0].album, 'After Hours');
      expect(tracks[0].albumArtist, 'The Weeknd');
      expect(tracks[0].durationMs, 200000);
      expect(tracks[0].isrc, 'USUMV2403154');
      expect(tracks[0].releaseDate, '2020-03-20');
      expect(tracks[0].artworkUrl, 'https://i.scdn.co/image/large');
      // Unavailable items are represented, not fatal.
      expect(tracks[1].sourceTrackId, '');
      expect(tracks[1].title, '');
      expect(tracks[2].position, 2);
    });

    test('maps 403/404/429 to structured errors', () async {
      Future<ResolveError> errorFor(int status) async {
        final adapter = FakeAdapter();
        adapter.handler = (o) =>
            o.path.contains('api/token')
                ? json({'access_token': 'tok', 'expires_in': 3600})
                : json({}, status: status);
        final client = clientWith(adapter);
        try {
          await client.fetchPlaylistTracks('p1');
          fail('expected an error');
        } on ResolveError catch (e) {
          return e;
        }
      }

      expect((await errorFor(403)).code, ResolveErrorCode.permissionDenied);
      expect((await errorFor(404)).code, ResolveErrorCode.playlistNotFound);
      expect((await errorFor(429)).code, ResolveErrorCode.providerRateLimited);
    });

    test('rejects bad credentials', () async {
      final adapter = FakeAdapter();
      adapter.handler = (_) => json({}, status: 400);
      final client = clientWith(adapter);

      await expectLater(
        client.fetchPlaylistTracks('p1'),
        throwsA(isA<ResolveError>()
            .having((e) => e.code, 'code', ResolveErrorCode.authenticationRequired)),
      );
    });
  });
}
