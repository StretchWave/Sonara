import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/nav_parser.dart';
import 'package:sonara/services/ytaccount/yt_account_service.dart';

void main() {
  group('YtAccountService.sapisidHash', () {
    test('uses SAPISIDHASH epoch_sha1(origin) shape', () {
      final hash = YtAccountService.sapisidHash('test-sapisid',
          epochSeconds: 1700000000);
      expect(hash, startsWith('SAPISIDHASH 1700000000_'));
      final digest = hash.split('_').last;
      expect(digest.length, 40);
    });

    test('matches a known reference vector', () {
      // epoch=1700000000, sapisid=test-sapisid,
      // origin=https://music.youtube.com
      // sha1("1700000000 test-sapisid https://music.youtube.com")
      const expectedDigest = '17d748c166afd876ceb872a291e5befdca771528';
      final hash = YtAccountService.sapisidHash('test-sapisid',
          epochSeconds: 1700000000);
      expect(hash, 'SAPISIDHASH 1700000000_$expectedDigest');
    });
  });

  group('parseLibraryGrid', () {
    test('parses playlist/album/artist cards', () {
      final items = parseLibraryGrid([
        {
          'musicTwoRowItemRenderer': {
            'title': {'runs': [
              {
                'text': 'Liked playlist',
                'navigationEndpoint': {
                  'browseEndpoint': {
                    'browseId': 'VLPL123',
                    'browseEndpointContextSupportedConfigs': {
                      'browseEndpointContextMusicConfig': {
                        'pageType': 'MUSIC_PAGE_TYPE_PLAYLIST'
                      }
                    }
                  }
                }
              }
            ]},
            'subtitle': {'runs': [{'text': 'Playlist · 12 songs'}]},
            'thumbnailRenderer': {
              'musicThumbnailRenderer': {
                'thumbnail': {
                  'thumbnails': [
                    {'url': 'https://i.ytimg.com/vi/x/w120.jpg'}
                  ]
                }
              }
            }
          }
        },
        {
          'musicTwoRowItemRenderer': {
            'title': {'runs': [
              {
                'text': 'An album',
                'navigationEndpoint': {
                  'browseEndpoint': {
                    'browseId': 'MPREb123',
                    'browseEndpointContextSupportedConfigs': {
                      'browseEndpointContextMusicConfig': {
                        'pageType': 'MUSIC_PAGE_TYPE_ALBUM'
                      }
                    }
                  }
                }
              }
            ]},
            'subtitle': {'runs': [{'text': 'Artist · 1 song'}]},
          }
        },
        {
          'musicTwoRowItemRenderer': {
            'title': {'runs': [
              {
                'text': 'Niji',
                'navigationEndpoint': {
                  'browseEndpoint': {
                    'browseId': 'UC123',
                    'browseEndpointContextSupportedConfigs': {
                      'browseEndpointContextMusicConfig': {
                        'pageType': 'MUSIC_PAGE_TYPE_ARTIST'
                      }
                    }
                  }
                }
              }
            ]},
            'subtitle': {'runs': [{'text': 'Artist'}]},
          }
        }
      ]);

      expect(items.length, 3);
      expect(items[0]['kind'], 'playlist');
      expect(items[0]['id'], 'VLPL123');
      expect(items[0]['title'], 'Liked playlist');
      expect(items[0]['subtitle'], 'Playlist · 12 songs');
      expect(items[0]['thumbnailUrl'], 'https://i.ytimg.com/vi/x/w120.jpg');
      expect(items[1]['kind'], 'album');
      expect(items[2]['kind'], 'artist');
    });

    test('parses responsive list rows with second-column page type', () {
      final items = parseLibraryGrid([
        {
          'musicResponsiveListItemRenderer': {
            'flexColumns': [
              {
                'musicResponsiveListItemFlexColumnRenderer': {
                  'text': {
                    'runs': [
                      {'text': 'My playlist row'}
                    ]
                  }
                }
              },
              {
                'musicResponsiveListItemFlexColumnRenderer': {
                  'text': {
                    'runs': [
                      {
                        'text': 'Playlist',
                        'navigationEndpoint': {
                          'browseEndpoint': {
                            'browseId': 'VLPLROW',
                            'browseEndpointContextSupportedConfigs': {
                              'browseEndpointContextMusicConfig': {
                                'pageType': 'MUSIC_PAGE_TYPE_PLAYLIST'
                              }
                            }
                          }
                        }
                      }
                    ]
                  }
                }
              }
            ],
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': 'VLPLROW'}
            },
            'thumbnail': {
              'musicThumbnailRenderer': {
                'thumbnail': {
                  'thumbnails': [
                    {'url': 'https://i.ytimg.com/vi/y/w60.jpg'}
                  ]
                }
              }
            }
          }
        }
      ]);

      expect(items.length, 1);
      expect(items[0]['kind'], 'playlist');
      expect(items[0]['id'], 'VLPLROW');
      expect(items[0]['title'], 'My playlist row');
      expect(items[0]['subtitle'], 'Playlist');
      expect(items[0]['thumbnailUrl'], 'https://i.ytimg.com/vi/y/w60.jpg');
    });

    test('skips items without navigation ids', () {
      final items = parseLibraryGrid([
        {'musicTwoRowItemRenderer': {}},
        {'somethingElse': {}},
      ]);
      expect(items, isEmpty);
    });
  });
}
