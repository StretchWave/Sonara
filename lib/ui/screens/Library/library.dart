import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '/services/ytaccount/yt_account_service.dart';
import '/ui/widgets/modification_list.dart';
import '../../../models/playlist.dart';
import '../../widgets/piped_sync_widget.dart';
import 'library_controller.dart';
import '../../widgets/content_list_widget_item.dart';
import '../../widgets/list_widget.dart';
import '../../widgets/sort_widget.dart';
import '../Settings/settings_screen_controller.dart';

class SongsLibraryWidget extends StatelessWidget {
  const SongsLibraryWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(left: 5.0, top: topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isBottomNavActive
              ? const SizedBox(
                  height: 10,
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "libSongs".tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
          Obx(() {
            final libSongsController = Get.find<LibrarySongsController>();
            return SortWidget(
              tag: "LibSongSort",
              screenController: libSongsController,
              itemCountTitle: "${libSongsController.librarySongsList.length}",
              itemIcon: Icons.music_note,
              titleLeftPadding: 9,
              requiredSortTypes: buildSortTypeSet(true, true),
              isSearchFeatureRequired: true,
              isSongDeletetioFeatureRequired: true,
              onSort: (type, ascending) {
                libSongsController.onSort(type, ascending);
              },
              onSearch: libSongsController.onSearch,
              onSearchClose: libSongsController.onSearchClose,
              onSearchStart: libSongsController.onSearchStart,
              startAdditionalOperation:
                  libSongsController.startAdditionalOperation,
              selectAll: libSongsController.selectAll,
              performAdditionalOperation:
                  libSongsController.performAdditionalOperation,
              cancelAdditionalOperation:
                  libSongsController.cancelAdditionalOperation,
            );
          }),
          GetX<LibrarySongsController>(builder: (controller) {
            return controller.librarySongsList.isNotEmpty
                ? (controller.additionalOperationMode.value ==
                        OperationMode.none
                    ? ListWidget(
                        controller.librarySongsList,
                        "library Songs",
                        true,
                        isPlaylistOrAlbum: true,
                        playlist: Playlist(
                            title: "Library Songs",
                            playlistId: "SongsDownloads",
                            thumbnailUrl: "",
                            isCloudPlaylist: false),
                      )
                    : ModificationList(
                        mode: controller.additionalOperationMode.value,
                        screenController: controller,
                      ))
                : Expanded(
                    child: Center(
                        child: Text(
                      "noOfflineSong".tr,
                      style: Theme.of(context).textTheme.titleMedium,
                    )),
                  );
          })
        ],
      ),
    );
  }
}

class PlaylistNAlbumLibraryWidget extends StatelessWidget {
  const PlaylistNAlbumLibraryWidget(
      {super.key, this.isAlbumContent = true, this.isBottomNavActive = false});
  final bool isAlbumContent;
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final libralbumCntrller = Get.find<LibraryAlbumsController>();
    final librplstCntrller = Get.find<LibraryPlaylistsController>();
    final settingscrnController = Get.find<SettingsScreenController>();
    final size = MediaQuery.of(context).size;

