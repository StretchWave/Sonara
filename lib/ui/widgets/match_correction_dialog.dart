import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/providers/match_correction.dart';
import '/services/providers/matching/match_override_store.dart';
import '/services/providers/matching/track_candidate.dart';
import '/services/providers/song_query.dart';
import '/ui/player/player_controller.dart';
import 'common_dialog_widget.dart';

/// Opens the match-correction dialog for [song].
Future<void> showMatchCorrectionDialog(
    BuildContext context, MediaItem song) {
  return showDialog(
    context: context,
    builder: (context) => MatchCorrectionDialog(song: song),
  );
}

/// Lets the user correct an automatic cross-catalog match by picking the
/// right version from a provider's search results. The choice is saved as a
/// remembered override and the song is re-resolved immediately.
class MatchCorrectionDialog extends StatefulWidget {
  const MatchCorrectionDialog({super.key, required this.song});

  final MediaItem song;

  @override
  State<MatchCorrectionDialog> createState() => _MatchCorrectionDialogState();
}

class _MatchCorrectionDialogState extends State<MatchCorrectionDialog> {
  late Future<List<ProviderCandidateGroup>> _future;

  /// Provider id currently saving an override (disables taps while busy).
  String? _busyProvider;

  @override
  void initState() {
    super.initState();
    _future = collectCorrectionCandidates(SongQuery.fromMediaItem(widget.song));
  }

  Future<void> _applyOverride(String providerId, String trackId) async {
    setState(() => _busyProvider = providerId);
    MatchOverrideStore.setOverride(providerId, widget.song.id, trackId);
    await _replayIfCurrentSong();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _clearOverride(String providerId) async {
    setState(() => _busyProvider = providerId);
    MatchOverrideStore.clearOverride(providerId, widget.song.id);
    await _replayIfCurrentSong();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Re-resolves the current song through the provider chain so the
  /// corrected match is heard immediately.
  Future<void> _replayIfCurrentSong() async {
    try {
      final playerController = Get.find<PlayerController>();
      if (playerController.currentSong.value?.id != widget.song.id) return;
      await Get.find<AudioHandler>().customAction('playByIndex', {
        'index': playerController.currentSongIndex.value,
        'newUrl': true,
      });
    } catch (_) {
      // Playback isn't available (e.g. preview/tests) — the override is
      // saved anyway and applies on the next play.
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      child: SizedBox(
        height: Get.mediaQuery.size.height * .7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: Text(
                'Correct source match',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'This song was matched automatically. Pick the right '
                'version below to lock it in for this source (remembered '
                'for next time).',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const Divider(),
            Expanded(
              child: FutureBuilder<List<ProviderCandidateGroup>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final groups = snapshot.data ?? const [];
                  if (groups.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No sources configured. Enable Qobuz or Tidal in '
                          'Settings → Sources to correct matches.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView(
                    children: [
                      for (final group in groups) ..._groupWidgets(group),
                    ],
                  );
                },
              ),
            ),
            const Divider(),
            SizedBox(
              height: 50,
              child: Align(
                alignment: Alignment.center,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10.0, horizontal: 25),
                    child: Text('close'.tr),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _groupWidgets(ProviderCandidateGroup group) {
    final override =
        MatchOverrideStore.getOverride(group.providerId, widget.song.id);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          group.displayName,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ),
      if (group.candidates.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('No candidates found on ${group.displayName}.'),
        )
      else
        for (final candidate in group.candidates)
          _candidateTile(group, candidate, override),
      if (override != null && override.isNotEmpty)
        ListTile(
          dense: true,
          leading: const Icon(Icons.auto_awesome, size: 20),
          title: Text(
            'Use automatic matching',
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary, fontSize: 13),
          ),
          onTap: _busyProvider == null
              ? () => _clearOverride(group.providerId)
              : null,
        ),
      const Divider(),
    ];
  }

  Widget _candidateTile(
    ProviderCandidateGroup group,
    TrackCandidate candidate,
    String? override,
  ) {
    final isCurrent = override == candidate.trackId;
    final busy = _busyProvider != null;
    final artists = candidate.artists.join(', ');
    final subtitleParts = [
      if (artists.isNotEmpty) artists,
      if (candidate.album != null && candidate.album!.isNotEmpty)
        candidate.album!,
      if (candidate.durationMs != null)
        _formatDuration(candidate.durationMs!),
    ];
    return ListTile(
      dense: true,
      leading: Icon(
        isCurrent ? Icons.radio_button_checked : Icons.music_note,
        color: isCurrent ? Theme.of(context).colorScheme.primary : null,
        size: 22,
      ),
      title: Text(candidate.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleParts.join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (candidate.qualityLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Text(
                candidate.qualityLabel!,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      onTap: busy
          ? null
          : () => _applyOverride(group.providerId, candidate.trackId),
    );
  }

  String _formatDuration(int durationMs) {
    final totalSeconds = durationMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
