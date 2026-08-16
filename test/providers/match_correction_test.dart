import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/match_correction.dart';
import 'package:sonara/services/providers/qobuz/qobuz_api.dart';
import 'package:sonara/services/providers/qobuz/qobuz_provider.dart';
import 'package:sonara/services/providers/song_query.dart';
import 'package:sonara/services/providers/stream_router.dart';
import 'package:sonara/services/providers/tidal/tidal_api.dart';
import 'package:sonara/services/providers/tidal/tidal_provider.dart';

class _FakeQobuzApi extends QobuzApi {
  _FakeQobuzApi({this.searchResults = const {}, this.throwingTerms = const {}});

  final Map<String, List<Map<String, dynamic>>> searchResults;
  final Set<String> throwingTerms;

  @override
  Future<List<Map<String, dynamic>>> searchTracks(
    String baseUrl,
    String term,
    String country,
  ) async {
    if (throwingTerms.contains(term)) throw Exception('resolver down');
    return searchResults[term] ?? const [];
  }
}

class _FakeTidalApi extends TidalApi {
  _FakeTidalApi({this.searchResults = const {}});

  final Map<String, List<Map<String, dynamic>>> searchResults;

  @override
  Future<List<Map<String, dynamic>>> searchTracks(String term) async =>
      searchResults[term] ?? const [];
}

Map<String, dynamic> _qobuzItem({
  required String id,
  required String title,
  required String artist,
  bool hires = false,
}) =>
    {
      'id': id,
      'title': title,
      'version': null,
      'downloadable': true,
      'streamable': true,
      'hires': hires,
      'maximum_bit_depth': hires ? 24 : 16,
      'maximum_sampling_rate': hires ? 96.0 : 44.1,
      'performer': {'name': artist},
      'album': {'title': 'After Hours', 'artist': {'name': artist}},
    };

Map<String, dynamic> _tidalItem({
  required String id,
  required String title,
  required String artist,
  String audioQuality = 'LOSSLESS',
}) =>
    {
      'id': id,
      'title': title,
      'artist': {'name': artist},
      'artists': [
        {'name': artist}
      ],
      'album': {'title': 'After Hours'},
      'duration': 200,
      'audioQuality': audioQuality,
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
  group('collectCorrectionCandidates', () {
    test('groups candidates from Qobuz and Tidal in order', () async {
      final router = StreamRouter(providers: [
        QobuzProvider(
          instances: ['https://kq.example'],
          api: _FakeQobuzApi(searchResults: {
            _searchTerm: [
              _qobuzItem(id: '42', title: 'Blinding Lights', artist: 'The Weeknd'),
            ],
          }),
        ),
        TidalProvider(
          endpoints: ['https://t.example'],
          api: _FakeTidalApi(searchResults: {
            _searchTerm: [
              _tidalItem(id: '123', title: 'Blinding Lights', artist: 'The Weeknd'),
            ],
          }),
        ),
      ]);

      final groups = await collectCorrectionCandidates(_query, router: router);

      expect(groups.map((g) => g.displayName), ['Qobuz', 'Tidal']);
      expect(groups[0].candidates.single.trackId, '42');
      expect(groups[0].candidates.single.qualityLabel, 'FLAC');
      expect(groups[1].candidates.single.trackId, '123');
    });

    test('carries quality labels for Hi-Res and AAC candidates', () async {
      final router = StreamRouter(providers: [
        QobuzProvider(
          instances: ['https://kq.example'],
          api: _FakeQobuzApi(searchResults: {
            _searchTerm: [
              _qobuzItem(
                  id: '42', title: 'Blinding Lights', artist: 'The Weeknd', hires: true),
            ],
          }),
        ),
        TidalProvider(
          endpoints: ['https://t.example'],
          api: _FakeTidalApi(searchResults: {
            _searchTerm: [
              _tidalItem(
                  id: '123',
                  title: 'Blinding Lights',
                  artist: 'The Weeknd',
                  audioQuality: 'HIGH'),
            ],
          }),
        ),
      ]);

      final groups = await collectCorrectionCandidates(_query, router: router);

      expect(groups[0].candidates.single.qualityLabel, 'Hi-Res FLAC');
      expect(groups[1].candidates.single.qualityLabel, 'AAC');
    });

    test('keeps a provider group when a resolver throws', () async {
      final router = StreamRouter(providers: [
        QobuzProvider(
          instances: ['https://kq.example'],
          api: _FakeQobuzApi(throwingTerms: {_searchTerm}),
        ),
        TidalProvider(
          endpoints: ['https://t.example'],
          api: _FakeTidalApi(searchResults: {
            _searchTerm: [
              _tidalItem(id: '123', title: 'Blinding Lights', artist: 'The Weeknd'),
            ],
          }),
        ),
      ]);

      final groups = await collectCorrectionCandidates(_query, router: router);

      expect(groups, hasLength(2));
      expect(groups[0].candidates, isEmpty);
      expect(groups[1].candidates, hasLength(1));
    });

    test('returns empty when no candidates are found anywhere', () async {
      final router = StreamRouter(providers: [
        QobuzProvider(instances: ['https://kq.example'], api: _FakeQobuzApi()),
        TidalProvider(endpoints: ['https://t.example'], api: _FakeTidalApi()),
      ]);

      final groups = await collectCorrectionCandidates(_query, router: router);

      expect(groups.map((g) => g.candidates.length), [0, 0]);
    });

    test('ignores non-catalog providers (YouTube fallback)', () async {
      final router = StreamRouter(providers: [
        QobuzProvider(
          instances: ['https://kq.example'],
          api: _FakeQobuzApi(searchResults: {
            _searchTerm: [
              _qobuzItem(id: '42', title: 'Blinding Lights', artist: 'The Weeknd'),
            ],
          }),
        ),
      ]);

      final groups = await collectCorrectionCandidates(_query, router: router);

      expect(groups, hasLength(1));
      expect(groups.single.displayName, 'Qobuz');
    });
  });
}
