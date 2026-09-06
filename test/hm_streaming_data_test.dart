import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/models/hm_streaming_data.dart';
import 'package:sonara/services/stream_service.dart';

void main() {
  test('providerId survives the JSON round-trip', () {
    final data = HMStreamingData(
      playable: true,
      statusMSG: 'OK',
      providerId: 'qobuz',
      highQualityAudio: Audio(
        itag: 6,
        audioCodec: Codec.flac,
        bitrate: 1411000,
        duration: 204000,
        loudnessDb: 0,
        url: 'https://q.example/stream.flac',
        size: 47185920,
      ),
      lowQualityAudio: Audio(
        itag: 6,
        audioCodec: Codec.flac,
        bitrate: 1411000,
        duration: 204000,
        loudnessDb: 0,
        url: 'https://q.example/stream.flac',
        size: 47185920,
      ),
    );

    final restored = HMStreamingData.fromJson(data.toJson());
    expect(restored.providerId, 'qobuz');
  });

  test('missing providerId defaults to empty (backward compatible)', () {
    final restored = HMStreamingData.fromJson({
      'playable': true,
      'statusMSG': 'OK',
      'lowQualityAudio': {
        'itag': 251,
        'audioCodec': 'opus',
        'bitrate': 160,
        'loudnessDb': 0.0,
        'url': 'https://y.example/stream',
        'approxDurationMs': 204000,
        'size': 0,
      },
      'highQualityAudio': {
        'itag': 251,
        'audioCodec': 'opus',
        'bitrate': 160,
        'loudnessDb': 0.0,
        'url': 'https://y.example/stream',
        'approxDurationMs': 204000,
        'size': 0,
      },
    });
    expect(restored.providerId, '');
  });
}
