import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/song_query.dart';
import 'package:sonara/services/providers/tidal/tidal_api.dart';
import 'package:sonara/services/providers/tidal/tidal_provider.dart';
import 'package:sonara/services/stream_service.dart';

class _FakeTidalApi extends TidalApi {
  _FakeTidalApi({
    this.searchResults = const {},
    this.streamResponses = const {},
  });

  final Map<String, List<Map<String, dynamic>>> searchResults;
  final Map<String, Map<String, dynamic>> streamResponses;
  final List<String> requestedStreams = [];

  @override
  Future<List<Map<String, dynamic>>> searchTracks(String term) async =>
      searchResults[term] ?? const [];

  @override
  Future<Map<String, dynamic>> requestStream(
    String baseUrl,
    String trackId,
    String quality,
  ) async {
    requestedStreams.add('$baseUrl::$trackId::$quality');
    final data = streamResponses['$baseUrl::$trackId::$quality'];
    if (data == null) throw TidalApiException('no stream at $quality');
    return data;
  }
}

Map<String, dynamic> _trackItem({
  required String id,
  required String title,
  required String artist,
  String? album = 'After Hours',
  int? duration = 200,
  String? audioQuality = 'LOSSLESS',
}) =>
    {
      'id': id,
      'title': title,
      'artist': {'name': artist},
      'artists': [
        {'name': artist}
      ],
      'album': {'title': album},
      'isrc': null,
      'duration': duration,
      'audioQuality': audioQuality,
    };

Map<String, dynamic> _streamData({
  required String manifest,
  String manifestMimeType = 'application/dash+xml',
  String audioQuality = 'LOSSLESS',
  Object? sampleRate = 44100,
  Object? bitDepth = 16,
  String? assetPresentation,
  Object? bitRate,
}) =>
    {
      'manifest': manifest,
      'manifestMimeType': manifestMimeType,
      'audioQuality': audioQuality,
      'sampleRate': sampleRate,
      'bitDepth': bitDepth,
      'assetPresentation': assetPresentation,
      'bitRate': bitRate,
    };

const _query = SongQuery(
  mediaId: 'yt-id',
  title: 'Blinding Lights',
  artists: ['The Weeknd'],
  album: 'After Hours',
  durationMs: 200000,
);

const _searchTerm = 'Blinding Lights The Weeknd After Hours';

