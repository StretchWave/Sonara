import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../player_controller.dart';

/// Bottom sheet for adjusting the synced-lyrics resync offset of the
/// current song (tap lyric lines to seek, fine-tune timing here).
class LyricsOffsetSheet extends StatelessWidget {
  const LyricsOffsetSheet({super.key});

  String _formatOffset(int ms) {
    final sign = ms < 0 ? '-' : '+';
    final abs = ms.abs();
    final seconds = (abs / 1000).toStringAsFixed(2);
    return '$sign$seconds s';
  }

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Padding(
      padding: EdgeInsets.only(bottom: Get.mediaQuery.padding.bottom),
      child: Obx(
        () => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text("lyricsResync".tr),
              subtitle: Text("lyricsResyncDes".tr),
              trailing: TextButton(
                onPressed: playerController.resetLyricsOffset,
                child: Text("reset".tr),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _quickButton(context, playerController, -1000, '-1 s'),
                  _quickButton(context, playerController, -100, '-100 ms'),
                  _quickButton(context, playerController, 100, '+100 ms'),
                  _quickButton(context, playerController, 1000, '+1 s'),
                ],
              ),
            ),
            Slider(
              value: playerController.lyricsOffsetMs.value.toDouble(),
              min: -5000,
              max: 5000,
              divisions: 200,
              label: _formatOffset(playerController.lyricsOffsetMs.value),
              onChanged: (value) =>
                  playerController.setLyricsOffset(value.round()),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _formatOffset(playerController.lyricsOffsetMs.value),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickButton(
      BuildContext context, PlayerController controller, int delta, String label) {
    return TextButton(
      onPressed: () => controller.setLyricsOffset(
          controller.lyricsOffsetMs.value + delta),
      child: Text(label),
    );
  }
}