    const double itemHeight = 180;
    const double itemWidth = 130;
    final topPadding = context.isLandscape ? 50.0 : 90.0;

    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(top: topPadding),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 5.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                isBottomNavActive
                    ? const SizedBox(
                        height: 10,
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isAlbumContent ? "libAlbums".tr : "libPlaylists".tr,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                (settingscrnController.isBottomNavBarEnabled.isTrue ||
                        isAlbumContent ||
                        settingscrnController.isLinkedWithPiped.isFalse)
                    ? const SizedBox.shrink()
                    : PipedSyncWidget(
                        padding: EdgeInsets.only(right: size.width * .05),
                      )
              ],
            ),
          ),
          Obx(
            () => isAlbumContent
                ? SortWidget(
                    tag: "LibAlbumSort",
                    screenController: libralbumCntrller,
                    isAdditionalOperationRequired: false,
                    isSearchFeatureRequired: true,
                    itemCountTitle:
                        "${libralbumCntrller.libraryAlbums.length} ${"items".tr}",
                    requiredSortTypes: buildSortTypeSet(true),
                    onSort: (type, ascending) {
                      libralbumCntrller.onSort(type, ascending);
                    },
                    onSearch: libralbumCntrller.onSearch,
                    onSearchClose: libralbumCntrller.onSearchClose,
                    onSearchStart: libralbumCntrller.onSearchStart,
                  )
                : SortWidget(
                    tag: "LibPlaylistSort",
                    screenController: librplstCntrller,
                    isAdditionalOperationRequired: false,
                    isSearchFeatureRequired: true,
                    itemCountTitle:
                        "${librplstCntrller.libraryPlaylists.length} ${"items".tr}",
                    requiredSortTypes: buildSortTypeSet(),
                    onSort: (type, ascending) {
                      librplstCntrller.onSort(type, ascending);
                    },
                    onSearch: librplstCntrller.onSearch,
                    onSearchClose: librplstCntrller.onSearchClose,
                    onSearchStart: librplstCntrller.onSearchStart,
                    isImportFeatureRequired: true,
                  ),
          ),
          YtMirrorSection(kind: isAlbumContent ? 'album' : 'playlist'),
          Expanded(
            child: Obx(
              () => (isAlbumContent
                      ? libralbumCntrller.libraryAlbums.isNotEmpty
                      : librplstCntrller.libraryPlaylists.isNotEmpty)
                  ? LayoutBuilder(builder: (context, constraints) {
                      //Fix for grid in mobile screen
                      final availableWidth = constraints.maxWidth > 300 &&
                              constraints.maxWidth < 394
                          ? 310.0
                          : constraints.maxWidth;
                      int columns = (availableWidth / itemWidth).floor();
                      return SizedBox(
                        width: availableWidth,
                        child: GridView.builder(
                            physics: const BouncingScrollPhysics(),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              childAspectRatio: (itemWidth / itemHeight),
                            ),
                            controller:
                                ScrollController(keepScrollOffset: false),
                            shrinkWrap: true,
                            scrollDirection: Axis.vertical,
                            padding:
                                const EdgeInsets.only(bottom: 200, top: 10),
                            itemCount: isAlbumContent
                                ? libralbumCntrller.libraryAlbums.length
                                : librplstCntrller.libraryPlaylists.length,
                            itemBuilder: (context, index) => Center(
                                  child: ContentListItem(
                                    content: isAlbumContent
                                        ? libralbumCntrller.libraryAlbums[index]
                                        : librplstCntrller
                                            .libraryPlaylists[index],
                                    isLibraryItem: true,
                                  ),
                                )),
                      );
                    })
                  : Center(
                      child: Text(
                      "noBookmarks".tr,
                      style: Theme.of(context).textTheme.titleMedium,
                    )),
            ),
          )
        ],
      ),
    );
  }
}

class LibraryArtistWidget extends StatelessWidget {
  const LibraryArtistWidget({super.key, this.isBottomNavActive = false});
  final bool isBottomNavActive;

