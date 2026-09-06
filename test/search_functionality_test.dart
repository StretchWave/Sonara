import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:sonara/services/music_service.dart';
import 'package:sonara/services/nav_parser.dart';
import 'package:sonara/ui/screens/Home/home_screen_controller.dart';
import 'package:sonara/ui/screens/Search/search_result_screen.dart';
import 'package:sonara/ui/screens/Settings/settings_screen_controller.dart';
import 'package:sonara/utils/get_localization.dart';

/// A minimal, parseable `musicResponsiveListItemRenderer` for a song.
Map<String, dynamic> _songRow(
  String videoId,
  String title,
  String artist,
  String album,
  String length,
) {
  return {
    'musicResponsiveListItemRenderer': {
      'flexColumns': [
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': {
              'runs': [
                {'text': title},
              ],
            },
          },
        },
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': {
              'runs': [
                {'text': artist},
                {'text': ' • '},
                {'text': album},
                {'text': ' • '},
                {'text': length},
              ],
            },
          },
        },
      ],
      'overlay': {
        'musicItemThumbnailOverlayRenderer': {
          'content': {
            'musicPlayButtonRenderer': {
              'playNavigationEndpoint': {
                'watchEndpoint': {
                  'videoId': videoId,
                  'watchEndpointMusicSupportedConfigs': {
                    'watchEndpointMusicConfig': {
                      'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV',
                    },
                  },
                },
              },
            },
          },
        },
      },
      'thumbnail': {
        'musicThumbnailRenderer': {
          'thumbnail': {
            'thumbnails': [
              {'url': 'https://example.com/a.jpg'},
            ],
          },
        },
      },
    },
  };
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(Map<String, dynamic> body) => ResponseBody.fromString(
      json.encode(body),
      200,
      headers: {'content-type': ['application/json']},
    );

MusicServices _musicServicesWith(Map<String, dynamic> body) {
  final ms = MusicServices();
  // Use the synchronous transformer so tests avoid isolate scheduling.
  ms.dio.transformer = SyncTransformer();
  ms.dio.httpClientAdapter =
      _FakeAdapter((options) async => _jsonBody(body));
  return ms;
}

