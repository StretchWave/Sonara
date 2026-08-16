import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sonara/services/playback_stats_service.dart';
import 'package:share_plus/share_plus.dart';

import '../../widgets/snackbar.dart';

/// Listening statistics screen with a Wrapped-style yearly recap.
///
/// Shows all-time and per-year totals (listening time, plays, unique songs),
/// top songs/artists/albums, monthly activity and a shareable text recap.
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final statsService = Get.find<PlaybackStatsService>();
    return Scaffold(
      backgroundColor: Theme.of(context).canvasColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text("listeningStatistics".tr),
        actions: [
          IconButton(
            tooltip: "shareRecap".tr,
            icon: const Icon(Icons.ios_share),
            onPressed: () => _shareRecap(context, statsService),
          ),
          IconButton(
            tooltip: "clearStatistics".tr,
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmClear(context, statsService),
          ),
        ],
      ),
      body: FutureBuilder<List<int>>(
        future: statsService.getAvailableYears(),
        builder: (context, yearsSnapshot) {
          final years = yearsSnapshot.data ?? const <int>[];
          return DefaultTabController(
            length: years.length + 1,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  tabs: [
                    Tab(text: "allTime".tr),
                    for (final year in years) Tab(text: "$year"),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _StatsYearView(statsService: statsService, year: null),
                      for (final year in years)
                        _StatsYearView(statsService: statsService, year: year),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _shareRecap(
      BuildContext context, PlaybackStatsService statsService) async {
    final allTime = await _buildRecapText(statsService, null);
    final currentYear = DateTime.now().year;
    final yearText = await _buildRecapText(statsService, currentYear);
    final text = yearText == null
        ? allTime
        : "$yearText\n\n— — —\n\n$allTime";
    if (!context.mounted) return;
    if (text == null) {
      ScaffoldMessenger.of(context).showSnackBar(snackbar(
          context, "noStatisticsData".tr,
          size: SanckBarSize.MEDIUM));
      return;
    }
    await Share.share(text);
  }

  Future<String?> _buildRecapText(
      PlaybackStatsService statsService, int? year) async {
    final history = await statsService.getHistory(year: year);
    if (history.isEmpty) return null;

    final label = year == null ? "allTime".tr : "$year";
    final listenMs = history.fold<int>(
        0, (sum, e) => sum + ((e['listenMs'] as int?) ?? 0));
    final topSongs = _aggregate(history, 'songId', 'title');
    final topArtists = _aggregateArtists(history);
    final buffer = StringBuffer()
      ..writeln("🎧 ${"myMusicRecap".tr} — $label")
      ..writeln("${history.length} ${'songsPlayedCount'.tr} · ${formatListeningTime(listenMs)} ${'listened'.tr}")
      ..writeln();
    if (topSongs.isNotEmpty) {
      buffer.writeln("🏆 ${'topSongs'.tr}:");
      for (final song in topSongs.take(5)) {
        buffer.writeln("   ${song['title']} — ${song['plays']}×");
      }
      buffer.writeln();
    }
    if (topArtists.isNotEmpty) {
      buffer.writeln("🎤 ${'topArtists'.tr}:");
      for (final artist in topArtists.take(5)) {
        buffer.writeln("   ${artist['name']} — ${artist['plays']}×");
      }
    }
    return buffer.toString();
  }

  void _confirmClear(BuildContext context, PlaybackStatsService statsService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text("clearStatistics".tr),
        content: Text("clearStatisticsDes".tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("cancel".tr),
          ),
          TextButton(
            onPressed: () async {
              await statsService.clearStats();
              if (!context.mounted) return;
              Navigator.of(context).pop();
              Get.to(() => const StatisticsScreen(),
                  transition: Transition.noTransition);
            },
            child: Text("clear".tr),
          ),
        ],
      ),
    );
  }
}

class _StatsYearView extends StatefulWidget {
  const _StatsYearView({required this.statsService, required this.year});

  final PlaybackStatsService statsService;
  final int? year;

  @override
  State<_StatsYearView> createState() => _StatsYearViewState();
}

class _StatsYearViewState extends State<_StatsYearView> {
  late Future<List<Map<String, dynamic>>> _historyFuture;
  late Future<Map<String, int>> _dailyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = widget.statsService.getHistory(year: widget.year);
    _dailyFuture = widget.statsService.getDailyActivity(year: widget.year);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final history = snapshot.data ?? const <Map<String, dynamic>>[];
        if (history.isEmpty) {
          return Center(
            child: Text(
              "noStatisticsData".tr,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        }

        return FutureBuilder<Map<String, int>>(
          future: _dailyFuture,
          builder: (context, dailySnapshot) {
            final daily = dailySnapshot.data ?? const <String, int>{};
            final streaks = _computeStreaks(daily);
            final currentStreak = streaks.current;
            final longestStreak = streaks.longest;
            final listenMs = history.fold<int>(
                0, (sum, e) => sum + ((e['listenMs'] as int?) ?? 0));
            final uniqueSongs = history.map((e) => e['songId']).toSet().length;
            final topSongs = _aggregate(history, 'songId', 'title');
            final topArtists = _aggregateArtists(history);
            final topAlbums = _aggregate(history, 'album', 'album');

            return ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                // ---- Summary cards ----
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.timer_outlined,
                        label: "listeningTime".tr,
                        value: formatListeningTime(listenMs),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.play_circle_outline,
                        label: "songsPlayed".tr,
                        value: "${history.length}",
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.music_note_outlined,
                        label: "uniqueSongs".tr,
                        value: "$uniqueSongs",
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ---- Streak cards ----
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.local_fire_department,
                        label: "currentStreak".tr,
                        value: "$currentStreak ${'days'.tr}",
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.emoji_events_outlined,
                        label: "longestStreak".tr,
                        value: "$longestStreak ${'days'.tr}",
                      ),
                    ),
                  ],
                ),

