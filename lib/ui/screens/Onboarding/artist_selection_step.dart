import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/music_service.dart';
import '../../../services/onboarding_controller.dart';
import 'curated_artists_data.dart';
import 'language_selection_step.dart';

/// Third onboarding step: artist multi-select.
///
/// Features up to 50 curated artist options tailored to the user's chosen languages,
/// real-time search across YouTube Music, circular avatars matching Sonara's design,
/// and smooth selection states.
class ArtistSelectionStep extends StatefulWidget {
  const ArtistSelectionStep({super.key, this.onComplete});

  /// Optional callback for login-later flow.
  final VoidCallback? onComplete;

  @override
  State<ArtistSelectionStep> createState() => _ArtistSelectionStepState();
}

class _ArtistSelectionStepState extends State<ArtistSelectionStep> {
  final OnboardingController _onboarding = Get.find<OnboardingController>();
  final MusicServices _musicServices = Get.find<MusicServices>();

  final List<Map<String, dynamic>> _artists = [];
  final Set<String> _selectedIds = {};
  final Map<String, Map<String, dynamic>> _selectedArtistsMap = {};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchingOnline = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();

    // 1. Pre-select any previously chosen artists
    for (final a in _onboarding.favoriteArtists) {
      final id = a['browseId']?.toString() ?? a['name']?.toString() ?? '';
      if (id.isNotEmpty) {
        _selectedIds.add(id);
        _selectedArtistsMap[id] = Map<String, dynamic>.from(a);
      }
    }

    // 2. Load curated artists matching user's selected languages (up to 50 options)
    _loadCuratedArtists();

    // 3. Kick off background enhancement to fetch thumbnails & more artists
    _augmentArtistsFromNetwork();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _loadCuratedArtists() {
    final curated = CuratedArtistsData.getCuratedArtists(
      languageCodes: _onboarding.musicLanguages,
      targetCount: 50,
    );
    _artists.addAll(curated);
  }

