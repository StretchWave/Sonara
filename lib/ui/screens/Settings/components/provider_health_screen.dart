import 'package:flutter/material.dart';
import 'package:sonara/services/providers/provider_health.dart';
import 'package:sonara/services/providers/stream_route_config.dart';

/// Settings page that probes each configured Qobuz/Tidal resolver and
/// shows Online / Reachable / Offline status with latency.
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
      ProviderHealthChecker().checkAll(StreamRouteConfig.fromSettings());

  void _refresh() {
    setState(() {
      _resultsFuture = _runChecks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Resolver health')),
      body: FutureBuilder<List<ProviderHealthResult>>(
        future: _resultsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final results = snapshot.data ?? const [];
          if (results.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No Qobuz or Tidal resolvers configured.\n'
                  'Enable them in Settings → Sources.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];
                return ListTile(
                  contentPadding:
                      const EdgeInsets.only(left: 16, right: 16),
                  leading: Icon(
                    _iconFor(result.status),
                    color: _colorFor(result.status),
                  ),
                  title: Text(result.name),
                  subtitle: Text(result.message),
                  trailing: result.latencyMs != null
                      ? Text('${result.latencyMs} ms')
                      : null,
                );
              },
            ),
          );
        },
      ),
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
