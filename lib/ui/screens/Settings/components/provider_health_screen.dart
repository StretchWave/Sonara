import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sonara/services/providers/provider_health.dart';
import 'package:sonara/services/providers/stream_route_config.dart';
import '../settings_screen_controller.dart';

/// Settings page that scans every audio source (YouTube Music, SoundCloud,
/// Qobuz, Tidal, Deezer, Apple, Amazon, Instagram) to show which are
/// available and working, and lets the user reorder the priority in which
/// sources are tried (first, second, ...).
class ProviderHealthScreen extends StatefulWidget {
  const ProviderHealthScreen({super.key});

  @override
  State<ProviderHealthScreen> createState() => _ProviderHealthScreenState();
}

class _ProviderHealthScreenState extends State<ProviderHealthScreen> {
  late Future<List<ProviderHealthResult>> _resultsFuture;

  @override
  void initState() {
    super.initState();
    _resultsFuture = _runChecks();
  }

  Future<List<ProviderHealthResult>> _runChecks() =>
      ProviderHealthChecker().checkSources(StreamRouteConfig.fromSettings());

  void _refresh() {
    setState(() {
      _resultsFuture = _runChecks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sources & priority')),
      body: FutureBuilder<List<ProviderHealthResult>>(
        future: _resultsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final results = snapshot.data ?? const [];
          final bySource = {
            for (final r in results)
              if (r.sourceId.isNotEmpty) r.sourceId: r,
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionHeader(
                context,
                title: 'Availability',
                subtitle: 'Scans each source to check if it is reachable '
                    'and can stream audio.',
                trailing: IconButton(
                  tooltip: 'Scan again',
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                ),
              ),
              Expanded(
                child: results.isEmpty
                    ? const Center(child: Text('No sources to check.'))
                    : _AvailabilityList(results: results),
              ),
              const Divider(height: 1),
              _buildSectionHeader(
                context,
                title: 'Priority',
                subtitle: 'Drag to choose which source is tried first, '
                    'second, and so on. Disabled/not-configured sources are '
                    'skipped automatically.',
              ),
              Expanded(child: _PriorityList(bySource: bySource)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(subtitle,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

class _AvailabilityList extends StatelessWidget {
  const _AvailabilityList({required this.results});

  final List<ProviderHealthResult> results;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        final notConfigured = !result.configured;
        return ListTile(
          dense: true,
          leading: Icon(
            notConfigured
                ? Icons.remove_circle_outline
                : _iconFor(result.status),
            color: notConfigured
                ? Colors.grey
                : _colorFor(result.status),
          ),
          title: Text(result.name),
          subtitle: Text(
            result.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: result.latencyMs != null
              ? Text('${result.latencyMs} ms')
              : null,
        );
      },
    );
  }

  IconData _iconFor(ProviderHealthStatus status) => switch (status) {
        ProviderHealthStatus.online => Icons.check_circle,
        ProviderHealthStatus.reachable => Icons.help,
        ProviderHealthStatus.offline => Icons.cancel,
      };

  Color _colorFor(ProviderHealthStatus status) => switch (status) {
        ProviderHealthStatus.online => Colors.green,
        ProviderHealthStatus.reachable => Colors.orange,
        ProviderHealthStatus.offline => Colors.red,
      };
}

class _PriorityList extends StatelessWidget {
  const _PriorityList({required this.bySource});

  final Map<String, ProviderHealthResult> bySource;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SettingsScreenController>();
    return Obx(() {
      final order = controller.providerOrder.toList();
      if (order.isEmpty) {
        return const Center(child: Text('No sources to order.'));
      }
      return ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        buildDefaultDragHandles: false,
        itemCount: order.length,
        onReorderItem: (oldIndex, newIndex) {
          final updated = List<String>.of(order);
          final moved = updated.removeAt(oldIndex);
          updated.insert(newIndex, moved);
          controller.setProviderOrder(updated);
        },
        itemBuilder: (context, index) {
          final sourceId = order[index];
          final probe = bySource[sourceId];
          final name =
              ProviderHealthChecker.sourceNames[sourceId] ?? sourceId;
          return ListTile(
            key: ValueKey('priority-$sourceId'),
            dense: true,
            leading: ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Icon(Icons.drag_handle),
              ),
            ),
            title: Row(
              children: [
                CircleAvatar(
                  radius: 11,
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(name)),
              ],
            ),
            trailing: _StatusChip(probe: probe),
          );
        },
      );
    });
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.probe});

  final ProviderHealthResult? probe;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (probe == null) {
      return Chip(
        label: const Text('unknown'),
        visualDensity: VisualDensity.compact,
        labelStyle: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        backgroundColor: colorScheme.surfaceContainerHighest,
      );
    }
    if (!probe!.configured) {
      return Chip(
        label: const Text('not configured'),
        visualDensity: VisualDensity.compact,
        labelStyle: const TextStyle(fontSize: 11, color: Colors.grey),
        backgroundColor: colorScheme.surfaceContainerHighest,
      );
    }
    final (label, color) = switch (probe!.status) {
      ProviderHealthStatus.online => ('working', Colors.green),
      ProviderHealthStatus.reachable => ('reachable', Colors.orange),
      ProviderHealthStatus.offline => ('offline', Colors.red),
    };
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      labelStyle: const TextStyle(fontSize: 11, color: Colors.white),
      backgroundColor: color,
    );
  }
}
