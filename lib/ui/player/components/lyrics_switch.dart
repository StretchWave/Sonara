import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:harmonymusic/ui/utils/theme_controller.dart';
import 'package:toggle_switch/toggle_switch.dart';

import '../player_controller.dart';
import 'lyrics_offset_sheet.dart';

class LyricsSwitch extends StatelessWidget {
  const LyricsSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final PlayerController playerController = Get.find<PlayerController>();
    return Obx(
      () => playerController.showLyricsflag.value
          ? Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ToggleSwitch(
                    minWidth: 90.0,
                    cornerRadius: 20.0,
                    activeBgColors: [
                      [Theme.of(context).primaryColor.withLightness(0.4)],
                      [Theme.of(context).primaryColor.withLightness(0.4)]
                    ],
                    activeFgColor: Colors.white,
                    inactiveBgColor: Theme.of(context).colorScheme.secondary,
                    inactiveFgColor: Colors.white,
                    initialLabelIndex: playerController.lyricsMode.value,
                    totalSwitches: 2,
                    labels: ['synced'.tr, 'plain'.tr],
                    radiusStyle: true,
                    onToggle: playerController.changeLyricsMode,
                  ),
                  if (playerController.lyricsMode.value == 0) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: "lyricsResync".tr,
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      onPressed: () => showModalBottomSheet(
                        constraints: const BoxConstraints(maxWidth: 500),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(10.0)),
                        ),
                        isScrollControlled: true,
                        context: playerController
                            .homeScaffoldkey.currentState!.context,
                        barrierColor: Colors.transparent.withAlpha(100),
                        builder: (context) => const LyricsOffsetSheet(),
                      ),
                      icon: Icon(
                        Icons.tune,
                        color: Theme.of(context).textTheme.titleMedium!.color,
                      ),
                    ),
                  ],
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
