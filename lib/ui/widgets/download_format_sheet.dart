import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../screens/Settings/settings_screen_controller.dart';
import '/services/downloader.dart';

/// Shows a per-song download format picker (Original / MP3 / FLAC) and
/// starts the download with the chosen format.
///
/// The globally configured default (Settings → Download) is highlighted;
/// automatic downloads (playlists, favorites) keep using that default.
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
