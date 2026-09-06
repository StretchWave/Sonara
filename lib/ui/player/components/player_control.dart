import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:widget_marquee/widget_marquee.dart';

import '/services/providers/models/provider_id.dart';
import '/ui/player/components/animated_play_button.dart';
import '/ui/widgets/source_explanation_sheet.dart';
import '../player_controller.dart';

class PlayerControlWidget extends StatelessWidget {
  const PlayerControlWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: ShaderMask(
                  shaderCallback: (rect) {
                    return const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.transparent
                      ],
                    ).createShader(
                        Rect.fromLTWH(0, 0, rect.width, rect.height));
                  },
                  blendMode: BlendMode.dstIn,
                  child: Obx(() {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Marquee(
                          delay: const Duration(milliseconds: 300),
                          duration: const Duration(seconds: 10),
                          id: "${playerController.currentSong.value}_title",
                          child: Text(
                            playerController.currentSong.value != null
                                ? playerController.currentSong.value!.title
                                : "NA",
                            textAlign: TextAlign.start,
                            style: Theme.of(context).textTheme.labelMedium!,
                          ),
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        Marquee(
                          delay: const Duration(milliseconds: 300),
                          duration: const Duration(seconds: 10),
                          id: "${playerController.currentSong.value}_subtitle",
                          child: Text(
                            playerController.currentSong.value != null
                                ? playerController.currentSong.value!.artist!
                                : "NA",
                            textAlign: TextAlign.start,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        Obx(() {
                          final currentSong = playerController.currentSong.value;
                          if (currentSong == null) return const SizedBox.shrink();
                          final label = currentSong.extras?['streamLabel']?.toString();
                          final source = currentSong.extras?['streamSource']?.toString();
                          if (label == null && (source == null || source.isEmpty)) {
                            return const SizedBox.shrink();
                          }

                          final provider = ProviderId.fromStableId(source ?? '');
                          final providerName = provider?.displayName ?? (source ?? 'YouTube Music');
                          final display = (label != null && label.isNotEmpty) ? label : providerName;

                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                showSourceExplanationSheet(context, currentSong);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.graphic_eq,
                                      size: 12,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        display,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(
                                      Icons.info_outline,
                                      size: 11,
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        })
                      ],
                    );
                  }),
                ),
              ),
              SizedBox(
                width: 45,
                child: IconButton(
                    onPressed: playerController.toggleFavourite,
                    icon: Obx(() => Icon(
                          playerController.isCurrentSongFav.isFalse
                              ? Icons.favorite_border
                              : Icons.favorite,
                          color: Theme.of(context).textTheme.titleMedium!.color,
                        ))),
              ),
            ],
          ),
          const SizedBox(
            height: 20,
          ),
          GetX<PlayerController>(builder: (controller) {
            return ProgressBar(
              thumbRadius: 7,
              barHeight: 4.5,
              baseBarColor: Theme.of(context).sliderTheme.inactiveTrackColor,
              bufferedBarColor:
                  Theme.of(context).sliderTheme.valueIndicatorColor,
              progressBarColor: Theme.of(context).sliderTheme.activeTrackColor,
              thumbColor: Theme.of(context).sliderTheme.thumbColor,
              timeLabelTextStyle: Theme.of(context)
                  .textTheme
                  .titleMedium!
                  .copyWith(fontSize: 14),
              progress: controller.progressBarStatus.value.current,
              total: controller.progressBarStatus.value.total,
              buffered: controller.progressBarStatus.value.buffered,
              onSeek: controller.seek,
            );
          }),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                  onPressed: playerController.toggleShuffleMode,
                  icon: Obx(() => Icon(
                        Icons.shuffle,
                        color: playerController.isShuffleModeEnabled.value
                            ? Theme.of(context).textTheme.titleLarge!.color
                            : Theme.of(context)
                                .textTheme
                                .titleLarge!
                                .color!
                                .withOpacity(0.2),
                      ))),
              _previousButton(playerController, context),
              const CircleAvatar(radius: 35, child: AnimatedPlayButton(key: Key("playButton"),)),
              _nextButton(playerController, context),
              _speedButton(playerController, context),
              Obx(() {
                return IconButton(
                    onPressed: playerController.toggleLoopMode,
                    icon: Icon(
                      Icons.all_inclusive,
                      color: playerController.isLoopModeEnabled.value
                          ? Theme.of(context).textTheme.titleLarge!.color
                          : Theme.of(context)
                              .textTheme
                              .titleLarge!
                              .color!
                              .withOpacity(0.2),
                    ));
              }),
            ],
          ),
        ]);
  }

  /// Varispeed button: shows the current speed and opens a picker.
  Widget _speedButton(PlayerController playerController, BuildContext context) {
    return Obx(() {
      final speed = playerController.playbackSpeed.value;
      final speedText = speed == speed.roundToDouble()
          ? "${speed.toInt()}x"
          : "${speed}x";
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showModalBottomSheet(
            constraints: const BoxConstraints(maxWidth: 500),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(10.0)),
            ),
            isScrollControlled: true,
            context: playerController.homeScaffoldkey.currentState!.context,
            barrierColor: Colors.transparent.withAlpha(100),
            builder: (context) => _SpeedSelectorSheet(
              currentSpeed: speed,
              onSelected: playerController.setPlaybackSpeed,
            ),
          ),
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).textTheme.titleMedium!.color!,
                width: 1.2,
              ),
            ),
            child: Text(
              speedText,
              style: Theme.of(context).textTheme.titleSmall!.copyWith(
                    color: Theme.of(context).textTheme.titleMedium!.color,
                    fontSize: 12,
                  ),
            ),
          ),
        ),
      );
    });
  }


  Widget _previousButton(
      PlayerController playerController, BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.skip_previous,
        color: Theme.of(context).textTheme.titleMedium!.color,
      ),
      iconSize: 30,
      onPressed: playerController.prev,
    );
  }
}

Widget _nextButton(PlayerController playerController, BuildContext context) {
  return Obx(() {
    final isLastSong = playerController.currentQueue.isEmpty ||
        (!(playerController.isShuffleModeEnabled.isTrue ||
                playerController.isQueueLoopModeEnabled.isTrue) &&
            (playerController.currentQueue.last.id ==
                playerController.currentSong.value?.id));
    return IconButton(
        icon: Icon(
          Icons.skip_next,
          color: isLastSong
              ? Theme.of(context).textTheme.titleLarge!.color!.withOpacity(0.2)
              : Theme.of(context).textTheme.titleMedium!.color,
        ),
        iconSize: 30,
        onPressed: isLastSong ? null : playerController.next);
  });
}

/// Bottom sheet with the available playback speeds.
class _SpeedSelectorSheet extends StatelessWidget {
  const _SpeedSelectorSheet({
    required this.currentSpeed,
    required this.onSelected,
  });

  static const List<double> speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  final double currentSpeed;
  final ValueChanged<double> onSelected;

  String _label(double speed) => speed == speed.roundToDouble()
      ? "${speed.toInt()}.0x"
      : "${speed}x";

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: Get.mediaQuery.padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.speed),
            title: Text("playbackSpeed".tr),
          ),
          const Divider(),
          for (final speed in speeds)
            ListTile(
              onTap: () {
                Navigator.of(context).pop();
                onSelected(speed);
              },
              leading: Icon(
                speed == currentSpeed
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
              ),
              title: Text(
                _label(speed),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
        ],
      ),
    );
  }
}
