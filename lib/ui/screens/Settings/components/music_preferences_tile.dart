import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../services/music_service.dart';
import '../../../../services/onboarding_controller.dart';
import '../../Onboarding/curated_artists_data.dart';
import '../../Onboarding/language_selection_step.dart';

/// Settings tile showing the user's current music language and artist
/// preferences, with an option to edit them.
class MusicPreferencesTile extends StatelessWidget {
  const MusicPreferencesTile({super.key});

  @override
  Widget build(BuildContext context) {
    final onboarding = Get.find<OnboardingController>();
    final theme = Theme.of(context);

    return Obx(() {
      final langs = onboarding.musicLanguages;
      final artists = onboarding.favoriteArtists;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Music Languages
          ListTile(
            contentPadding: const EdgeInsets.only(left: 5, right: 10),
            leading: const Icon(Icons.language),
            title: const Text('Music Languages'),
            subtitle: langs.isEmpty
                ? Text(
                    'Not set — tap to select',
                    style: theme.textTheme.bodyMedium,
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: langs.map((code) {
                      final name = musicLanguageMap[code] ?? code;
                      return Chip(
                        label: Text(name, style: const TextStyle(fontSize: 12)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }).toList(),
                  ),
            onTap: () => _showLanguageEditor(context, onboarding),
          ),

          // Favourite Artists
          ListTile(
            contentPadding: const EdgeInsets.only(left: 5, right: 10),
            leading: const Icon(Icons.people_outline),
            title: const Text('Favorite Artists'),
            subtitle: artists.isEmpty
                ? Text(
                    'Not set — tap to select',
                    style: theme.textTheme.bodyMedium,
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: artists.map((a) {
                      final name = a['name']?.toString() ?? 'Unknown';
                      return Chip(
                        label: Text(name, style: const TextStyle(fontSize: 12)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }).toList(),
                  ),
            onTap: () => _showArtistEditor(context, onboarding),
          ),
        ],
      );
    });
  }

  void _showLanguageEditor(
      BuildContext context, OnboardingController onboarding) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.secondary;
    final selected = Set<String>.from(onboarding.musicLanguages);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Music Languages'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: musicLanguageMap.entries.map((entry) {
                  final isSelected = selected.contains(entry.key);
                  return FilterChip(
                    label: Text(
                      entry.value,
                      style: TextStyle(
                        color: isSelected ? Colors.white : null,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (val) {
                      setDialogState(() {
                        if (val) {
                          selected.add(entry.key);
                        } else {
                          selected.remove(entry.key);
                        }
                      });
                    },
                    selectedColor: primaryColor,
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            if (selected.isNotEmpty)
              TextButton(
                onPressed: () {
                  setDialogState(() => selected.clear());
                },
                child: const Text('Clear'),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                onboarding.setMusicLanguages(selected.toList());
                // Reset step to complete since this is from settings
                onboarding.currentStep.value = OnboardingStep.complete;
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showArtistEditor(
      BuildContext context, OnboardingController onboarding) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('Favorite Artists'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: SafeArea(
            child: _SettingsArtistPicker(
              onboarding: onboarding,
              onDone: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }
}

/// A simplified artist picker reusing the same logic as the onboarding
/// artist step, but used from settings (editable after onboarding).
class _SettingsArtistPicker extends StatefulWidget {
  const _SettingsArtistPicker({
    required this.onboarding,
    required this.onDone,
  });

  final OnboardingController onboarding;
  final VoidCallback onDone;

  @override
  State<_SettingsArtistPicker> createState() => _SettingsArtistPickerState();
}

class _SettingsArtistPickerState extends State<_SettingsArtistPicker> {
  @override
  Widget build(BuildContext context) {
    return _ArtistSelectionInline(
      onboarding: widget.onboarding,
      onDone: widget.onDone,
    );
  }
}

/// Inline version of artist selection for the settings editor.
class _ArtistSelectionInline extends StatefulWidget {
  const _ArtistSelectionInline({
    required this.onboarding,
    required this.onDone,
  });

  final OnboardingController onboarding;
  final VoidCallback onDone;

  @override
  State<_ArtistSelectionInline> createState() =>
      _ArtistSelectionInlineState();
}

class _ArtistSelectionInlineState extends State<_ArtistSelectionInline> {
  final List<Map<String, dynamic>> _artists = [];
  final Set<String> _selectedIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    for (final a in widget.onboarding.favoriteArtists) {
      if (a['browseId'] != null) _selectedIds.add(a['browseId'].toString());
    }
    _fetchArtists();
  }

  Future<void> _fetchArtists() async {
    setState(() => _isLoading = true);
    try {
      final langs = widget.onboarding.musicLanguages;
      final seenIds = <String>{};
      final seenNames = <String>{};
      final allArtists = <Map<String, dynamic>>[];

      // Include currently selected artists so they appear in the grid
      for (final a in widget.onboarding.favoriteArtists) {
        final id = a['browseId']?.toString();
        final name = a['name']?.toString() ?? '';
        if (id != null && !seenIds.contains(id)) {
          seenIds.add(id);
          if (name.isNotEmpty) seenNames.add(name.toLowerCase());
          allArtists.add(Map<String, dynamic>.from(a));
        }
      }

      // Add curated artists matching the user's selected languages (up to 50)
      final curated = CuratedArtistsData.getCuratedArtists(
        languageCodes: langs,
        targetCount: 50,
      );
      for (final a in curated) {
        final id = a['browseId']?.toString();
        final name = a['name']?.toString().toLowerCase() ?? '';
        if (id != null && !seenIds.contains(id) && !seenNames.contains(name)) {
          seenIds.add(id);
          seenNames.add(name);
          allArtists.add(Map<String, dynamic>.from(a));
        }
      }

      if (mounted) {
        setState(() {
          _artists
            ..clear()
            ..addAll(allArtists);
          _isLoading = false;
        });
      }

      // Try fetching additional online artists in the background
      final musicServices = Get.find<MusicServices>();
      final queries = <String>[];
      if (langs.isEmpty) {
        queries.add('popular artists');
      } else {
        for (final code in langs.take(4)) {
          final langName = musicLanguageMap[code] ?? code;
          queries.add('$langName music artists');
        }
      }

      for (final query in queries) {
        try {
          final results = await musicServices.search(query, filter: 'artists');
          final artistList = results['Artists'] ?? results['artists'] ?? [];
          if (artistList is List) {
            for (final artist in artistList) {
              if (artist == null) continue;
              final browseId = artist is Map
                  ? artist['browseId']?.toString()
                  : null;
              String name = 'Unknown';
              String thumb = '';
              if (artist is Map) {
                name = artist['artist']?.toString() ??
                    artist['name']?.toString() ??
                    'Unknown';
                final thumbs = artist['thumbnails'];
                if (thumbs is List && thumbs.isNotEmpty) {
                  thumb = thumbs.last['url']?.toString() ?? '';
                }
              }
              if (name == 'Unknown' || browseId == null) continue;

              final existingIdx = _artists.indexWhere((a) =>
                  a['name']?.toString().toLowerCase() == name.toLowerCase());
              if (existingIdx >= 0) {
                if ((_artists[existingIdx]['thumbnailUrl'] == null ||
                        _artists[existingIdx]['thumbnailUrl'] == '') &&
                    thumb.isNotEmpty) {
                  _artists[existingIdx]['thumbnailUrl'] = thumb;
                }
              } else if (!seenIds.contains(browseId) &&
                  !seenNames.contains(name.toLowerCase())) {
                seenIds.add(browseId);
                seenNames.add(name.toLowerCase());
                if (_artists.length < 50) {
                  _artists.add({
                    'name': name,
                    'browseId': browseId,
                    'thumbnailUrl': thumb,
                  });
                }
              }
            }
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.secondary;
    final size = MediaQuery.of(context).size;

    return Column(
      children: [
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _artists.isEmpty
                  ? Center(
                      child: Text(
                        'No artists found.',
                        style: theme.textTheme.bodyLarge,
                      ),
                    )
                  : GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: size.width > 600 ? 4 : 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: _artists.length,
                      itemBuilder: (context, index) {
                        final artist = _artists[index];
                        final isSelected = _selectedIds
                            .contains(artist['browseId'].toString());
                        final thumb = artist['thumbnailUrl']?.toString() ?? '';

                        return InkWell(
                          onTap: () {
                            final id = artist['browseId'].toString();
                            setState(() {
                              if (_selectedIds.contains(id)) {
                                _selectedIds.remove(id);
                              } else {
                                _selectedIds.add(id);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? primaryColor.withValues(alpha: 0.14)
                                  : theme.primaryColorLight
                                      .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? primaryColor
                                    : theme.dividerColor
                                        .withValues(alpha: 0.12),
                                width: isSelected ? 1.8 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Stack(
                                  children: [
                                    AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      width: 62,
                                      height: 62,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected
                                              ? primaryColor
                                              : Colors.transparent,
                                          width: 2.5,
                                        ),
                                      ),
                                      child: ClipOval(
                                        child: thumb.isNotEmpty
                                            ? Image.network(
                                                thumb,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Container(
                                                  color: theme.primaryColorLight,
                                                  child: Icon(
                                                    Icons.person_rounded,
                                                    size: 32,
                                                    color: theme.iconTheme.color
                                                        ?.withValues(alpha: 0.4),
                                                  ),
                                                ),
                                              )
                                            : Container(
                                                color: theme.primaryColorLight,
                                                child: Icon(
                                                  Icons.person_rounded,
                                                  size: 32,
                                                  color: theme.iconTheme.color
                                                      ?.withValues(alpha: 0.4),
                                                ),
                                              ),
                                      ),
                                    ),
                                    if (isSelected)
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            color: primaryColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: theme
                                                  .scaffoldBackgroundColor,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.check,
                                            size: 13,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  artist['name']?.toString() ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? primaryColor
                                        : theme.textTheme.bodyMedium?.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                final selected = _artists
                    .where((a) =>
                        _selectedIds.contains(a['browseId'].toString()))
                    .toList();
                widget.onboarding.setFavoriteArtists(selected);
                widget.onboarding.currentStep.value =
                    OnboardingStep.complete;
                widget.onDone();
              },
              child: const Text(
                'Save',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
