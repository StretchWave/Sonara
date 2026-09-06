import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../screens/Settings/settings_screen_controller.dart';
import '../../utils/theme_controller.dart';
import '../player_controller.dart';

class BackgroudImage extends StatelessWidget {
  const BackgroudImage({super.key, this.cacheHeight});

  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    return GetX<PlayerController>(
      builder: (playerController) {
        final song = playerController.currentSong.value;
        if (song == null) {
          return const SizedBox.expand();
        }

        final isLocal = (song.extras?['url'] as String? ?? '').contains('file');

        return SizedBox.expand(
          child: isLocal
              ? Builder(builder: (context) {
                  final imgFile = File(
                      "${Get.find<SettingsScreenController>().supportDirPath}/thumbnails/${song.id}.png");
                  return FutureBuilder<bool>(
                    future: imgFile.exists(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done &&
                          snapshot.data == true) {
                        if (Get.find<SettingsScreenController>()
                                .themeModetype
                                .value ==
                            ThemeType.dynamic) {
                          Get.find<ThemeController>()
                              .setTheme(FileImage(imgFile), song.id);
                        }

                        return Image.file(
                          imgFile,
                          cacheHeight: cacheHeight,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: Theme.of(context).primaryColor),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  );
                })
              : Builder(builder: (context) {
                  final artUriStr = song.artUri?.toString() ?? '';
                  if (artUriStr.isEmpty) {
                    return Container(color: Theme.of(context).primaryColor);
                  }

                  return CachedNetworkImage(
                    memCacheHeight: cacheHeight,
                    imageUrl: artUriStr,
                    fit: BoxFit.cover,
                    imageBuilder: (context, imageProvider) {
                      if (Get.find<SettingsScreenController>()
                              .themeModetype
                              .value ==
                          ThemeType.dynamic) {
                        Future.delayed(
                          const Duration(milliseconds: 50),
                          () => Get.find<ThemeController>()
                              .setTheme(imageProvider, song.id),
                        );
                      }
                      return Image(
                        image: imageProvider,
                        fit: BoxFit.cover,
                      );
                    },
                    placeholder: (context, url) =>
                        Container(color: Theme.of(context).primaryColor),
                    errorWidget: (context, url, error) =>
                        Container(color: Theme.of(context).primaryColor),
                  );
                }),
        );
      },
    );
  }
}