                // ---- Activity calendar (per-year views) ----
                if (widget.year != null) ...[
                  const SizedBox(height: 20),
                  _SectionHeader(title: "activityCalendar".tr),
                  const SizedBox(height: 8),
                  _ActivityCalendar(year: widget.year!, daily: daily),
                ],
                const SizedBox(height: 20),

                // ---- Monthly activity ----
                _SectionHeader(title: "monthlyActivity".tr),
                const SizedBox(height: 8),
                _MonthlyActivityChart(history: history, year: widget.year),
                const SizedBox(height: 20),

                // ---- Top songs ----
                _SectionHeader(title: "topSongs".tr),
                const SizedBox(height: 4),
                for (var i = 0; i < topSongs.take(10).length; i++)
                  _RankTile(
                    rank: i + 1,
                    title: (topSongs[i]['title'] as String?) ?? "NA",
                    subtitle: "${topSongs[i]['plays']}× · ${formatListeningTime((topSongs[i]['listenMs'] as int?) ?? 0)}",
                  ),
                const SizedBox(height: 20),

                // ---- Top artists ----
                _SectionHeader(title: "topArtists".tr),
                const SizedBox(height: 4),
                for (var i = 0; i < topArtists.take(10).length; i++)
                  _RankTile(
                    rank: i + 1,
                    title: (topArtists[i]['name'] as String?) ?? "NA",
                    subtitle: "${topArtists[i]['plays']}× · ${formatListeningTime((topArtists[i]['listenMs'] as int?) ?? 0)}",
                  ),
                const SizedBox(height: 20),

