import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../screens/Settings/settings_screen_controller.dart';
import '/services/downloader.dart';
import '/services/providers/song_query.dart';
import '/services/providers/stream_route_config.dart';
import '/services/providers/stream_router.dart';
import '/services/stream_service.dart' show Codec;

/// Shows a per-song download format picker (Original / MP3 / FLAC) and
/// starts the download with the chosen format.
///
/// The globally configured default (Settings → Download) is highlighted;
/// automatic downloads (playlists, favorites) keep using that default.
/// Choosing FLAC opens a second sheet listing every source that can supply
/// a FLAC copy (name, length, size) so the user can pick one.
Future<void> showDownloadFormatSheet(BuildContext context, MediaItem song) async {
  final settingsController = Get.find<SettingsScreenController>();
  final selected = await showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (context) => _DownloadFormatSheet(
      defaultFormat: settingsController.downloadingFormat.value,
    ),
  );
  if (selected == null || !context.mounted) return;

  if (selected == 'flac') {
    final source = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => _FlacSourceSheet(song: song),
    );
    if (source == null || !context.mounted) return;
    // Empty source = "no FLAC found, download the best available copy".
    Get.find<Downloader>().download(song,
        format: 'flac', source: source.isEmpty ? null : source);
    return;
  }
  Get.find<Downloader>().download(song, format: selected);
}

class _DownloadFormatSheet extends StatelessWidget {
  const _DownloadFormatSheet({required this.defaultFormat});

  /// The globally configured default, highlighted in the sheet.
  final String defaultFormat;

  static const _options = <(String, String, IconData)>[
    ('original', 'Original (source quality)', Icons.file_download_outlined),
    ('mp3', 'MP3 (320 kbps)', Icons.audiotrack),
    ('flac', 'FLAC (lossless)', Icons.hd),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              "Download as",
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final (value, label, icon) in _options)
            ListTile(
              dense: true,
              leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
              title: Text(label),
              trailing: value == defaultFormat
                  ? Icon(Icons.check, color: theme.colorScheme.primary)
                  : null,
              onTap: () => Navigator.of(context).pop(value),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Text(
              'MP3/FLAC conversion uses ffmpeg on this device. If it is '
              'not installed, the song is saved in its original format '
              'instead.',
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolves the song against every configured source and lists the ones
/// that returned a FLAC stream, each with the source name, the stream
/// label, the track length and the file size.
class _FlacSourceSheet extends StatefulWidget {
  const _FlacSourceSheet({required this.song});

  final MediaItem song;

  @override
  State<_FlacSourceSheet> createState() => _FlacSourceSheetState();
}

class _FlacSourceSheetState extends State<_FlacSourceSheet> {
  late final Future<List<_FlacSource>> _sourcesFuture;

  @override
  void initState() {
    super.initState();
    _sourcesFuture = _loadSources();
  }

  Future<List<_FlacSource>> _loadSources() async {
    final results = await StreamRouter.build(StreamRouteConfig.fromSettings())
        .fetchAll(widget.song.id, song: SongQuery.fromMediaItem(widget.song));
    final sources = <_FlacSource>[];
    for (final result in results) {
      final flac = result.stream.audioFormats
          .where((a) => a.audioCodec == Codec.flac)
          .toList();
      if (flac.isEmpty) continue;
      sources.add(_FlacSource(
        providerId: result.providerId,
        label: flac.first.label,
        durationMs: flac.first.duration,
        sizeBytes: flac.first.size,
      ));
    }
    return sources;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              "FLAC sources",
              style: theme.textTheme.titleMedium,
            ),
          ),
          FutureBuilder<List<_FlacSource>>(
            future: _sourcesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                );
              }
              final sources = snapshot.data ?? const <_FlacSource>[];
              if (sources.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No source returned a FLAC stream for this song.',
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(''),
                          child: const Text('Download best available'),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final source in sources)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.hd,
                          color: theme.colorScheme.onSurfaceVariant),
                      title: Text(_sourceName(source.providerId)),
                      subtitle: Text(
                        _sourceDetails(source),
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: () =>
                          Navigator.of(context).pop(source.providerId),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Text(
                      'Pick a source to download its FLAC copy. If ffmpeg '
                      'is not installed, the song is saved in its original '
                      'format instead.',
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FlacSource {
  const _FlacSource({
    required this.providerId,
    required this.label,
    required this.durationMs,
    required this.sizeBytes,
  });

  final String providerId;
  final String? label;
  final int durationMs;
  final int sizeBytes;
}

/// Display names for the sources the app can route through.
const Map<String, String> _sourceNames = {
  'youtube_music': 'YouTube Music',
  'soundcloud': 'SoundCloud',
  'qobuz': 'Qobuz',
  'tidal': 'Tidal',
  'deezer': 'Deezer',
  'apple': 'Apple Music',
  'amazon': 'Amazon Music',
  'internet_archive': 'Internet Archive',
  'instagram': 'Instagram',
};

String _sourceName(String providerId) =>
    _sourceNames[providerId] ?? providerId;

/// e.g. "Hi-Res FLAC 24-bit/192 kHz · 3:24 · 45.2 MB"
String _sourceDetails(_FlacSource source) {
  final parts = <String>[
    if (source.label != null && source.label!.isNotEmpty) source.label!,
    _formatDuration(source.durationMs),
    if (source.sizeBytes > 0) _formatSize(source.sizeBytes),
  ];
  return parts.join(' · ');
}

String _formatDuration(int durationMs) {
  final totalSeconds = (durationMs / 1000).round();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _formatSize(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 100) return '${mb.round()} MB';
  return '${mb.toStringAsFixed(1)} MB';
}
