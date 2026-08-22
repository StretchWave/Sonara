import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../stream_service.dart' show Audio, Codec;
import 'audio_source_provider.dart';
import 'matching/search_terms.dart';
import 'resolved_stream.dart';
import 'song_query.dart';

/// Internet Archive provider — streams free lossless FLAC from archive.org.
///
/// Covers public-domain classical, the Live Music Archive (concerts),
/// netlabels and Creative Commons releases.  No account, no resolver:
/// IA's CDN serves full files and honors arbitrary byte ranges, so both
/// streaming (via mpv/ExoPlayer) and downloads work directly.
///
/// Matching is deliberately tolerant: IA items are usually *albums* or
/// *full concerts*, so the provider matches the requested song against the
/// item's FLAC file names rather than item titles alone.  Soundboard
/// recordings are preferred over audience recordings, and 24-bit files
/// over 16-bit, when several uploads of the same show exist.
class InternetArchiveProvider extends AudioSourceProvider {
  const InternetArchiveProvider();

  static const String providerId = 'internet_archive';

  static const String _searchUrl =
      'https://archive.org/advancedsearch.php';
  static const String _metadataUrl = 'https://archive.org/metadata';
  static const String _downloadUrl = 'https://archive.org/download';

  static const Duration _requestTimeout = Duration(seconds: 12);

  /// How many candidate items to fetch metadata for (each carries the
  /// full file list used for matching).
  static const int _maxCandidates = 5;

  @override
  String get id => providerId;

  @override
  Future<ResolvedStream> resolve(SongQuery query) async {
    final title = query.title.trim();
    if (title.isEmpty) {
      return const ResolvedStream(
        playable: false,
        statusMSG: 'Internet Archive: no title to search',
      );
    }

    final items = await _searchItems(query);
    if (items.isEmpty) {
      return ResolvedStream(
        playable: false,
        statusMSG: 'Internet Archive match not found for ${query.title}',
      );
    }

    // Fetch file lists for the top candidates in parallel.
    final results = await Future.wait(
      items.map((item) async {
        try {
          final files = await _fetchFlacFiles(item['identifier'] as String);
          return scoreItem(item, files, query);
        } catch (_) {
          return null;
        }
      }),
    );
    final scored = results.whereType<ScoredItem>().toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (scored.isEmpty || scored.first.score <= 0) {
      return ResolvedStream(
        playable: false,
        statusMSG: 'Internet Archive match not found for ${query.title}',
      );
    }

    final best = scored.first;
    final file = best.file;
    final identifier = best.identifier;
    final encodedName = Uri.encodeComponent(file.name);
    final url = '$_downloadUrl/$identifier/$encodedName';
    final durationSec = int.tryParse(file.length ?? '') ?? 0;
    final rateKhz = _parseHiresHints(file.name)?.$2;
    final bitDepth = _parseHiresHints(file.name)?.$1;

    final label = StringBuffer('Internet Archive FLAC');
    if (best.soundboard) label.write(' (soundboard)');
    if (rateKhz != null) label.write(' $bitDepth-bit/$rateKhz kHz');
    final labelString = label.toString();

    return ResolvedStream(
      playable: true,
      label: labelString,
      mimeType: 'audio/flac',
      sampleRate: rateKhz == null ? null : rateKhz * 1000,
      bitDepth: bitDepth,
      audioFormats: [
        Audio(
          itag: 9991,
          audioCodec: Codec.flac,
          bitrate: 0,
          duration: durationSec * 1000,
          loudnessDb: 0,
          url: url,
          size: int.tryParse(file.size ?? '') ?? 0,
          label: labelString,
          mimeType: 'audio/flac',
          sampleRate: rateKhz == null ? null : rateKhz * 1000,
          bitDepth: bitDepth,
        ),
      ],
    );
  }

