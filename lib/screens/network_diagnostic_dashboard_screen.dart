import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../providers/network_diagnostic_provider.dart';

class NetworkDiagnosticDashboardScreen extends StatefulWidget {
  static const routeName = '/activity-3';

  const NetworkDiagnosticDashboardScreen({super.key});

  @override
  State<NetworkDiagnosticDashboardScreen> createState() =>
      _NetworkDiagnosticDashboardScreenState();
}

class _NetworkDiagnosticDashboardScreenState
    extends State<NetworkDiagnosticDashboardScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<NetworkDiagnosticProvider>().start();
  }

  @override
  Widget build(BuildContext context) {
    final diagnostic = context.watch<NetworkDiagnosticProvider>();
    final result = diagnostic.result;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Network Diagnostic Dashboard')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _HealthCard(diagnostic: diagnostic),
            const SizedBox(height: 20),
            Text(
              'Connection type',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SegmentedButton<DiagnosticNetworkType>(
              segments: const [
                ButtonSegment(
                  value: DiagnosticNetworkType.wifi,
                  icon: Icon(Icons.wifi),
                  label: Text('Wi-Fi'),
                ),
                ButtonSegment(
                  value: DiagnosticNetworkType.mobileData,
                  icon: Icon(Icons.signal_cellular_alt),
                  label: Text('Data'),
                ),
                ButtonSegment(
                  value: DiagnosticNetworkType.offline,
                  icon: Icon(Icons.cloud_off),
                  label: Text('Offline'),
                ),
              ],
              selected: {diagnostic.networkType},
              onSelectionChanged: (selection) => diagnostic.setNetworkType(
                selection.first,
              ),
            ),
            const SizedBox(height: 20),
            if (diagnostic.isTesting) const LinearProgressIndicator(),
            if (diagnostic.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  diagnostic.errorMessage!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              'Live measurements',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _MetricGrid(result: result),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: diagnostic.isTesting ? null : diagnostic.runDiagnostic,
              icon: const Icon(Icons.refresh),
              label: const Text('Run diagnostic now'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context
                  .read<AppStateProvider>()
                  .toggleActivityCompletion(3),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Mark Activity 3 complete'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.diagnostic});

  final NetworkDiagnosticProvider diagnostic;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (diagnostic.health) {
      DiagnosticHealth.excellent => ('Excellent', Colors.green, Icons.verified),
      DiagnosticHealth.fair => ('Fair', Colors.orange, Icons.thumbs_up_down),
      DiagnosticHealth.poor => ('Poor', Colors.red, Icons.warning_amber),
      DiagnosticHealth.degraded => ('Degraded', Colors.deepOrange, Icons.error),
      DiagnosticHealth.unknown => (
          'Waiting for results',
          Colors.grey,
          Icons.sync,
        ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: color, size: 42),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Connection health'),
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold, color: color),
                  ),
                  const Text('Updates automatically every minute.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.result});

  final NetworkDiagnosticResult? result;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('Idle ping', result == null ? '--' : '${result!.idlePingMs.toStringAsFixed(0)} ms'),
      ('Download', result == null ? '--' : '${result!.downloadMbps.toStringAsFixed(1)} Mbps'),
      ('Download ping', result == null ? '--' : '${result!.downloadPingMs.toStringAsFixed(0)} ms'),
      ('Upload', result == null ? '--' : '${result!.uploadMbps.toStringAsFixed(1)} Mbps'),
      ('Upload ping', result == null ? '--' : '${result!.uploadPingMs.toStringAsFixed(0)} ms'),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: metrics
          .map(
            (metric) => SizedBox(
              width: 160,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(metric.$1),
                      const SizedBox(height: 6),
                      Text(
                        metric.$2,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}