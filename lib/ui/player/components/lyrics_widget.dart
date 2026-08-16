import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import 'package:flutter_lyric/lyrics_reader_model.dart';
import 'package:get/get.dart';

import '../../../services/lyrics_utils.dart';
import '../../widgets/loader.dart';
import '../player_controller.dart';

class LyricsWidget extends StatelessWidget {
  final EdgeInsetsGeometry padding;
  const LyricsWidget({super.key, required this.padding});

  @override
  Widget build(BuildContext context) {
    final playerController = Get.find<PlayerController>();
    return Obx(
      () => playerController.isLyricsLoading.isTrue
          ? const Center(
              child: LoadingIndicator(),
            )
          : playerController.lyricsMode.toInt() == 1
              ? Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: padding,
                    child: Obx(
                      () => TextSelectionTheme(
                        data: Theme.of(context).textSelectionTheme,
                        child: SelectableText(
                          playerController.lyrics["plainLyrics"] == "NA"
                              ? "lyricsNotAvailable".tr
                              : playerController.lyrics["plainLyrics"],
                          textAlign: TextAlign.center,
                          style: playerController.isDesktopLyricsDialogOpen
                              ? Theme.of(context).textTheme.titleMedium!
                              : Theme.of(context)
                                  .textTheme
                                  .titleMedium!
                                  .copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                )
              : _SyncedLyricsView(playerController: playerController),
    );
  }
}

class _SyncedLyricsView extends StatefulWidget {
  const _SyncedLyricsView({required this.playerController});

  final PlayerController playerController;

  @override
  State<_SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<_SyncedLyricsView> {
  bool _selectMode = false;
  int _selectedStartTime = 0;
  String _selectedText = '';
  Timer? _selectTimer;

  @override
  void dispose() {
    _selectTimer?.cancel();
    super.dispose();
  }

  void _armSelection(LyricsReaderModel model) {
    final position = widget.playerController
        .progressBarStatus.value.current.inMilliseconds;
    final index = model.getCurrentLine(position);
    final line = model.lyrics[index];
    setState(() {
      _selectMode = true;
      _selectedStartTime = line.startTime ?? 0;
      _selectedText = line.mainText ?? '';
    });
    _selectTimer?.cancel();
    _selectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _selectMode = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerController = widget.playerController;
    final raw = playerController.lyrics['synced'].toString();
    final isQrc = playerController.lyrics['format'] == 'qrc';
    final offset = playerController.lyricsOffsetMs.value;

    // Apply the user resync offset to the lyric timestamps.
    final text = offset == 0 ? raw : LyricsUtils.shiftLyrics(raw, offset);
    final model = isQrc
        ? LyricsModelBuilder.create()
            .bindLyricToMain(text, ParserQrc(text))
            .getModel()
        : LyricsModelBuilder.create().bindLyricToMain(text).getModel();

    return Stack(
      children: [
        // Rebuild on every playback-position tick so the active line
        // advances with the song (LyricsReader re-selects the line when its
        // `position` changes). The model itself is built once, outside the
        // Obx, so the LRC parse never runs per tick.
        Obx(() => LyricsReader(
              padding: const EdgeInsets.only(left: 5, right: 5),
              lyricUi: playerController.lyricUi,
              position: playerController
                  .progressBarStatus.value.current.inMilliseconds,
              model: model,
              emptyBuilder: () => Center(
                child: Text(
                  "syncedLyricsNotAvailable".tr,
                  style: playerController.isDesktopLyricsDialogOpen
                      ? Theme.of(context).textTheme.titleMedium!
                      : Theme.of(context)
                          .textTheme
                          .titleMedium!
                          .copyWith(color: Colors.white),
                ),
              ),
            )),
        // Tap layer: a tap arms selection on the current lyric line.
        // (Only taps are handled here, so lyric scrolling still works.)
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _armSelection(model),
          ),
        ),
        // Select chip: tapping it seeks playback to that line.
        if (_selectMode)
          Align(
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () {
                playerController.seek(Duration(milliseconds: _selectedStartTime));
                setState(() => _selectMode = false);
                _selectTimer?.cancel();
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 30),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow,
                        size: 18, color: Colors.white),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _selectedText.isEmpty
                            ? "tapToSeek".tr
                            : _selectedText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