  /// Searches archive.org for FLAC audio items matching [query].
  Future<List<Map<String, dynamic>>> _searchItems(SongQuery query) async {
    final terms = buildSearchTerms(query);
    for (final term in terms) {
      final items = await _searchOnce(term);
      if (items.isNotEmpty) return items;
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> _searchOnce(String term) async {
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    try {
      final q = 'mediatype:audio AND format:"Flac" AND (title:($term) '
          'OR description:($term))';
      final uri = Uri.parse(_searchUrl).replace(queryParameters: {
        'q': q,
        'fl[]': 'identifier,title,creator',
        'rows': '$_maxCandidates',
        'output': 'json',
        'sort[]': 'downloads desc',
      });
      final req = await client.getUrl(uri).timeout(_requestTimeout);
      req.headers.set('User-Agent', 'Sonara/1.0');
      final res = await req.close().timeout(_requestTimeout);
      if (res.statusCode != 200) return const [];
      final body = await utf8.decoder.bind(res).join();
      final decoded = jsonDecode(body);
      final docs = (decoded as Map)['response']?['docs'];
      if (docs is! List) return const [];
      return docs
          .whereType<Map>()
          .map((doc) => Map<String, dynamic>.from(doc))
          .toList();
    } catch (_) {
      return const [];
    } finally {
      client.close();
    }
  }

  /// Fetches the FLAC file list of an item, sorted by track order.
  Future<List<FlacFile>> _fetchFlacFiles(String identifier) async {
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    try {
      final uri = Uri.parse('$_metadataUrl/$identifier');
      final req = await client.getUrl(uri).timeout(_requestTimeout);
      req.headers.set('User-Agent', 'Sonara/1.0');
      final res = await req.close().timeout(_requestTimeout);
      if (res.statusCode != 200) return const [];
      final body = await utf8.decoder.bind(res).join();
      final decoded = jsonDecode(body);
      final files = (decoded as Map)['files'];
      if (files is! List) return const [];
  final out = <FlacFile>[];
  for (final entry in files.whereType<Map>()) {
    final name = entry['name'];
    if (name is! String || !name.toLowerCase().endsWith('.flac')) {
      continue;
    }
    out.add(FlacFile(
      name: name,
      length: entry['length'] is String ? entry['length'] as String : null,
      size: entry['size'] is String ? entry['size'] as String : null,
    ));
  }
  return out;
    } catch (_) {
      return const [];
    } finally {
      client.close();
    }
  }

  /// Scores one item + its FLAC files against [query].
  @visibleForTesting
  ScoredItem? scoreItem(
    Map<String, dynamic> item,
    List<FlacFile> files,
    SongQuery query,
  ) {
    if (files.isEmpty) return null;
    final identifier = (item['identifier'] as String?) ?? '';
    if (identifier.isEmpty) return null;
    final itemTitle = (item['title'] as String?) ?? '';
    final itemCreator = (item['creator'] as String?) ?? '';

    final wantedTitle = _normalize(query.title);
    final wantedArtists =
        query.artists.map(_normalize).where((a) => a.isNotEmpty).toList();
    final wantedDurationSec =
        query.durationMs == null ? null : (query.durationMs! / 1000).round();

    // Artist must appear in the item title or creator, unless unknown.
    final haystack = '${_normalize(itemTitle)} ${_normalize(itemCreator)}';
    final artistOk = wantedArtists.isEmpty ||
        wantedArtists.any((artist) => haystack.contains(artist));
    if (!artistOk) return null;

    FlacFile? bestFile;
    var bestScore = 0;
    for (final file in files) {
      final fileTitle = _normalize(file.name);
      var score = 0;
      if (fileTitle == wantedTitle) {
        score += 400;
      } else if (fileTitle.contains(wantedTitle) ||
          wantedTitle.contains(fileTitle)) {
        score += 260;
      } else if (_wordsOverlap(fileTitle, wantedTitle) >= 2) {
        score += 120;
      } else {
        // A file that doesn't mention the song at all can't be the track.
        continue;
      }

      // Duration plausibility.
      final fileDurationSec = int.tryParse(file.length ?? '');
      if (wantedDurationSec != null && fileDurationSec != null) {
        final diff = (wantedDurationSec - fileDurationSec).abs();
        if (diff <= 3) {
          score += 160;
        } else if (diff <= 10) {
          score += 90;
        } else if (diff >= 45) {
          score -= 140;
        }
      }

      // Artist appearing in the file name is a bonus (e.g. "06. Artist -
      // Song.flac").
      if (wantedArtists.any(fileTitle.contains)) score += 80;

      // Prefer hi-res (24-bit) files over CD-ripped ones.
      final hints = _parseHiresHints(file.name);
      if (hints != null) score += hints.$1 >= 24 ? 60 : 20;

      if (score > bestScore) {
        bestScore = score;
        bestFile = file;
      }
    }
    if (bestFile == null) {
      // Fallback: the item itself carries the requested title (single-work
      // releases, album-title queries). Play its first file.
      final normalizedItem = _normalize(itemTitle);
      if (wantedTitle.length >= 4 && normalizedItem.contains(wantedTitle)) {
        bestFile = files.first;
        bestScore = 300;
      } else {
        return null;
      }
    }
    if (bestScore < 260) return null;

    // Source preference: soundboard > matrix > audience.
    final identifierLower = identifier.toLowerCase();
    final itemHaystackLower = '$itemTitle $itemCreator'.toLowerCase();
    final soundboard = identifierLower.contains('sbd') ||
        itemHaystackLower.contains('soundboard') ||
        itemHaystackLower.contains('matrix');
    final audienceOnly = identifierLower.contains('aud') &&
        !identifierLower.contains('sbd') &&
        !itemHaystackLower.contains('soundboard');

    var score = bestScore;
    if (soundboard) score += 200;
    if (audienceOnly) score -= 60;

    return ScoredItem(
      identifier: identifier,
      file: bestFile,
      score: score,
      soundboard: soundboard,
    );
  }

  @visibleForTesting
  static String normalizeTitle(String value) => _normalize(value);

  static String _normalize(String value) {
    final lower = value.toLowerCase();
    final cleaned = lower
        .replaceAll(RegExp(r"[\(\)\[\]\{\}\-_–—,.!?'`]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Drop common container noise ("cd1", "disc2", track numbers) and
    // leading track numbers.
    return cleaned
        .replaceAll(RegExp(r'\b(cd|disc|disk|track)\s*\d+\b'), '')
        .replaceFirst(RegExp(r'^\d+\s+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @visibleForTesting
  static int wordsOverlap(String a, String b) => _wordsOverlap(a, b);

  static int _wordsOverlap(String a, String b) {
    final wordsA = a.split(' ').where((w) => w.length > 2).toSet();
    return b.split(' ').where((w) => wordsA.contains(w)).length;
  }

  /// Parses "24-96"-style hi-res hints from a file name: returns
  /// (bitDepth, sampleRateKhz) when found, e.g. (24, 96).
  @visibleForTesting
  static (int, int)? parseHiresHints(String name) => _parseHiresHints(name);

  static (int, int)? _parseHiresHints(String name) {
    final match = RegExp(r'(\d{1,2})-(\d{2,3})').firstMatch(name);
    if (match == null) return null;
    final a = int.tryParse(match.group(1)!);
    final b = int.tryParse(match.group(2)!);
    if (a == null || b == null) return null;
    // Only recognize plausible bit-depth/rate pairs.
    if ((a == 16 || a == 24 || a == 32) &&
        (b == 44 || b == 48 || b == 88 || b == 96 || b == 192)) {
      return (a, b);
    }
    return null;
  }
}

/// A single FLAC file inside an archive.org item.
@visibleForTesting
class FlacFile {
  final String name;
  final String? length;
  final String? size;

  const FlacFile({required this.name, this.length, this.size});
}

/// Best-matching file for an item, with its score.
@visibleForTesting
class ScoredItem {
  final String identifier;
  final FlacFile file;
  final int score;
  final bool soundboard;

  const ScoredItem({
    required this.identifier,
    required this.file,
    required this.score,
    required this.soundboard,
  });
}
