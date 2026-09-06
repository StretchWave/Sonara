import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/song_query.dart';
import 'package:sonara/services/providers/soundcloud/soundcloud_audio_provider.dart';

const _query = SongQuery(
  mediaId: 'yt-id',
  title: 'Blinding Lights',
  artists: ['The Weeknd'],
  album: 'After Hours',
  durationMs: 200000,
);

Map<String, dynamic> _item(String id, String title, String user, int durMs) => {
      'id': id,
      'title': title,
      'user': {'username': user},
      'duration': durMs,
    };

void main() {
  group('SoundCloudAudioProvider.pickBestMatchItem', () {
    test('picks a real match over covers/remixes/slowed uploads', () {
      final collection = [
        _item('preview', 'Blinding Lights', 'The Weeknd', 30000),
        _item('cover', 'Blinding Lights (Cover)', 'FanChannel', 201000),
        _item('slowed', 'Blinding Lights (Slowed + Reverb)', 'SlowedBeats', 240000),
        _item('remix', 'Blinding Lights (Remix)', 'DJ', 205000),
        _item('real', 'Blinding Lights', 'The Weeknd', 200000),
      ];
      final best =
          SoundCloudAudioProvider.pickBestMatchItem(collection, _query);
      expect(best?['id'], 'real');
    });

    test('returns null when only wrong versions exist (no fallback to first)',
        () {
      final collection = [
        _item('preview', 'Blinding Lights', 'The Weeknd', 30000),
        _item('cover', 'Blinding Lights (Cover)', 'FanChannel', 201000),
        _item('slowed', 'Blinding Lights (Slowed + Reverb)', 'SlowedBeats', 240000),
      ];
      final best =
          SoundCloudAudioProvider.pickBestMatchItem(collection, _query);
      // The old bug: it fell back to collection.first (the 30s preview).
      expect(best, isNull);
    });

    test('rejects a wrong artist even with an exact title', () {
      final collection = [
        _item('other', 'Blinding Lights', 'SomeOtherArtist', 200000),
      ];
      final best =
          SoundCloudAudioProvider.pickBestMatchItem(collection, _query);
      expect(best, isNull);
    });

    test('rejects an implausibly short version', () {
      final collection = [
        _item('short', 'Blinding Lights', 'The Weeknd', 70000),
      ];
      final best =
          SoundCloudAudioProvider.pickBestMatchItem(collection, _query);
      expect(best, isNull);
    });

    test('accepts a clean match with the right artist and duration', () {
      final collection = [
        _item('real', 'Blinding Lights', 'The Weeknd', 200000),
      ];
      final best =
          SoundCloudAudioProvider.pickBestMatchItem(collection, _query);
      expect(best?['id'], 'real');
    });
  });
}
