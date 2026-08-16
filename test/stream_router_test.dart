import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/audio_source_provider.dart';
import 'package:sonara/services/providers/resolved_stream.dart';
import 'package:sonara/services/providers/song_query.dart';
import 'package:sonara/services/providers/stream_router.dart';
import 'package:sonara/services/stream_service.dart';

/// A fake provider that either fails with a status message or returns a
/// stream URL derived from its id.
class _FakeProvider extends AudioSourceProvider {
  _FakeProvider(this._id, {required this.fail});

  final String _id;
  final bool fail;

  @override
  String get id => _id;

  @override
  Future<ResolvedStream> resolve(SongQuery query) async {
    if (fail) {
      return ResolvedStream(playable: false, statusMSG: 'failed: $_id');
    }
    return ResolvedStream(
      playable: true,
      statusMSG: 'OK',
      audioFormats: [
        Audio(
          itag: 1,
          audioCodec: Codec.mp4a,
          bitrate: 128000,
          duration: 0,
          loudnessDb: 0,
          url: 'https://$_id/stream',
          size: 0,
        ),
      ],
    );
  }
}

class _RecordingProvider extends AudioSourceProvider {
  _RecordingProvider(this._onResolve);

  final void Function(SongQuery) _onResolve;

  @override
  String get id => 'rec';

  @override
  Future<ResolvedStream> resolve(SongQuery query) async {
    _onResolve(query);
    return const ResolvedStream(playable: true, statusMSG: 'OK');
  }
}

void main() {
  test('uses the first playable provider in priority order', () async {
    final router = StreamRouter(providers: [
      _FakeProvider('a', fail: true),
      _FakeProvider('b', fail: false),
      _FakeProvider('c', fail: false),
    ]);
    final result = await router.fetch('song-1');
    expect(result.playable, isTrue);
    expect(result.audioFormats!.single.url, 'https://b/stream');
  });

  test('returns the last failure when every provider fails', () async {
    final router = StreamRouter(providers: [
      _FakeProvider('a', fail: true),
      _FakeProvider('b', fail: true),
    ]);
    final result = await router.fetch('song-1');
    expect(result.playable, isFalse);
    expect(result.statusMSG, 'failed: b');
  });

  test('a crashing provider is skipped and the next one is used', () async {
    final router = StreamRouter(providers: [
      _ThrowingProvider('boom'),
      _FakeProvider('b', fail: false),
    ]);
    final result = await router.fetch('song-1');
    expect(result.playable, isTrue);
    expect(result.audioFormats!.single.url, 'https://b/stream');
  });

  test('default router contains only the YouTube provider', () {
    expect(StreamRouter.instance.providers.single.id, 'youtube_music');
  });

  test('passes the song query through to providers', () async {
    late SongQuery received;
    final router = StreamRouter(providers: [_RecordingProvider((q) => received = q)]);
    await router.fetch(
      'id',
      song: const SongQuery(mediaId: 'id', title: 'T', artists: ['A']),
    );
    expect(received.title, 'T');
    expect(received.artists, ['A']);
  });
}

class _ThrowingProvider extends AudioSourceProvider {
  _ThrowingProvider(this._id);

  final String _id;

  @override
  String get id => _id;

  @override
  Future<ResolvedStream> resolve(SongQuery query) async {
    throw Exception('provider exploded');
  }
}
