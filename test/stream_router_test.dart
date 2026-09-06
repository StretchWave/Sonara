import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/audio_source_provider.dart';
import 'package:sonara/services/providers/resolved_stream.dart';
import 'package:sonara/services/providers/song_query.dart';
import 'package:sonara/services/providers/stream_route_config.dart';
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

  test('default router contains YouTube and SoundCloud providers', () {
    expect(StreamRouter.instance.providers.map((p) => p.id),
        ['youtube_music', 'soundcloud', 'internet_archive']);
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

  test('fetch stamps the producing provider id on the result', () async {
    final router = StreamRouter(providers: [_FakeProvider('qobuz', fail: false)]);
    final result = await router.fetch('song-1');
    expect(result.providerId, 'qobuz');
  });

  test('build with forceProviderId keeps only that provider', () {
    const config = StreamRouteConfig(
      qobuzEnabled: true,
      qobuzInstances: ['https://q.example'],
      tidalEnabled: true,
      tidalEndpoints: ['https://t.example'],
    );
    final router = StreamRouter.build(config, forceProviderId: 'youtube_music');
    expect(router.providers.map((p) => p.id), ['youtube_music']);
  });

  test('build with forceProviderId of a disabled provider is empty', () {
    const config = StreamRouteConfig();
    final router = StreamRouter.build(config, forceProviderId: 'qobuz');
    expect(router.providers, isEmpty);
  });

  test('fetchAll returns every playable provider with its id', () async {
    final router = StreamRouter(providers: [
      _FakeProvider('qobuz', fail: false),
      _FakeProvider('tidal', fail: true),
      _FakeProvider('deezer', fail: false),
    ]);
    final results = await router.fetchAll('song-1');
    expect(results.map((r) => r.providerId), ['qobuz', 'deezer']);
    expect(results.first.stream.providerId, 'qobuz');
  });

  test('fetchAll filters to FLAC sources via flacAudio', () async {
    final router = StreamRouter(providers: [
      _FakeFlacProvider('qobuz', 'Qobuz Hi-Res FLAC 24-bit/192 kHz'),
      _FakeProvider('youtube_music', fail: false),
    ]);
    final results = await router.fetchAll('song-1');
    final flac = results
        .where((r) => r.flacAudio?.audioCodec == Codec.flac)
        .toList();
    expect(flac.map((r) => r.providerId), ['qobuz']);
    expect(flac.single.flacAudio!.label, 'Qobuz Hi-Res FLAC 24-bit/192 kHz');
    expect(flac.single.flacAudio!.duration, 204000);
    expect(flac.single.flacAudio!.size, 47185920);
  });
}

/// A provider that returns a FLAC stream with label/duration/size.
class _FakeFlacProvider extends AudioSourceProvider {
  _FakeFlacProvider(this._id, this._label);

  final String _id;
  final String _label;

  @override
  String get id => _id;

  @override
  Future<ResolvedStream> resolve(SongQuery query) async {
    return ResolvedStream(
      playable: true,
      statusMSG: 'OK',
      label: _label,
      audioFormats: [
        Audio(
          itag: 6,
          audioCodec: Codec.flac,
          bitrate: 1411000,
          duration: 204000,
          loudnessDb: 0,
          url: 'https://$_id/stream.flac',
          size: 47185920,
          label: _label,
        ),
      ],
    );
  }
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
