import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/qobuz/qobuz_api.dart';
import 'package:sonara/services/providers/qobuz/qobuz_provider.dart';
import 'package:sonara/services/providers/song_query.dart';
import 'package:sonara/services/stream_service.dart';

class _FakeQobuzApi extends QobuzApi {
  _FakeQobuzApi({
    this.searchResults = const {},
    this.streamResponses = const {},
    this.contentLengths = const {},
  });

  final Map<String, List<Map<String, dynamic>>> searchResults;
  final Map<String, Map<String, dynamic>> streamResponses;
  final Map<String, int?> contentLengths;
  final List<String> requestedStreams = [];

  @override
  Future<List<Map<String, dynamic>>> searchTracks(
    String baseUrl,
    String term,
    String country,
  ) async =>
      searchResults[term] ?? const [];

  @override
  Future<Map<String, dynamic>> requestStream(
    String baseUrl,
    String trackId,
    int quality,
  ) async {
    requestedStreams.add('$baseUrl::$trackId::$quality');
    final data = streamResponses['$baseUrl::$trackId::$quality'];
    if (data == null) {
      throw QobuzApiException('no stream at quality $quality');
    }
    return data;
  }

  @override
  Future<int?> fetchContentLength(String url) async => contentLengths[url];
}

Map<String, dynamic> _trackItem({
  required String id,
  required String title,
  required String artist,
  String? album = 'After Hours',
  int? duration = 200,
  String? isrc,
  bool hires = false,
}) =>
    {
      'id': id,
      'title': title,
      'version': null,
      'downloadable': true,
      'streamable': true,
      'isrc': isrc,
      'duration': duration,
      'hires': hires,
      'maximum_bit_depth': hires ? 24 : 16,
      'maximum_sampling_rate': hires ? 96.0 : 44.1,
      'performer': {'name': artist},
      'album': {'title': album, 'artist': {'name': artist}},
    };

