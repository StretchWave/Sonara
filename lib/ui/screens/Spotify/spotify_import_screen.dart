import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/models/playlist.dart';
import '/services/metadata/backend_playlist_provider.dart';
import '/services/spotify/playlist_migration_item.dart';
import '/services/spotify/playlist_migration_service.dart';
import '/ui/screens/Library/library_controller.dart';
import '/ui/widgets/custom_button.dart';
import '/ui/widgets/loader.dart';
import '/ui/widgets/modified_text_field.dart';
import '/ui/widgets/snackbar.dart';
import 'spotify_import_controller.dart';

class SpotifyImportScreen extends StatefulWidget {
  const SpotifyImportScreen({super.key});

  @override
  State<SpotifyImportScreen> createState() => _SpotifyImportScreenState();
}

class _SpotifyImportScreenState extends State<SpotifyImportScreen> {
  late final SpotifyImportController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.isRegistered<SpotifyImportController>()
        ? Get.find<SpotifyImportController>()
        : Get.put(SpotifyImportController());
  }

  @override
  void dispose() {
    if (Get.isRegistered<SpotifyImportController>()) {
      Get.delete<SpotifyImportController>();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('importSpotifyPlaylist'.tr,
            style: Theme.of(context).textTheme.titleLarge),
        centerTitle: false,
      ),
      body: Obx(() {
        switch (controller.phase.value) {
          case MigrationPhase.setup:
            return _SetupView(controller: controller);
          case MigrationPhase.importing:
            return _CenteredMessage('resolvingPlaylist'.tr, busy: true);
          case MigrationPhase.authRequired:
            return _AuthRequiredView(controller: controller);
          case MigrationPhase.reimport:
            return _ReimportView(controller: controller);
          case MigrationPhase.resolving:
            return _ResolvingView(controller: controller);
          case MigrationPhase.review:
            return _ReviewView(controller: controller);
          case MigrationPhase.migrating:
            return _CenteredMessage('migratingTracks'.tr, busy: true);
          case MigrationPhase.done:
            return _DoneView(controller: controller);
        }
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

class _SetupView extends StatelessWidget {
  final SpotifyImportController controller;
  const _SetupView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('importSpotifyPlaylistDes'.tr,
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 20),
          Text('spotifyPlaylistUrlLabel'.tr,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ModifiedTextField(
            onChanged: (v) => controller.urlInput.value = v,
            decoration: const InputDecoration(
              hintText: 'https://open.spotify.com/playlist/...',
              contentPadding: EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: ProceedButton(
              buttonText: 'importSpotifyPlaylist'.tr,
              onPressed: controller.importPlaylist,
            ),
          ),
          Obx(() => controller.errorMessage.value != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(controller.errorMessage.value!,
                      style: TextStyle(color: theme.colorScheme.error)),
                )
              : const SizedBox.shrink()),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text('sourcesTitle'.tr, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          _SourceRow(
            icon: Icons.public,
            label: 'sourcePublic'.tr,
            status: 'sourceAvailable'.tr,
            active: true,
          ),
          _SourceRow(
            icon: Icons.storage,
            label: 'sourceCached'.tr,
            status: 'sourceReady'.tr,
            active: true,
          ),
          _SourceRow(
            icon: Icons.cloud_done,
            label: 'sourceBackend'.tr,
            status: BackendPlaylistProvider.isConfigured
                ? 'sourceAvailable'.tr
                : 'sourceNotConfigured'.tr,
            active: BackendPlaylistProvider.isConfigured,
          ),
          _SourceRow(
            icon: Icons.travel_explore,
            label: 'sourceMusicBrainz'.tr,
            status: 'sourceAvailable'.tr,
            active: true,
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String status;
  final bool active;
  const _SourceRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(active ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Text(status, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Auth required (playlist identified, track list needs Spotify access)
// ---------------------------------------------------------------------------

class _AuthRequiredView extends StatelessWidget {
  final SpotifyImportController controller;
  const _AuthRequiredView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
              child: _Artwork(url: controller.playlistArtwork.value, size: 160)),
          const SizedBox(height: 16),
          Text(controller.playlistName.value,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('authRequiredTitle'.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Obx(() => Text(
                controller.authMessage.value ?? 'authRequiredDes'.tr,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              )),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: controller.importPlaylist,
            child: Text('tryAgain'.tr),
          ),
          TextButton(
            onPressed: () => controller.phase.value = MigrationPhase.setup,
            child: Text('tryAnotherPlaylist'.tr),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Re-import (repeated import of the same playlist)
// ---------------------------------------------------------------------------

class _ReimportView extends StatelessWidget {
  final SpotifyImportController controller;
  const _ReimportView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stored = controller.reimportRecord.value;
    final analysis = controller.reimport.value;
    final importedAt = (stored?['migratedAt'] as num?)?.toInt();
    final wasCompleted = stored?['status'] == 'completed';
    final previouslyResolved = controller.matchedCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(controller.playlistName.value,
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Icon(Icons.history,
              size: 40, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(wasCompleted ? 'reimportTitle'.tr : 'reimportIncomplete'.tr,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '${'reimportLastImported'.tr}: '
            '${importedAt != null ? _formatDate(importedAt) : '—'}\n'
            '${'reimportPreviouslyResolved'.tr}: '
            '$previouslyResolved / ${controller.totalTracks.value}'
            '${!wasCompleted ? ' ${'reimportResumeHint'.tr}' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (analysis != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CountPill(
                    icon: Icons.done_all,
                    color: theme.colorScheme.primary,
                    value: analysis.unchanged.length,
                    label: 'reimportUnchanged'.tr),
                _CountPill(
                    icon: Icons.sync_alt,
                    color: Colors.amber,
                    value: analysis.changed.length,
                    label: 'reimportChanged'.tr),
                _CountPill(
                    icon: Icons.add_circle_outline,
                    color: theme.colorScheme.secondary,
                    value: analysis.added.length,
                    label: 'reimportNew'.tr),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ProceedButton(
                buttonText: 'reusePreviousMatches'.tr,
                onPressed: () =>
                    controller.chooseReimport(ReimportChoice.reuseMatches),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    controller.chooseReimport(ReimportChoice.reResolveAll),
                child: Text('reResolveEverything'.tr),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: () =>
                    controller.chooseReimport(ReimportChoice.startFresh),
                child: Text('startFresh'.tr),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatDate(int millis) {
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  final local = dt.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _CenteredMessage extends StatelessWidget {
  final String message;
  final bool busy;
  const _CenteredMessage(this.message, {this.busy = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy) const LoadingIndicator(),
          if (busy) const SizedBox(height: 16),
          Text(message, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int value;
  final String label;
  const _CountPill({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text('$value ${label.toLowerCase()}',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  final String? url;
  final double size;
  const _Artwork({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    if (url == null || url.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.music_note,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(Icons.music_note,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        placeholder: (_, __) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

String _formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final h = d.inHours > 0 ? '${d.inHours}:' : '';
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$h$m:$s';
}

IconData _statusIcon(MigrationStatus status) => switch (status) {
      MigrationStatus.matched => Icons.check_circle,
      MigrationStatus.lowConfidence => Icons.warning_amber_rounded,
      MigrationStatus.unmatched => Icons.search_off,
      MigrationStatus.failed => Icons.error_outline,
      MigrationStatus.skipped => Icons.skip_next,
      MigrationStatus.searching => Icons.sync,
      MigrationStatus.pending => Icons.radio_button_unchecked,
    };

Color _statusColor(BuildContext context, MigrationStatus status) =>
    switch (status) {
      MigrationStatus.matched => Theme.of(context).colorScheme.primary,
      MigrationStatus.lowConfidence => Colors.amber,
      MigrationStatus.unmatched => Theme.of(context).colorScheme.outline,
      MigrationStatus.failed => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.outline,
    };

IconData _lyricsIcon(LyricsStatus status) => switch (status) {
      LyricsStatus.synced => Icons.lyrics,
      LyricsStatus.plain => Icons.notes,
      LyricsStatus.instrumental => Icons.music_note,
      LyricsStatus.notFound => Icons.lyrics_outlined,
      _ => Icons.music_off,
    };

// ---------------------------------------------------------------------------
// Resolving (live progress)
// ---------------------------------------------------------------------------

class _ResolvingView extends StatelessWidget {
  final SpotifyImportController controller;
  const _ResolvingView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = controller.totalTracks.value;
    final done = controller.completedTracks.value;
    final progress = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(controller.playlistName.value,
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Obx(() => Text(
                    switch (controller.stage.value) {
                      ResolutionStage.enriching => 'enrichingTracks'.tr,
                      ResolutionStage.matching => 'matchingTracks'.tr,
                      ResolutionStage.lyrics => 'fetchingLyrics'.tr,
                    },
                    style: theme.textTheme.bodyMedium,
                  )),
              const SizedBox(height: 4),
              Obx(() {
                final done = controller.completedTracks.value;
                return Text('$done / $total',
                    style: theme.textTheme.bodySmall);
              }),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                ),
              ),
              Obx(() {
                if (controller.stage.value != ResolutionStage.lyrics ||
                    controller.lyricsTotal.value == 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),                        child: LinearProgressIndicator(
                          value: controller.lyricsDone.value /
                              controller.lyricsTotal.value,
                          minHeight: 4,
                        ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              Obx(() => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CountPill(
                          icon: Icons.check_circle,
                          color: theme.colorScheme.primary,
                          value: controller.matchedCount,
                          label: 'matched'.tr),
                      _CountPill(
                          icon: Icons.warning_amber_rounded,
                          color: Colors.amber,
                          value: controller.uncertainCount,
                          label: 'uncertain'.tr),
                      _CountPill(
                          icon: Icons.search_off,
                          color: theme.colorScheme.outline,
                          value: controller.unavailableCount,
                          label: 'unavailable'.tr),
                      _CountPill(
                          icon: Icons.sync,
                          color: theme.colorScheme.secondary,
                          value: controller.searchingCount,
                          label: 'searching'.tr),
                    ],
                  )),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: controller.isResolving.value
                      ? controller.cancel
                      : null,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: Text('cancelImport'.tr),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Obx(() => ListView.builder(
                itemCount: controller.items.length,
                itemBuilder: (context, i) =>
                    _MigrationTile(item: controller.items[i]),
              )),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Review
// ---------------------------------------------------------------------------

class _ReviewView extends StatelessWidget {
  final SpotifyImportController controller;
  const _ReviewView({required this.controller});

  void _showDestinationSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _DestinationSheet(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(controller.playlistName.value,
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Obx(() {
                if (controller.wasCancelled.value) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.pause_circle_outline,
                            size: 18, color: Colors.amber),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('importCancelled'.tr,
                              style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
              Obx(() => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CountPill(
                          icon: Icons.check_circle,
                          color: theme.colorScheme.primary,
                          value: controller.matchedCount,
                          label: 'matched'.tr),
                      _CountPill(
                          icon: Icons.warning_amber_rounded,
                          color: Colors.amber,
                          value: controller.uncertainCount,
                          label: 'needReview'.tr),
                      _CountPill(
                          icon: Icons.search_off,
                          color: theme.colorScheme.outline,
                          value: controller.unavailableCount,
                          label: 'unavailable'.tr),
                    ],
                  )),
              const SizedBox(height: 8),
              Obx(() => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CountPill(
                          icon: Icons.lyrics,
                          color: theme.colorScheme.secondary,
                          value: controller.lyricsSyncedCount,
                          label: 'lyricsSynced'.tr),
                      _CountPill(
                          icon: Icons.notes,
                          color: theme.colorScheme.secondary,
                          value: controller.lyricsPlainCount,
                          label: 'lyricsPlain'.tr),
                      _CountPill(
                          icon: Icons.music_note,
                          color: theme.colorScheme.outline,
                          value: controller.lyricsInstrumentalCount,
                          label: 'lyricsInstrumental'.tr),
                      _CountPill(
                          icon: Icons.lyrics_outlined,
                          color: theme.colorScheme.outline,
                          value: controller.lyricsUnavailableCount,
                          label: 'lyricsUnavailable'.tr),
                    ],
                  )),
              const SizedBox(height: 8),
              Obx(() => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'all'.tr,
                          selected:
                              controller.reviewFilter.value == ReviewFilter.all,
                          onSelected: () => controller.reviewFilter.value =
                              ReviewFilter.all,
                        ),
                        _FilterChip(
                          label: 'filterNeedsReview'.tr,
                          selected: controller.reviewFilter.value ==
                              ReviewFilter.needsReview,
                          onSelected: () => controller.reviewFilter.value =
                              ReviewFilter.needsReview,
                        ),
                        _FilterChip(
                          label: 'filterMatched'.tr,
                          selected: controller.reviewFilter.value ==
                              ReviewFilter.matched,
                          onSelected: () => controller.reviewFilter.value =
                              ReviewFilter.matched,
                        ),
                        _FilterChip(
                          label: 'filterUnavailable'.tr,
                          selected: controller.reviewFilter.value ==
                              ReviewFilter.unavailable,
                          onSelected: () => controller.reviewFilter.value =
                              ReviewFilter.unavailable,
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (controller.uncertainCount > 0 ||
                      controller.unavailableCount > 0)
                    TextButton(
                      onPressed: controller.retryUnmatched,
                      child: Text('retryUnmatched'.tr),
                    )
                  else
                    const SizedBox.shrink(),
                  ProceedButton(
                    buttonText: 'continue'.tr,
                    onPressed: () => _showDestinationSheet(context),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Obx(() {
            final list = controller.filteredItems;
            if (list.isEmpty) {
              return Center(
                  child: Text('filterEmpty'.tr,
                      style: theme.textTheme.bodyMedium));
            }
            return ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final item = list[i];
                return _MigrationTile(
                  item: item,
                  onTap: item.needsReview
                      ? () => _showCandidateSheet(context, item)
                      : null,
                );
              },
            );
          }),
        ),
      ],
    );
  }

  void _showCandidateSheet(
      BuildContext context, PlaylistMigrationItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _CandidateSheet(controller: controller, item: item),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Track tile
// ---------------------------------------------------------------------------

class _MigrationTile extends StatelessWidget {
  final PlaylistMigrationItem item;
  final VoidCallback? onTap;
  const _MigrationTile({required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = item.sourceTrack;
    final matched = item.matchedTrack;
    final artwork =
        matched != null ? matched.artUri?.toString() : source.artworkUrl;

    String subtitle;
    if (item.status == MigrationStatus.skipped) {
      subtitle = 'unavailableTrack'.tr;
    } else if (source.artists.isNotEmpty) {
      subtitle = source.artists.join(', ');
    } else {
      subtitle = '';
    }
    if (matched != null) {
      final provider = item.matchedProvider?.displayName ?? '';
      final pct = (item.matchScore * 100).round();
      final lyrics = switch (item.lyrics.status) {
        LyricsStatus.synced => ' • ${'lyricsSynced'.tr}',
        LyricsStatus.plain => ' • ${'lyricsPlain'.tr}',
        LyricsStatus.instrumental => ' • ${'lyricsInstrumental'.tr}',
        _ => '',
      };
      subtitle = '$subtitle\n$provider • $pct%$lyrics';
    }

    return ListTile(
      onTap: onTap,
      leading: _Artwork(url: artwork, size: 48),
      title: Text(
        source.title.isEmpty ? 'unavailableTrack'.tr : source.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: Text(subtitle,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall),
      trailing: item.status == MigrationStatus.searching
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.matchedTrack != null &&
                    item.lyrics.status != LyricsStatus.none &&
                    item.lyrics.status != LyricsStatus.failed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                        _lyricsIcon(item.lyrics.status),
                        size: 16,
                        color: item.lyrics.status == LyricsStatus.synced ||
                                item.lyrics.status == LyricsStatus.plain
                            ? theme.colorScheme.secondary
                            : theme.colorScheme.outline),
                  ),
                Icon(_statusIcon(item.status),
                    color: _statusColor(context, item.status), size: 22),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manual match candidates
// ---------------------------------------------------------------------------

class _CandidateSheet extends StatelessWidget {
  final SpotifyImportController controller;
  final PlaylistMigrationItem item;
  const _CandidateSheet({required this.controller, required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = item.sourceTrack;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('chooseMatch'.tr, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('${source.title} — ${source.artists.join(', ')}'
                    ' • ${_formatDuration(Duration(milliseconds: source.durationMs))}',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                      controller.service.resolveOne(item).then((_) {
                        controller.items.refresh();
                        Get.back();
                      });
                    },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text('searchAgain'.tr),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        controller.skipTrack(item);
                        Get.back();
                      },
                      icon: const Icon(Icons.skip_next, size: 18),
                      label: Text('skipTrack'.tr),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: item.candidates.isEmpty
                ? Center(
                    child: Text('noCandidates'.tr,
                        style: theme.textTheme.bodyMedium))
                : ListView.builder(
                    controller: scrollController,
                    itemCount: item.candidates.length,
                    itemBuilder: (context, i) {
                      final c = item.candidates[i];
                      final isChosen = c.track.id == item.matchedTrack?.id;
                      return ListTile(
                        leading: _Artwork(
                            url: c.track.artUri?.toString(), size: 48),
                        title: Text(c.track.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${c.track.artist}\n${c.provider.displayName} • '
                            '${(c.score * 100).round()}% • '
                            '${_formatDuration(c.track.duration)}',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: isChosen
                            ? Icon(Icons.check_circle,
                                color: theme.colorScheme.primary)
                            : null,
                        onTap: () async {
                          await controller.applyManualMatch(item, c);
                          Get.back();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Destination
// ---------------------------------------------------------------------------

class _DestinationSheet extends StatelessWidget {
  final SpotifyImportController controller;
  const _DestinationSheet({required this.controller});

  Future<void> _createPlaylistDialog(BuildContext context) async {
    final textController =
        TextEditingController(text: controller.playlistName.value);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('createPlaylist'.tr),
        content: ModifiedTextField(
          controller: textController,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 8),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('cancel'.tr)),
          TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(textController.text),
              child: Text('create'.tr)),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      await controller.createPlaylist(name.trim());
    }
  }

  Future<void> _existingPlaylistSheet(BuildContext context) async {
    final librPlstCntrller = Get.find<LibraryPlaylistsController>();
    final playlists = librPlstCntrller.libraryPlaylists
        .where((p) =>
            !const {
              'LIBRP',
              'LIBFAV',
              'LIBTP',
              'SongsCache',
              'SongDownloads'
            }.contains(p.playlistId) &&
            !p.isPipedPlaylist)
        .toList();
    final selected = await showModalBottomSheet<Playlist>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (sheetContext) => ListView(
        children: playlists.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: Text('noUserPlaylists'.tr,
                          style: Theme.of(context).textTheme.bodyMedium)),
                )
              ]
            : playlists
                .map((p) => ListTile(
                      leading: _Artwork(url: p.thumbnailUrl, size: 48),
                      title: Text(p.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(sheetContext).pop(p),
                    ))
                .toList(),
      ),
    );
    if (selected != null) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      await controller.addToExistingPlaylist(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('migrationDestination'.tr,
                  style: theme.textTheme.titleMedium),
            ),
            Obx(() => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      _ConfidenceChoice(
                        label: 'confidenceHigh'.tr,
                        selected: controller.confidenceFilter.value ==
                            ConfidenceFilter.high,
                        onSelected: () => controller.confidenceFilter.value =
                            ConfidenceFilter.high,
                      ),
                      _ConfidenceChoice(
                        label: 'confidenceHighMedium'.tr,
                        selected: controller.confidenceFilter.value ==
                            ConfidenceFilter.highAndMedium,
                        onSelected: () => controller.confidenceFilter.value =
                            ConfidenceFilter.highAndMedium,
                      ),
                      _ConfidenceChoice(
                        label: 'confidenceAllMatches'.tr,
                        selected: controller.confidenceFilter.value ==
                            ConfidenceFilter.all,
                        onSelected: () => controller.confidenceFilter.value =
                            ConfidenceFilter.all,
                      ),
                    ],
                  ),
                )),
            Obx(() => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    '${controller.eligibleItems.length} '
                    '${'eligibleTracks'.tr}',
                    style: theme.textTheme.bodySmall,
                  ),
                )),
            ListTile(
              leading: const Icon(Icons.favorite),
              title: Text('addToLikedSongs'.tr),
              subtitle: Text('addToLikedSongsDes'.tr,
                  style: theme.textTheme.bodySmall),
              onTap: () {
                Navigator.of(context).pop();
                controller.migrateToLiked();
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: Text('createNewPlaylist'.tr),
              subtitle: Text('createNewPlaylistDes'.tr,
                  style: theme.textTheme.bodySmall),
              onTap: () => _createPlaylistDialog(context),
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: Text('addToExistingPlaylist'.tr),
              subtitle: Text('addToExistingPlaylistDes'.tr,
                  style: theme.textTheme.bodySmall),
              onTap: () => _existingPlaylistSheet(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfidenceChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  const _ConfidenceChoice({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ---------------------------------------------------------------------------
// Done
// ---------------------------------------------------------------------------

class _DoneView extends StatelessWidget {
  final SpotifyImportController controller;
  const _DoneView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = controller.lastResult.value;
    final sourceTotal = controller.eligibleItems.length;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('migrationComplete'.tr, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('${controller.lastDestination.value} — $sourceTotal',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (result != null) ...[
              Text('${'added'.tr}: ${result.added}',
                  style: theme.textTheme.bodyMedium),
              Text('${'alreadyExists'.tr}: ${result.alreadyExists}',
                  style: theme.textTheme.bodyMedium),
              Text('${'failed'.tr}: ${result.failed}',
                  style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 4),
            Text('lyricsSummary'.tr, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('${'lyricsSynced'.tr}: ${controller.lyricsSyncedCount}',
                style: theme.textTheme.bodyMedium),
            Text('${'lyricsPlain'.tr}: ${controller.lyricsPlainCount}',
                style: theme.textTheme.bodyMedium),
            Text(
                '${'lyricsInstrumental'.tr}: '
                '${controller.lyricsInstrumentalCount}',
                style: theme.textTheme.bodyMedium),
            Text(
                '${'lyricsUnavailable'.tr}: '
                '${controller.lyricsUnavailableCount}',
                style: theme.textTheme.bodyMedium),
            if (controller.lyricsFailedCount > 0)
              Text('${'lyricsFailed'.tr}: ${controller.lyricsFailedCount}',
                  style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () {
                    controller.reset();
                    if (Get.isRegistered<LibraryPlaylistsController>()) {
                      Get.find<LibraryPlaylistsController>().refreshLib();
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                        snackbar(context, 'migrationSaved'.tr,
                            size: SanckBarSize.MEDIUM));
                  },
                  child: Text('importAnother'.tr),
                ),
                ProceedButton(
                  buttonText: 'done'.tr,
                  onPressed: () => Get.back(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