void main() {
  group('TidalProvider.resolve', () {
    test('matches a track and resolves a DASH manifest URL', () async {
      final api = _FakeTidalApi(
        searchResults: {
          _searchTerm: [
            _trackItem(id: '123', title: 'Blinding Lights', artist: 'The Weeknd'),
          ],
        },
        streamResponses: {
          'https://t.example::123::LOSSLESS': _streamData(
            manifest: 'https://cdn.example/123.mpd',
            sampleRate: 44100,
            bitDepth: 16,
          ),
        },
      );
      final provider = TidalProvider(endpoints: ['https://t.example'], api: api);

      final result = await provider.resolve(_query);

      expect(result.playable, isTrue);
      expect(result.label, 'Tidal FLAC');
      expect(result.mimeType, 'audio/flac');
      expect(result.audioFormats.single.audioCodec, Codec.flac);
      expect(result.audioFormats.single.url, 'https://cdn.example/123.mpd');
      expect(result.sampleRate, 44100);
      expect(result.bitDepth, 16);
    });

    test('uses the best URL of a progressive JSON manifest', () async {
      final api = _FakeTidalApi(
        streamResponses: {
          'https://t.example::987::LOSSLESS': _streamData(
            manifest: base64Encode(
                utf8.encode('{"urls":["https://cdn/a.mp4","https://cdn/b.mp4"]}')),
            manifestMimeType: 'application/json',
            audioQuality: 'HIGH',
          ),
        },
      );
      final provider = TidalProvider(endpoints: ['https://t.example'], api: api);

      final result = await provider.resolve(
        const SongQuery(mediaId: '987', durationMs: 200000),
      );

      expect(result.playable, isTrue);
      expect(result.label, 'Tidal AAC');
      expect(result.audioFormats.single.audioCodec, Codec.mp4a);
      expect(result.audioFormats.single.url, 'https://cdn/b.mp4');
    });

    test('writes a base64 DASH manifest to a temp file for playback', () async {
      const mpd = '<MPD><BaseURL>https://cdn/seg/</BaseURL></MPD>';
      final api = _FakeTidalApi(
        streamResponses: {
          'https://t.example::987::LOSSLESS': _streamData(
            manifest: base64Encode(utf8.encode(mpd)),
            sampleRate: 44100,
            bitDepth: 16,
          ),
        },
      );
      final provider = TidalProvider(endpoints: ['https://t.example'], api: api);

      final result = await provider.resolve(
        const SongQuery(mediaId: '987', durationMs: 200000),
      );

      expect(result.playable, isTrue);
      expect(result.audioFormats.single.url, startsWith('file://'));
      final path = Uri.parse(result.audioFormats.single.url).toFilePath();
      expect(File(path).readAsStringSync(), mpd);
    });

    test('rejects preview assets', () async {
      final api = _FakeTidalApi(
        streamResponses: {
          'https://t.example::987::LOSSLESS': _streamData(
            manifest: 'https://cdn.example/preview.mpd',
            assetPresentation: 'PREVIEW',
          ),
        },
      );
      final provider = TidalProvider(endpoints: ['https://t.example'], api: api);

      final result = await provider.resolve(
        const SongQuery(mediaId: '987', title: 'X', durationMs: 200000),
      );

      expect(result.playable, isFalse);
      expect(result.statusMSG, 'Tidal stream not found for X');
    });

    test('falls down the quality ladder when a quality is unavailable',
        () async {
      final api = _FakeTidalApi(
        streamResponses: {
          'https://t.example::987::LOSSLESS': _streamData(
            manifest: 'https://cdn.example/987.mpd',
            sampleRate: 44100,
            bitDepth: 16,
          ),
        },
      );
      final provider = TidalProvider(
        endpoints: ['https://t.example'],
        quality: 'HI_RES_LOSSLESS',
        api: api,
      );

      final result = await provider.resolve(
        const SongQuery(mediaId: '987', durationMs: 200000),
      );

      expect(result.playable, isTrue);
      expect(result.label, 'Tidal FLAC');
      expect(
        api.requestedStreams,
        [
          'https://t.example::987::HI_RES_LOSSLESS',
          'https://t.example::987::LOSSLESS',
        ],
      );
    });

    test('labels Hi-Res FLAC streams', () async {
      final api = _FakeTidalApi(
        streamResponses: {
          'https://t.example::987::HI_RES_LOSSLESS': _streamData(
            manifest: 'https://cdn.example/987.mpd',
            audioQuality: 'HI_RES_LOSSLESS',
            sampleRate: 192000,
            bitDepth: 24,
          ),
        },
      );
      final provider = TidalProvider(
        endpoints: ['https://t.example'],
        quality: 'HI_RES_LOSSLESS',
        api: api,
      );

      final result = await provider.resolve(
        const SongQuery(mediaId: '987', durationMs: 200000),
      );

      expect(result.playable, isTrue);
      expect(result.label, 'Tidal Hi-Res FLAC');
      expect(result.audioFormats.single.audioCodec, Codec.flac);
    });

    test('reports when no endpoints are configured', () async {
      final provider =
          TidalProvider(endpoints: const [], api: _FakeTidalApi());
      final result = await provider.resolve(_query);
      expect(result.playable, isFalse);
      expect(result.statusMSG, 'Tidal not configured');
    });
  });

  group('TidalProvider.normalizeEndpoints', () {
    test('adds https scheme and trims slashes', () {
      expect(
        TidalProvider.normalizeEndpoints(
            ['tidalres.example', 'https://other.example/']),
        ['https://tidalres.example', 'https://other.example'],
      );
    });
  });
}