  @override
  Widget build(BuildContext context) {
    final cntrller = Get.find<LibraryArtistsController>();
    final topPadding = context.isLandscape ? 50.0 : 90.0;
    return Padding(
      padding: isBottomNavActive
          ? const EdgeInsets.only(left: 15)
          : EdgeInsets.only(left: 5, top: topPadding),
      child: Column(
        children: [
          isBottomNavActive
              ? const SizedBox(
                  height: 10,
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "libArtists".tr,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
          Obx(
            () => SortWidget(
              tag: "LibArtistSort",
              screenController: cntrller,
              isAdditionalOperationRequired: false,
              isSearchFeatureRequired: true,
              itemCountTitle: "${cntrller.libraryArtists.length} ${"items".tr}",
              onSort: (type, ascending) {
                cntrller.onSort(type, ascending);
              },
              onSearch: cntrller.onSearch,
              onSearchClose: cntrller.onSearchClose,
              onSearchStart: cntrller.onSearchStart,
            ),
          ),
          YtMirrorSection(kind: 'artist'),
          Obx(() => cntrller.libraryArtists.isNotEmpty
              ? ListWidget(cntrller.libraryArtists, "Library Artists", true)
              : Expanded(
                  child: Center(
                      child: Text(
                  "noBookmarks".tr,
                  style: Theme.of(context).textTheme.titleMedium,
                ))))
        ],
      ),
    );
  }
}

class YtMirrorSection extends StatelessWidget {
  const YtMirrorSection({super.key, required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) {
    final ytLibController = Get.find<YtLibraryController>();
    final ytAccount = Get.find<YtAccountService>();
    String sectionTitle() => switch (kind) {
          'album' => "ytAccountAlbumsSection".tr,
          'artist' => "ytAccountArtistsSection".tr,
          _ => "ytAccountPlaylistsSection".tr,
        };
    final items = switch (kind) {
          'album' => ytLibController.ytAlbums,
          'artist' => ytLibController.ytArtists,
          _ => ytLibController.ytPlaylists,
        };

    return Obx(() {
      if (ytAccount.isLoggedIn.isFalse ||
          (items.isEmpty && ytLibController.isYtFetched.isTrue)) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4, left: 5, right: 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(sectionTitle(),
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: ytLibController.refetch,
                    icon: const Icon(Icons.sync, size: 18)),
              ],
            ),
            if (kind == 'playlist')
              Obx(() => TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).textTheme.titleSmall!.color,
                        padding: const EdgeInsets.only(left: 5)),
                    onPressed: ytLibController.isFavouriteImporting.value
                        ? null
                        : ytLibController.mergeLikedSongsToFavourites,
                    icon: ytLibController.isFavouriteImporting.value
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.favorite_border, size: 15),
                    label: Text("ytAccountLikedImport".tr,
                        style: Theme.of(context).textTheme.bodyMedium),
                  )),
            const SizedBox(height: 6),
            SizedBox(
              height: 172,
              child: items.isEmpty
                  ? const Center(
                      child: SizedBox(
                        width: 21,
                        height: 21,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(right: 10),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) =>
                          YtMirrorCard(item: items[index]),
                    ),
            ),
          ],
        ),
      );
    });
  }
}

class YtMirrorCard extends StatelessWidget {
  const YtMirrorCard({super.key, required this.item});
  final Map<String, dynamic> item;

  static String _assetForKind(String kind) => switch (kind) {
        'artist' => "assets/icons/artist.png",
        'album' => "assets/icons/album.png",
        _ => "assets/icons/song.png",
      };

  @override
  Widget build(BuildContext context) {
    final ytLibController = Get.find<YtLibraryController>();
    final isArtist = item['kind'] == 'artist';
    final thumbUrl = (item['thumbnailUrl'] ?? "").toString();
    final assetIcon = _assetForKind((item['kind'] ?? "").toString());
    return GestureDetector(
      onTap: () => ytLibController.openYtItem(item),
      child: SizedBox(
        width: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(isArtist ? 65 : 10),
              child: Container(
                height: 115,
                width: 115,
                color: Theme.of(context).colorScheme.secondary,
                child: thumbUrl.isEmpty
                    ? Image.asset(assetIcon)
                    : CachedNetworkImage(
                        imageUrl: thumbUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Image.asset(assetIcon),
                      ),
              ),
            ),
            const SizedBox(height: 5),
            Text((item['title'] ?? "").toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
            Text((item['subtitle'] ?? "").toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall!
                    .copyWith(color: Theme.of(context).colorScheme.onSurface)),
          ],
        ),
      ),
    );
  }
}
