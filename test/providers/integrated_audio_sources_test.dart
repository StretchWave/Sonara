import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/soundcloud/soundcloud_audio_provider.dart';
import 'package:sonara/services/providers/song_query.dart';
import 'package:sonara/services/providers/stream_route_config.dart';
import 'package:sonara/services/providers/stream_router.dart';
import 'package:sonara/services/providers/youtube_audio_provider.dart';

class _AllowAllHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  HttpOverrides.global = _AllowAllHttpOverrides();

  group('YouTubeAudioProvider (InnerTube)', () {
    const provider = YouTubeAudioProvider();

    test('has correct provider ID', () {
      expect(provider.id, 'youtube_music');
    });

    test('resolves stream for real YouTube video id', () async {
      const query = SongQuery(mediaId: '-BJt4fCAtZE', title: 'Arz Kiya Hai');
      final result = await provider.resolve(query);

      expect(result.playable, isTrue);
      expect(result.audioFormats, isNotEmpty);
      expect(result.audioFormats.first.url, startsWith('http'));
      expect(result.audioFormats.first.headers, isNotNull);
      expect(result.audioFormats.first.headers?['User-Agent'], isNotEmpty);
    });
  });

  group('SoundCloudAudioProvider', () {
    const provider = SoundCloudAudioProvider();

    test('has correct provider ID', () {
      expect(provider.id, 'soundcloud');
    });

    test('scrapes or retrieves client ID successfully', () async {
      final clientId = await SoundCloudAudioProvider.getClientId();
      expect(clientId, isNotNull);
      expect(clientId!.length, greaterThan(15));
    });

    test('resolves stream for song query with title and artist', () async {
      const query = SongQuery(
        mediaId: 'mock-id',
        title: 'Starboy',
        artists: ['The Weeknd'],
      );
      final result = await provider.resolve(query);

      expect(result.playable, isTrue);
      expect(result.audioFormats, isNotEmpty);
      expect(result.audioFormats.first.url, startsWith('http'));
      expect(result.audioFormats.first.headers, isNotNull);
    });
  });

  group('StreamRouter Cascade', () {
    test('resolves track via router cascade', () async {
      const config = StreamRouteConfig(soundcloudEnabled: true);
      final router = StreamRouter.build(config);

      final streamProvider = await router.fetch(
        '-BJt4fCAtZE',
        song: const SongQuery(
          mediaId: '-BJt4fCAtZE',
          title: 'Arz Kiya Hai',
          artists: ['Anuv Jain'],
        ),
      );

      expect(streamProvider.playable, isTrue);
      expect(streamProvider.highestQualityAudio, isNotNull);
      expect(streamProvider.highestQualityAudio!.url, startsWith('http'));
    });
  });
}