                // ---- Top albums ----
                if (topAlbums.isNotEmpty &&
                    (topAlbums.first['name'] as String?)?.isNotEmpty == true) ...[
                    _SectionHeader(title: "topAlbums".tr),
                    const SizedBox(height: 4),
                    for (var i = 0; i < topAlbums.take(10).length; i++)
                      _RankTile(
                        rank: i + 1,
                        title: (topAlbums[i]['name'] as String?) ?? "NA",
                        subtitle: "${topAlbums[i]['plays']}× · ${formatListeningTime((topAlbums[i]['listenMs'] as int?) ?? 0)}",
                      ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

/// Aggregates history entries by [key], summing plays and listen time.
List<Map<String, dynamic>> _aggregate(
    List<Map<String, dynamic>> history, String key, String nameKey) {
  final map = <String, Map<String, dynamic>>{};
  for (final entry in history) {
    final name = (entry[nameKey] as String?) ?? "NA";
    final aggregateKey = "${entry[key] ?? name}_$name";
    final agg = map.putIfAbsent(
      aggregateKey,
      () => {'name': name, 'plays': 0, 'listenMs': 0},
    );
    agg['plays'] = (agg['plays'] as int) + 1;
    agg['listenMs'] =
        (agg['listenMs'] as int) + ((entry['listenMs'] as int?) ?? 0);
  }
  final list = map.values.toList()
    ..sort((a, b) => (b['plays'] as int).compareTo(a['plays'] as int));
  return list;
}

/// Aggregates history entries by artist (artists are comma separated).
List<Map<String, dynamic>> _aggregateArtists(
    List<Map<String, dynamic>> history) {
  final map = <String, Map<String, dynamic>>{};
  for (final entry in history) {
    final artists = ((entry['artist'] as String?) ?? "NA")
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (artists.isEmpty) artists.add("NA");
    for (final artist in artists) {
      final agg = map.putIfAbsent(
        artist,
        () => {'name': artist, 'plays': 0, 'listenMs': 0},
      );
      agg['plays'] = (agg['plays'] as int) + 1;
      agg['listenMs'] =
          (agg['listenMs'] as int) + ((entry['listenMs'] as int?) ?? 0);
    }
  }
  final list = map.values.toList()
    ..sort((a, b) => (b['plays'] as int).compareTo(a['plays'] as int));
  return list;
}

String formatListeningTime(int ms) {
  final totalSeconds = ms ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (hours > 0) return "${hours}h ${minutes}m";
  if (minutes > 0) return "${minutes}m ${(totalSeconds % 60)}s";
  return "${totalSeconds}s";
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.secondary.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: colorScheme.onSecondary),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _RankTile extends StatelessWidget {
  const _RankTile({
    required this.rank,
    required this.title,
    required this.subtitle,
  });

  final int rank;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              "$rank",
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSecondary),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                Text(subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple monthly activity bar chart painted with plain containers.
class _MonthlyActivityChart extends StatelessWidget {
  const _MonthlyActivityChart({required this.history, required this.year});

  final List<Map<String, dynamic>> history;
  final int? year;

  @override
  Widget build(BuildContext context) {
    final monthly = List<int>.filled(12, 0);
    for (final entry in history) {
      final playedAt = DateTime.fromMillisecondsSinceEpoch(
          (entry['playedAt'] as int?) ?? 0);
      if (year == null || playedAt.year == year) {
        monthly[playedAt.month - 1] += 1;
      }
    }
    final maxCount = monthly.reduce((a, b) => a > b ? a : b);
    final monthLabels = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 12; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondary
                              .withValues(
                                  alpha: maxCount == 0
                                      ? 0.15
                                      : 0.25 + 0.75 * (monthly[i] / maxCount)),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      monthLabels[i],
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Computes the current and longest streak of consecutive days with plays.
///
/// The current streak counts consecutive days ending at the anchor day: today
/// if the user played today or yesterday, otherwise the last day with a play.
({int current, int longest}) _computeStreaks(Map<String, int> daily) {
  if (daily.isEmpty) return (current: 0, longest: 0);
  final days = daily.keys.map(DateTime.parse).toList()..sort();
  final daySet =
      days.map((d) => DateTime(d.year, d.month, d.day)).toSet();

  var longest = 1;
  var run = 1;
  for (var i = 1; i < days.length; i++) {
    if (days[i].difference(days[i - 1]).inDays == 1) {
      run += 1;
      if (run > longest) longest = run;
    } else {
      run = 1;
    }
  }

  final last = days.last;
  final today = DateTime.now();
  final lastDay = DateTime(last.year, last.month, last.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  final anchor =
      lastDay.difference(todayDay).inDays.abs() <= 1 ? todayDay : lastDay;

  var current = 0;
  var cursor = anchor;
  while (daySet.contains(cursor)) {
    current += 1;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return (current: current, longest: longest);
}

/// GitHub-style activity calendar: one column per week, one row per weekday,
/// cell intensity reflects the number of plays that day.
class _ActivityCalendar extends StatelessWidget {
  const _ActivityCalendar({required this.year, required this.daily});

  final int year;
  final Map<String, int> daily;

  static const List<String> _monthLabels = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final firstDay = DateTime(year, 1, 1);
    final lastDay = DateTime(year, 12, 31);
    final totalDays = lastDay.difference(firstDay).inDays + 1;
    final leading = firstDay.weekday - 1; // weeks start on Monday
    final weeks = ((leading + totalDays) / 7).ceil();

    final cellSize = 11.0;
    final gap = 2.0;
    final columnWidth = cellSize + gap;

    Color cellColor(int plays) {
      if (plays <= 0) {
        return colorScheme.secondary.withValues(alpha: 0.10);
      }
      final intensity = (plays / 6).clamp(0.0, 1.0);
      return colorScheme.secondary
          .withValues(alpha: 0.25 + 0.7 * intensity);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month labels + legend
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 14,
                  child: Stack(
                    children: [
                      for (var m = 0; m < 12; m++)
                        Positioned(
                          left: m / 12 * (weeks * columnWidth),
                          top: 0,
                          child: Text(
                            _monthLabels[m],
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontSize: 9),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  Text('less'.tr,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontSize: 9)),
                  const SizedBox(width: 4),
                  for (final level in [0, 1, 3, 6])
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Container(
                        width: cellSize - 2,
                        height: cellSize - 2,
                        decoration: BoxDecoration(
                          color: cellColor(level),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  Text('more'.tr,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontSize: 9)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Weekday gutter (Mon..Sun)
                    SizedBox(
                      width: 14,
                      child: Column(
                        children: [
                          for (var r = 0; r < 7; r++)
                            SizedBox(
                              height: cellSize + gap,
                              child: Text(
                                ['M', 'T', 'W', 'T', 'F', 'S', 'S'][r],
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(fontSize: 8),
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (var w = 0; w < weeks; w++)
                      Column(
                        children: [
                          for (var r = 0; r < 7; r++)
                            Builder(builder: (context) {
                              final dayIndex = w * 7 + r - leading;
                              final date =
                                  firstDay.add(Duration(days: dayIndex));
                              final inYear = date.year == year;
                              final key =
                                  '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                              final plays = inYear ? (daily[key] ?? 0) : 0;
                              return Tooltip(
                                message: inYear
                                    ? '$key · ${plays == 0 ? "noPlays".tr : "$plays"}'
                                    : '',
                                child: Container(
                                  width: cellSize,
                                  height: cellSize,
                                  margin: EdgeInsets.only(
                                      right: gap, bottom: gap),
                                  decoration: BoxDecoration(
                                    color: cellColor(plays),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              );
                            }),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper used by the settings entry point: opens the statistics screen.
void openStatisticsScreen(BuildContext context) {
  Get.to(() => const StatisticsScreen());
}
