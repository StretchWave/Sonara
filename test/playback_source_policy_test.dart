import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/audio_handler.dart';
import 'package:sonara/services/providers/stream_route_config.dart';

void main() {
  group('MyAudioHandler.providerForVideoType', () {
    test('official song audio (ATV) may use the catalog cascade', () {
      expect(MyAudioHandler.providerForVideoType('MUSIC_VIDEO_TYPE_ATV', ''),
          '');
      expect(
          MyAudioHandler.providerForVideoType('MUSIC_VIDEO_TYPE_ATV', 'qobuz'),
          'qobuz');
    });

    test('unknown/empty video type (library, restored session) may cascade', () {
      expect(MyAudioHandler.providerForVideoType('', ''), '');
      expect(MyAudioHandler.providerForVideoType('', 'qobuz'), 'qobuz');
    });

    test('a cover (UGC) is pinned to YouTube — never substituted', () {
      expect(MyAudioHandler.providerForVideoType('MUSIC_VIDEO_TYPE_UGC', ''),
          'youtube_music');
      expect(
          MyAudioHandler.providerForVideoType('MUSIC_VIDEO_TYPE_UGC', 'qobuz'),
          'youtube_music');
    });

    test('any non-official video type is pinned to YouTube', () {
      for (final type in ['MUSIC_VIDEO_TYPE_UGC', 'MUSIC_VIDEO_TYPE_OMV']) {
        expect(MyAudioHandler.providerForVideoType(type, ''),
            'youtube_music',
            reason: 'type $type');
      }
    });
  });

  group('MyAudioHandler.playbackConfig', () {
    test('demotes SoundCloud and Internet Archive to fallbacks after YouTube',
        () {
      const config = StreamRouteConfig(
        soundcloudEnabled: true,
        internetArchiveEnabled: true,
        providerOrder: ['soundcloud', 'youtube_music'],
      );
      final playback = MyAudioHandler.playbackConfig(config);
      expect(playback.providerOrder, [
        'youtube_music',
        'soundcloud',
        'internet_archive',
      ]);
    });

    test('keeps lossless catalog sources before YouTube', () {
      const config = StreamRouteConfig(
        qobuzEnabled: true,
        qobuzInstances: ['https://q.example'],
        tidalEnabled: true,
        tidalEndpoints: ['https://t.example'],
        internetArchiveEnabled: true,
        providerOrder: ['tidal', 'qobuz', 'youtube_music', 'soundcloud'],
      );
      final playback = MyAudioHandler.playbackConfig(config);
      expect(playback.providerOrder, [
        'tidal',
        'qobuz',
        'youtube_music',
        'soundcloud',
        'internet_archive',
      ]);
    });
  });
}
