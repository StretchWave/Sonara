import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/onboarding_controller.dart';

/// Music language definition with code, English name, and native script.
class MusicLanguageInfo {
  final String code;
  final String englishName;
  final String nativeName;

  const MusicLanguageInfo({
    required this.code,
    required this.englishName,
    required this.nativeName,
  });
}

/// Comprehensive list of music languages supported by Sonara.
const List<MusicLanguageInfo> allMusicLanguages = [
  MusicLanguageInfo(code: 'en', englishName: 'English', nativeName: 'English'),
  MusicLanguageInfo(code: 'hi', englishName: 'Hindi', nativeName: 'हिन्दी'),
  MusicLanguageInfo(code: 'pa', englishName: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ'),
  MusicLanguageInfo(code: 'ta', englishName: 'Tamil', nativeName: 'தமிழ்'),
  MusicLanguageInfo(code: 'te', englishName: 'Telugu', nativeName: 'తెలుగు'),
  MusicLanguageInfo(code: 'ml', englishName: 'Malayalam', nativeName: 'മലയാളം'),
  MusicLanguageInfo(code: 'es', englishName: 'Spanish', nativeName: 'Español'),
  MusicLanguageInfo(code: 'ko', englishName: 'Korean', nativeName: '한국어'),
  MusicLanguageInfo(code: 'ja', englishName: 'Japanese', nativeName: '日本語'),
  MusicLanguageInfo(code: 'bn', englishName: 'Bengali', nativeName: 'বাংলা'),
  MusicLanguageInfo(code: 'mr', englishName: 'Marathi', nativeName: 'मराठी'),
  MusicLanguageInfo(code: 'gu', englishName: 'Gujarati', nativeName: 'ગુજરાતી'),
  MusicLanguageInfo(code: 'fr', englishName: 'French', nativeName: 'Français'),
  MusicLanguageInfo(code: 'de', englishName: 'German', nativeName: 'Deutsch'),
  MusicLanguageInfo(code: 'pt', englishName: 'Portuguese', nativeName: 'Português'),
  MusicLanguageInfo(code: 'ar', englishName: 'Arabic', nativeName: 'العربية'),
  MusicLanguageInfo(code: 'ur', englishName: 'Urdu', nativeName: 'اردو'),
  MusicLanguageInfo(code: 'tr', englishName: 'Turkish', nativeName: 'Türkçe'),
  MusicLanguageInfo(code: 'it', englishName: 'Italian', nativeName: 'Italiano'),
  MusicLanguageInfo(code: 'ru', englishName: 'Russian', nativeName: 'Русский'),
  MusicLanguageInfo(code: 'kn', englishName: 'Kannada', nativeName: 'ಕನ್ನಡ'),
  MusicLanguageInfo(code: 'or', englishName: 'Odia', nativeName: 'ଓଡ଼ିଆ'),
  MusicLanguageInfo(code: 'id', englishName: 'Indonesian', nativeName: 'Bahasa Indonesia'),
  MusicLanguageInfo(code: 'fil', englishName: 'Filipino', nativeName: 'Filipino'),
  MusicLanguageInfo(code: 'th', englishName: 'Thai', nativeName: 'ไทย'),
  MusicLanguageInfo(code: 'vi', englishName: 'Vietnamese', nativeName: 'Tiếng Việt'),
  MusicLanguageInfo(code: 'zh', englishName: 'Chinese', nativeName: '中文'),
  MusicLanguageInfo(code: 'nl', englishName: 'Dutch', nativeName: 'Nederlands'),
  MusicLanguageInfo(code: 'sv', englishName: 'Swedish', nativeName: 'Svenska'),
  MusicLanguageInfo(code: 'pl', englishName: 'Polish', nativeName: 'Polski'),
  MusicLanguageInfo(code: 'fa', englishName: 'Persian', nativeName: 'فارسی'),
];

/// Legacy map compatibility for external references
final Map<String, String> musicLanguageMap = {
  for (final l in allMusicLanguages) l.code: l.englishName,
};

/// Second onboarding step: music language multi-select.
class LanguageSelectionStep extends StatefulWidget {
  const LanguageSelectionStep({super.key});

  @override
  State<LanguageSelectionStep> createState() => _LanguageSelectionStepState();
}

class _LanguageSelectionStepState extends State<LanguageSelectionStep> {
  final OnboardingController _onboarding = Get.find<OnboardingController>();
  final Set<String> _selected = {};
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-select existing choices or default to English
    if (_onboarding.musicLanguages.isNotEmpty) {
      _selected.addAll(_onboarding.musicLanguages);
    } else {
      _selected.add('en');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleLanguage(String code) {
    setState(() {
      if (_selected.contains(code)) {
        _selected.remove(code);
      } else {
        _selected.add(code);
      }
    });
  }

  void _continue() {
    if (_selected.isEmpty) return;
    _onboarding.setMusicLanguages(_selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.secondary;
    final textColor = theme.textTheme.bodyMedium?.color;
    final size = MediaQuery.of(context).size;
    final horizontalPad = size.width > 600 ? size.width * 0.12 : 20.0;

    final filteredLanguages = allMusicLanguages.where((l) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      return l.englishName.toLowerCase().contains(query) ||
          l.nativeName.toLowerCase().contains(query) ||
          l.code.toLowerCase().contains(query);
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
                "What languages do you listen to?",
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Select all languages you enjoy. We'll personalize your recommendations and home shelves.",
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
                    Icon(
                      Icons.search_rounded,
                      color: textColor?.withValues(alpha: 0.5),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: textColor, fontSize: 14),
                        onChanged: (val) {
                          setState(() => _searchQuery = val.trim());
                        },
                        decoration: InputDecoration(
                          hintText: "Search languages...",
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
                    "${_selected.length} ${_selected.length == 1 ? 'language' : 'languages'} selected",
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                  if (_selected.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _selected.clear()),
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

        // Languages Grid
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPad),
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 90),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: size.width > 600 ? 4 : 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.3,
              ),
              itemCount: filteredLanguages.length,
              itemBuilder: (context, index) {
                final lang = filteredLanguages[index];
                final isSelected = _selected.contains(lang.code);

                return _LanguageCard(
                  info: lang,
                  isSelected: isSelected,
                  primaryColor: primaryColor,
                  textColor: textColor,
                  onTap: () => _toggleLanguage(lang.code),
                );
              },
            ),
          ),
        ),

        // Bottom Action Container with gradient
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
    final isEnabled = _selected.isNotEmpty;

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
              backgroundColor: isEnabled ? primaryColor : theme.primaryColorLight,
              foregroundColor: isEnabled ? Colors.black : textColor?.withValues(alpha: 0.4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: isEnabled ? _continue : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isEnabled ? "Continue to Artists" : "Select at least 1 language",
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (isEnabled) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.info,
    required this.isSelected,
    required this.primaryColor,
    required this.textColor,
    required this.onTap,
  });

  final MusicLanguageInfo info;
  final bool isSelected;
  final Color primaryColor;
  final Color? textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.14)
              : theme.primaryColorLight.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? primaryColor
                : theme.dividerColor.withValues(alpha: 0.12),
            width: isSelected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.englishName,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 14,
                      color: isSelected ? primaryColor : textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (info.nativeName != info.englishName)
                    Text(
                      info.nativeName,
                      style: TextStyle(
                        fontSize: 11,
                        color: textColor?.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? primaryColor : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? primaryColor
                      : theme.dividerColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.black,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
