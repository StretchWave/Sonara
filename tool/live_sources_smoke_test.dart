// Live end-to-end smoke test for the audio sources.
//
// Unlike the unit tests, this hits REAL network endpoints:
//   - YTM      : InnerTube / Piped / YoutubeExplode (no config needed)
//   - Deezer   : public API + MetroFuse's public resolver (hf.space)
//   - Tidal    : public search API + (needs a user-configured resolver to stream)
//   - Amazon   : public web API + t2tunes public resolver
//
// Run with:  flutter test tool/live_sources_smoke_test.dart
// (flutter_test is used so package resolution works; real HTTP is allowed
//  via an explicit HttpOverrides).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonara/services/providers/amazon/amazon_provider.dart';
import 'package:sonara/services/providers/apple/apple_provider.dart';
import 'package:sonara/services/providers/deezer/deezer_provider.dart';
import 'package:sonara/services/providers/song_query.dart';
import 'package:sonara/services/providers/tidal/tidal_provider.dart';
import 'package:sonara/services/providers/youtube_audio_provider.dart';

class _AllowAllHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

const _deezerResolvers = [
  'https://yesitworkssomehow-funny-deeza-api-and-yeah.hf.space',
  // 'https://dzmedia-metrofuse.onrender.com', // suspended as of 2026-08-21
];

const _amazonResolvers = [
  'https://t2tunes.site/api/amazon-music/media-from-asin',
];

void main() {
  HttpOverrides.global = _AllowAllHttpOverrides();

  test('YTM (YouTube Music)', () async {
    const provider = YouTubeAudioProvider();
    const query = SongQuery(
      mediaId: '-BJt4fCAtZE',
      title: 'Arz Kiya Hai',
      artists: ['Anuv Jain'],
    );
    final sw = Stopwatch()..start();
    final result = await provider.resolve(query);
    sw.stop();
    print('--- YTM ---');
    print('  playable=${result.playable}  latency=${sw.elapsedMilliseconds}ms');
    print('  statusMSG=${result.statusMSG}');
    print('  formats=${result.audioFormats.length}');
    for (final f in result.audioFormats.take(2)) {
      print('    itag=${f.itag} codec=${f.audioCodec} bitrate=${f.bitrate} '
          'url=${f.url.length > 90 ? f.url.substring(0, 90) + '...' : f.url}');
    }
    expect(result.playable, isTrue,
        reason: 'YTM should resolve a real video id: ${result.statusMSG}');
  });

  test('Deezer (search via ISRC + hf.space resolver)', () async {
    final provider = DeezerProvider(
      endpoints: _deezerResolvers,
      quality: 'MP3_128',
    );
    const query = SongQuery(
      mediaId: 'deezer-probe',
      title: 'Cut To The Feeling',
      artists: ['Carly Rae Jepsen'],
      isrc: 'USUM71703861',
    );
    final sw = Stopwatch()..start();
    final result = await provider.resolve(query);
    sw.stop();
    print('--- DEEZER ---');
    print('  playable=${result.playable}  latency=${sw.elapsedMilliseconds}ms');
    print('  statusMSG=${result.statusMSG}');
    if (result.playable) {
      final f = result.audioFormats.first;
      print('  label=${result.label} url=${f.url}');
    }
  });

  test('Tidal (public search API)', () async {
    final provider = TidalProvider(endpoints: const []);
    const query = SongQuery(
      mediaId: 'tidal-probe',
      title: 'Starboy',
      artists: ['The Weeknd'],
    );
    final sw = Stopwatch()..start();
    final result = await provider.resolve(query);
    sw.stop();
    print('--- TIDAL ---');
    print('  playable=${result.playable}  latency=${sw.elapsedMilliseconds}ms');
    print('  statusMSG=${result.statusMSG}');
    // Verify the public search API itself returns catalog data.
    final candidates = await provider.searchCandidates(query, limit: 5);
    print('  searchCandidates=${candidates.length}');
    for (final c in candidates.take(3)) {
      print('    id=${c.trackId} "${c.title}" - ${c.artists.join(", ")} '
          'q=${c.qualityLabel}');
    }
    expect(candidates, isNotEmpty,
        reason: 'Tidal public search should return catalog data');
  });

  test('Apple Music (token + AMP + gamdl resolver)', () async {
    final provider = AppleProvider();
    const query = SongQuery(
      mediaId: 'apple-probe',
      title: 'Starboy',
      artists: ['The Weeknd'],
    );
    final sw = Stopwatch()..start();
    final result = await provider.resolve(query);
    sw.stop();
    print('--- APPLE ---');
    print('  playable=${result.playable}  latency=${sw.elapsedMilliseconds}ms');
    print('  statusMSG=${result.statusMSG}');
    if (result.playable) {
      final f = result.audioFormats.first;
      print('  label=${result.label} url=${f.url}');
    }
    expect(result.playable, isTrue,
        reason: 'Apple should resolve via MetroFuse endpoints: '
            '${result.statusMSG}');
  });

  test('Amazon (t2tunes resolver)', () async {
    final provider = AmazonProvider(
      endpoints: _amazonResolvers,
      quality: 'LOSSLESS',
    );
    // Use a direct ASIN so we skip the (broken/geo-blocked) web search.
    const query = SongQuery(
      mediaId: 'B0C4Y6R4H3',
      title: 'Starboy',
      artists: ['The Weeknd'],
    );
    final sw = Stopwatch()..start();
    final result = await provider.resolve(query);
    sw.stop();
    print('--- AMAZON ---');
    print('  playable=${result.playable}  latency=${sw.elapsedMilliseconds}ms');
    print('  statusMSG=${result.statusMSG}');
    if (result.playable) {
      final f = result.audioFormats.first;
      print('  label=${result.label} url=${f.url}');
    }
  });
}