/// Wraps search contents in the standard `tabbedSearchResultsRenderer` shape.
Map<String, dynamic> _searchResponse(List<dynamic> sections) => {
      'contents': {
        'tabbedSearchResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'sectionListRenderer': {
                    'header': {
                      'chipCloudRenderer': {
                        'chips': [],
                      },
                    },
                    'contents': sections,
                  },
                },
              },
            },
          ],
        },
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MusicServices.search resilience', () {
    test('parses songs from musicShelfRenderer sections', () async {
      final ms = _musicServicesWith(_searchResponse([
        {
          'musicShelfRenderer': {
            'contents': [
              _songRow('id1', 'Blinding Lights', 'The Weeknd', 'After Hours',
                  '3:20'),
            ],
          },
        },
      ]));

      final result = await ms.search('Blinding Lights');

      expect(result['Songs'], isNotNull);
      expect((result['Songs'] as List).length, 1);
      expect((result['Songs'] as List).first, isA<MediaItem>());
    });

    test('does NOT discard results arriving in a single itemSectionRenderer',
        () async {
      // Regression: when YouTube returns every result inside one
      // itemSectionRenderer (the newer response format), the old early-return
      // discarded them all and the search screen showed "no match".
      final ms = _musicServicesWith(_searchResponse([
        {
          'itemSectionRenderer': {
            'contents': [
              _songRow('id1', 'Blinding Lights', 'The Weeknd', 'After Hours',
                  '3:20'),
            ],
          },
        },
      ]));

      final result = await ms.search('Blinding Lights');

      expect(result['Songs'], isNotNull);
      expect((result['Songs'] as List).length, 1);
    });

    test('returns an empty result for a null contents body (bot check)',
        () async {
      final ms = _musicServicesWith({'contents': null});

      final result = await ms.search('Blinding Lights');

      expect(result.containsKey('Songs'), isFalse);
      expect(result.containsKey('Albums'), isFalse);
    });

    test('returns an empty result when sectionListRenderer is missing',
        () async {
      final ms = _musicServicesWith({
        'contents': {
          'tabbedSearchResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {'someUnexpectedRenderer': {}},
                },
              },
            ],
          },
        },
      });

      final result = await ms.search('Blinding Lights');

      expect(result.containsKey('Songs'), isFalse);
      expect(result.containsKey('Albums'), isFalse);
    });
  });

  group('parseSearchResults', () {
    test('skips rows without a parseable item renderer instead of crashing',
        () {
      final rows = [
        _songRow('id1', 'Blinding Lights', 'The Weeknd', 'After Hours', '3:20'),
        {'continuationItemRenderer': {'continuationEndpoint': {}}},
        {'foo': 'bar'},
      ];

      final parsed = parseSearchResults(rows,
          ['artist', 'playlist', 'song', 'video', 'station'], 'song', 'Songs');

      expect(parsed.length, 1);
      expect(parsed.first, isA<MediaItem>());
    });

    test('returns an empty list when nothing is parseable', () {
      final rows = [
        {'continuationItemRenderer': {}},
        {'messageRenderer': {}},
      ];

      final parsed = parseSearchResults(rows,
          ['artist', 'playlist', 'song', 'video', 'station'], 'song', 'Songs');

      expect(parsed, isEmpty);
    });
  });

  group('SearchResultScreen error handling', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('search_test');
      Hive.init(tempDir.path);
      await Hive.openBox('AppPrefs');
      Get.reset();
    });

    tearDown(() async {
      Get.reset();
      await Hive.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('a failed search shows retry instead of an infinite spinner',
        (WidgetTester tester) async {
      final ms = _FakeMusicServices();
      ms.shouldThrow = true;
      Get.put<MusicServices>(ms);
      Get.put<HomeScreenController>(_FakeHomeController());
      Get.put<SettingsScreenController>(_FakeSettingsController());

      // Navigate to the search result screen with a query, mirroring the app's
      // real Get.toNamed flow so Get.arguments is populated.
      await tester.pumpWidget(
        GetMaterialApp(
          translations: Languages(),
          locale: const Locale('en'),
          home: const _SearchNav(),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // The failure must surface as an error + retry, not a permanent spinner.
      expect(ms.searchCalls, greaterThanOrEqualTo(1));
      expect(find.text('Retry!'), findsOneWidget);

      // Fixing the source and retrying must re-run the search and leave the
      // error state. An empty result is used so the results UI stays in the
      // lightweight "no match" branch (rendering song tiles would pull in the
      // player stack, which is out of scope for this test).
      ms.shouldThrow = false;
      ms.result = {'searchEndpoint': {}};

      await tester.tap(find.text('Retry!'));
      await tester.pumpAndSettle();

      expect(find.text('Retry!'), findsNothing);
      expect(find.text('No Match found for'), findsOneWidget);
      expect(ms.searchCalls, greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
    });
  });
}

const _navId = 1;
const _searchRoute = '/search';

/// A minimal nested navigator that routes to [SearchResultScreen] with a
/// query argument, mirroring how the app navigates to search results.
class _SearchNav extends StatelessWidget {
  const _SearchNav();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: Get.nestedKey(_navId),
      initialRoute: '/home',
      onGenerateRoute: (settings) {
        Get.routing.args = settings.arguments;
        switch (settings.name) {
          case _searchRoute:
            return GetPageRoute(
              page: () => const SearchResultScreen(),
              settings: settings,
            );
          default:
            return GetPageRoute(
              page: () => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Get.toNamed(_searchRoute,
                        id: _navId, arguments: 'blinding lights'),
                    child: const Text('go'),
                  ),
                ),
              ),
              settings: settings,
            );
        }
      },
    );
  }
}

class _FakeMusicServices extends MusicServices {
  bool shouldThrow = false;
  Map<String, dynamic> result = const {};
  int searchCalls = 0;

  @override
  // ignore: must_call_super
  void onInit() {
    // Skip Hive/network initialization in tests.
  }

  @override
  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) async {
    searchCalls++;
    if (shouldThrow) {
      throw NetworkError();
    }
    return result;
  }
}

class _FakeHomeController extends HomeScreenController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Skip home content loading in tests.
  }

  @override
  void whenHomeScreenOnTop() {}
}

class _FakeSettingsController extends SettingsScreenController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Skip network/disk setup in tests.
  }
}