Map<String, dynamic> _streamData({
  required String url,
  int formatId = 6,
  int? bitDepth = 16,
  double? samplingRate = 44.1,
  String? mimeType,
}) =>
    {
      'url': url,
      'format_id': formatId,
      'bit_depth': bitDepth,
      'sampling_rate': samplingRate,
      'mime_type': mimeType ??
          (formatId == 5 ? 'audio/mpeg' : 'audio/flac'),
      'average_bitrate': formatId == 5 ? 320 : 900,
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
  group('QobuzProvider.resolve', () {
    test('matches a track and resolves it to a FLAC stream', () async {
      final api = _FakeQobuzApi(
        searchResults: {
          _searchTerm: [
            _trackItem(id: '42', title: 'Blinding Lights', artist: 'The Weeknd'),
          ],
        },
        streamResponses: {
          'https://kq.example::42::6':
              _streamData(url: 'https://cdn/42.flac', formatId: 6),
        },
        contentLengths: {'https://cdn/42.flac': 22500000},
      );
      final provider =
          QobuzProvider(instances: ['https://kq.example'], api: api);

      final result = await provider.resolve(_query);

      expect(result.playable, isTrue);
      expect(result.label, 'Qobuz CD FLAC 16-bit/44.1 kHz');
      expect(result.mimeType, 'audio/flac');
      expect(result.audioFormats.single.audioCodec, Codec.flac);
      expect(result.audioFormats.single.url, 'https://cdn/42.flac');
      expect(result.audioFormats.single.bitrate, 900000);
    });

    test('uses a direct Qobuz track id without searching', () async {
      final api = _FakeQobuzApi(
        streamResponses: {
          'https://kq.example::123456::27':
              _streamData(url: 'https://cdn/123456.flac', formatId: 27, bitDepth: 24, samplingRate: 192.0),
        },
      );
      final provider =
          QobuzProvider(instances: ['https://kq.example'], api: api);

      final result = await provider.resolve(
        const SongQuery(mediaId: '123456', title: 'X', durationMs: 200000),
      );

      expect(result.playable, isTrue);
      expect(result.label, 'Qobuz Hi-Res FLAC 24-bit/192 kHz');
      expect(api.requestedStreams.single, 'https://kq.example::123456::27');
    });

    test('applies a remembered match override', () async {
      final api = _FakeQobuzApi(
        streamResponses: {
          'https://kq.example::999::6':
              _streamData(url: 'https://cdn/999.flac', formatId: 6),
        },
      );
      final provider = QobuzProvider(
        instances: ['https://kq.example'],
        matchOverrides: {'qobuz::yt-id': '999'},
        api: api,
      );

      final result = await provider.resolve(_query);

      expect(result.playable, isTrue);
      expect(api.requestedStreams, contains('https://kq.example::999::6'));
    });

    test('falls down the quality ladder when a quality is unavailable',
        () async {
      final api = _FakeQobuzApi(
        streamResponses: {
          'https://kq.example::42::6':
              _streamData(url: 'https://cdn/42.flac', formatId: 6),
        },
      );
      final provider = QobuzProvider(
        instances: ['https://kq.example'],
        qualityCode: 27,
        api: api,
      );

      final result = await provider.resolve(
        const SongQuery(mediaId: '42', durationMs: 200000),
      );

      expect(result.playable, isTrue);
      expect(result.audioFormats.single.itag, 6);
      expect(api.requestedStreams,
          ['https://kq.example::42::27', 'https://kq.example::42::7', 'https://kq.example::42::6']);
    });

    test('rejects preview streams by estimated bitrate', () async {
      final api = _FakeQobuzApi(
        streamResponses: {
          'https://kq.example::42::6':
              _streamData(url: 'https://cdn/42.flac', formatId: 6),
        },
        contentLengths: {'https://cdn/42.flac': 2000000}, // ~80 kbps
      );
      final provider =
          QobuzProvider(instances: ['https://kq.example'], api: api);

      final result = await provider.resolve(
        const SongQuery(mediaId: '42', durationMs: 200000),
      );

      expect(result.playable, isFalse);
      expect(result.statusMSG, 'Qobuz stream not found for ');
    });

    test('resolves MP3 quality with a label and codec', () async {
      final api = _FakeQobuzApi(
        streamResponses: {
          'https://kq.example::42::5':
              _streamData(url: 'https://cdn/42.mp3', formatId: 5),
        },
      );
      final provider = QobuzProvider(
        instances: ['https://kq.example'],
        qualityCode: 5,
        api: api,
      );

      final result = await provider.resolve(
        const SongQuery(mediaId: '42', durationMs: 200000),
      );

      expect(result.playable, isTrue);
      expect(result.label, 'Qobuz MP3');
      expect(result.audioFormats.single.audioCodec, Codec.mp3);
      expect(result.audioFormats.single.bitrate, 320000);
    });

    test('reports when no instances are configured', () async {
      final provider = QobuzProvider(instances: const [], api: _FakeQobuzApi());
      final result = await provider.resolve(_query);
      expect(result.playable, isFalse);
      expect(result.statusMSG, 'Qobuz not configured');
    });

    test('reports when no match is found', () async {
      final provider = QobuzProvider(
        instances: ['https://kq.example'],
        api: _FakeQobuzApi(),
      );
      final result = await provider.resolve(_query);
      expect(result.playable, isFalse);
      expect(result.statusMSG, 'Qobuz match not found for Blinding Lights');
    });
  });

  group('QobuzProvider.normalizeInstances', () {
    test('adds https scheme and trims slashes', () {
      expect(
        QobuzProvider.normalizeInstances(
            ['kq.example.com', 'https://other.example/']),
        ['https://kq.example.com', 'https://other.example'],
      );
    });

    test('drops invalid entries and dedupes', () {
      expect(
        QobuzProvider.normalizeInstances(
            ['https://a.example', 'https://a.example', 'not a url']),
        ['https://a.example'],
      );
    });
  });
}