  Future<void> _augmentArtistsFromNetwork() async {
    try {
      final langs = _onboarding.musicLanguages;
      final seenNames = _artists
          .map((a) => a['name']?.toString().toLowerCase() ?? '')
          .toSet();

      // Collect top queries based on user's selected languages
      final queries = <String>[];
      if (langs.isEmpty) {
        queries.add('top popular artists');
      } else {
        for (final code in langs.take(3)) {
          final langName = musicLanguageMap[code] ?? code;
          queries.add('$langName top artists');
        }
      }

      for (final query in queries) {
        try {
          final results = await _musicServices.search(query, filter: 'artists');
          final list = results['Artists'] ?? results['artists'] ?? [];
          if (list is List) {
            for (final artist in list) {
              if (artist == null) continue;
              final name = _extractName(artist);
              final browseId = _extractBrowseId(artist);
              final thumb = _extractThumbnail(artist);

              if (name.isEmpty || name == 'Unknown') continue;

              // Check if already present to update thumbnail
              final existingIndex = _artists.indexWhere((a) =>
                  a['name']?.toString().toLowerCase() == name.toLowerCase());

              if (existingIndex >= 0) {
                if (_artists[existingIndex]['thumbnailUrl'] == '' &&
                    thumb.isNotEmpty) {
                  _artists[existingIndex]['thumbnailUrl'] = thumb;
                }
              } else if (!seenNames.contains(name.toLowerCase())) {
                seenNames.add(name.toLowerCase());
                if (_artists.length < 50) {
                  _artists.add({
                    'name': name,
                    'browseId': browseId ?? name,
                    'thumbnailUrl': thumb,
                  });
                }
              }
            }
          }
        } catch (_) {}
      }

      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _onSearchChanged(String query) {
    setState(() => _searchQuery = query.trim());

    _debounceTimer?.cancel();
    if (query.trim().length >= 2) {
      _debounceTimer = Timer(const Duration(milliseconds: 450), () {
        _performOnlineSearch(query.trim());
      });
    }
  }

  Future<void> _performOnlineSearch(String query) async {
    if (query.isEmpty) return;
    setState(() => _isSearchingOnline = true);

    try {
      final results = await _musicServices.search(query, filter: 'artists');
      final list = results['Artists'] ?? results['artists'] ?? [];

      if (list is List && mounted) {
        final existingNames =
            _artists.map((a) => a['name']?.toString().toLowerCase()).toSet();

        for (final item in list) {
          if (item == null) continue;
          final name = _extractName(item);
          final browseId = _extractBrowseId(item);
          final thumb = _extractThumbnail(item);

          if (name.isNotEmpty &&
              name != 'Unknown' &&
              !existingNames.contains(name.toLowerCase())) {
            existingNames.add(name.toLowerCase());
            _artists.insert(0, {
              'name': name,
              'browseId': browseId ?? name,
              'thumbnailUrl': thumb,
            });
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() => _isSearchingOnline = false);
    }
  }

  String? _extractBrowseId(dynamic artist) {
    if (artist is Map) return artist['browseId']?.toString();
    try {
      return (artist as dynamic).browseId?.toString();
    } catch (_) {
      return null;
    }
  }

  String _extractName(dynamic artist) {
    if (artist is Map) {
      return artist['artist']?.toString() ??
          artist['name']?.toString() ??
          'Unknown';
    }
    try {
      return (artist as dynamic).name?.toString() ?? 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  String _extractThumbnail(dynamic artist) {
    if (artist is Map) {
      final thumbs = artist['thumbnails'];
      if (thumbs is List && thumbs.isNotEmpty) {
        return thumbs.last['url']?.toString() ?? '';
      }
      return artist['thumbnailUrl']?.toString() ?? '';
    }
    try {
      return (artist as dynamic).thumbnailUrl?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  void _toggleArtist(Map<String, dynamic> artist) {
    final id = artist['browseId']?.toString() ?? artist['name'].toString();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        _selectedArtistsMap.remove(id);
      } else {
        _selectedIds.add(id);
        _selectedArtistsMap[id] = artist;
      }
    });
  }

  void _finish() {
    final selected = _selectedArtistsMap.values.toList();
    _onboarding.setFavoriteArtists(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.secondary;
    final textColor = theme.textTheme.bodyMedium?.color;
    final size = MediaQuery.of(context).size;
    final horizontalPad = size.width > 600 ? size.width * 0.12 : 20.0;

    final displayedArtists = _artists.where((a) {
      if (_searchQuery.isEmpty) return true;
      final name = a['name']?.toString().toLowerCase() ?? '';
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        // Header Section
        Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              Text(
                "Artists you like",
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Pick some artists to calibrate your taste profile and Discover recommendations.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: textColor?.withValues(alpha: 0.65),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // Search Bar matching Sonara search styling
              Container(
                height: 46,
                decoration: BoxDecoration(
                  color: theme.primaryColorLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _isSearchingOnline
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primaryColor,
                            ),
                          )
                        : Icon(
                            Icons.search_rounded,
                            color: textColor?.withValues(alpha: 0.5),
                            size: 20,
                          ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: textColor, fontSize: 14),
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: "Search any artist...",
                          hintStyle: TextStyle(
                            color: textColor?.withValues(alpha: 0.4),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: Icon(
                          Icons.close_rounded,
                          color: textColor?.withValues(alpha: 0.5),
                          size: 18,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Selection Counter Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${_selectedIds.length} ${_selectedIds.length == 1 ? 'artist' : 'artists'} selected",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                  if (_selectedIds.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() {
                        _selectedIds.clear();
                        _selectedArtistsMap.clear();
                      }),
                      child: Text(
                        "Clear all",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: textColor?.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),

        // Selected Artists Tray (Horizontal Chips)
        if (_selectedArtistsMap.isNotEmpty) ...[
          Container(
            height: 38,
            padding: EdgeInsets.symmetric(horizontal: horizontalPad),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _selectedArtistsMap.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final artist = _selectedArtistsMap.values.elementAt(index);
                final id = artist['browseId']?.toString() ??
                    artist['name']?.toString() ??
                    '';
                return Chip(
                  backgroundColor: primaryColor.withValues(alpha: 0.18),
                  side: BorderSide(color: primaryColor, width: 1.2),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text(
                    artist['name']?.toString() ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                  deleteIcon: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: primaryColor,
                  ),
                  onDeleted: () {
                    setState(() {
                      _selectedIds.remove(id);
                      _selectedArtistsMap.remove(id);
                    });
                  },
                );
              },
            ),
          ),
        ],

        // Artists Grid (Up to 50 options)
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPad),
            child: displayedArtists.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_search_rounded,
                          size: 48,
                          color: textColor?.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "No artists found",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textColor?.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Try searching for another artist or skip this step.",
                          style: TextStyle(
                            fontSize: 13,
                            color: textColor?.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(top: 8, bottom: 90),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: size.width > 600 ? 5 : 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: displayedArtists.length,
                    itemBuilder: (context, index) {
                      final artist = displayedArtists[index];
                      final id = artist['browseId']?.toString() ??
                          artist['name'].toString();
                      final isSelected = _selectedIds.contains(id);

                      return _ArtistCard(
                        artist: artist,
                        isSelected: isSelected,
                        primaryColor: primaryColor,
                        textColor: textColor,
                        onTap: () => _toggleArtist(artist),
                      );
                    },
                  ),
          ),
        ),

        // Bottom Action Bar
        _buildBottomBar(context, primaryColor, textColor),
      ],
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    Color primaryColor,
    Color? textColor,
  ) {
    final theme = Theme.of(context);
    final isSelected = _selectedIds.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isSelected ? primaryColor : theme.primaryColorLight,
              foregroundColor: isSelected ? Colors.black : textColor?.withValues(alpha: 0.6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () {
              if (isSelected) {
                _finish();
              } else {
                _onboarding.skipArtists();
              }
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isSelected ? "Finish & Start Listening" : "Continue without Artists",
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  const _ArtistCard({
    required this.artist,
    required this.isSelected,
    required this.primaryColor,
    required this.textColor,
    required this.onTap,
  });

  final Map<String, dynamic> artist;
  final bool isSelected;
  final Color primaryColor;
  final Color? textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = artist['name']?.toString() ?? 'Artist';
    final thumb = artist['thumbnailUrl']?.toString() ?? '';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.14)
              : theme.primaryColorLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : theme.dividerColor.withValues(alpha: 0.12),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Circular Avatar with Sonara border & badge
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? primaryColor : Colors.transparent,
                      width: 2.2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: primaryColor.withValues(alpha: 0.35),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipOval(
                    child: thumb.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: thumb,
                            fit: BoxFit.cover,
                            memCacheHeight: 130,
                            memCacheWidth: 130,
                            placeholder: (_, __) => _buildInitials(name, theme),
                            errorWidget: (_, __, ___) =>
                                _buildInitials(name, theme),
                          )
                        : _buildInitials(name, theme),
                  ),
                ),
                if (isSelected)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: primaryColor,
                        border: Border.all(
                          color: theme.scaffoldBackgroundColor,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: Colors.black,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Artist Name
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 12.5,
                  color: isSelected ? primaryColor : textColor,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitials(String name, ThemeData theme) {
    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').map((p) => p.isNotEmpty ? p[0] : '').take(2).join()
        : 'A';

    return Container(
      color: theme.colorScheme.secondary.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        initials.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
  }
}
