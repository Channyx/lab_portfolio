import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/network_monitor_provider.dart';

class NetworkMonitorScreen extends StatelessWidget {
  static const routeName = '/network-monitor';

  const NetworkMonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NetworkMonitorProvider(),
      child: const _NetworkMonitorView(),
    );
  }
}

class _NetworkMonitorView extends StatelessWidget {
  const _NetworkMonitorView();

  @override
  Widget build(BuildContext context) {
    final activeInterface =
        context.select<NetworkMonitorProvider, NetworkInterfaceType>(
            (monitor) => monitor.activeInterface);
    final theme = Theme.of(context);
    final isOnline = activeInterface != NetworkInterfaceType.offline;

    return Scaffold(
      appBar: AppBar(title: const Text('Network Monitor')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _ConnectionStatusCard(
              interfaceType: activeInterface,
              isOnline: isOnline,
            ),
            const SizedBox(height: 20),
            Text(
              'Connection controls',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SegmentedButton<NetworkInterfaceType>(
              segments: const [
                ButtonSegment(
                  value: NetworkInterfaceType.wifi,
                  icon: Icon(Icons.wifi),
                  label: Text('Wi-Fi'),
                ),
                ButtonSegment(
                  value: NetworkInterfaceType.cellular,
                  icon: Icon(Icons.signal_cellular_alt),
                  label: Text('Cellular'),
                ),
                ButtonSegment(
                  value: NetworkInterfaceType.offline,
                  icon: Icon(Icons.cloud_off),
                  label: Text('Offline'),
                ),
              ],
              selected: {activeInterface},
              onSelectionChanged: (selection) => context
                  .read<NetworkMonitorProvider>()
                  .simulateNetwork(selection.first),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: context.read<NetworkMonitorProvider>().enqueueRequest,
              icon: const Icon(Icons.download),
              label: const Text('Start large data request'),
            ),
            const SizedBox(height: 12),
            const _RequestQueuePanel(),
          ],
        ),
      ),
    );
  }
}

class _RequestQueuePanel extends StatelessWidget {
  const _RequestQueuePanel();

  @override
  Widget build(BuildContext context) {
    final monitor = context.watch<NetworkMonitorProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${monitor.completedRequestCount} request(s) completed',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        if (monitor.queuedRequests.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.inbox_outlined),
              title: Text('No pending requests'),
              subtitle: Text('Start a request to see handover recovery.'),
            ),
          )
        else
          ...monitor.queuedRequests.map(
            (request) => Card(
              child: ListTile(
                leading: Icon(
                  request.status == 'Waiting for connection'
                      ? Icons.pause_circle_outline
                      : Icons.sync,
                ),
                title: Text('Request #${request.id}'),
                subtitle: Text(request.status),
                trailing: SizedBox(
                  width: 90,
                  child: LinearProgressIndicator(value: request.progress),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard({
    required this.interfaceType,
    required this.isOnline,
  });

  final NetworkInterfaceType interfaceType;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (interfaceType) {
      NetworkInterfaceType.wifi => ('Wi-Fi', Icons.wifi),
      NetworkInterfaceType.cellular => ('Cellular', Icons.signal_cellular_alt),
      NetworkInterfaceType.offline => ('Offline', Icons.cloud_off),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 42, color: isOnline ? Colors.green : Colors.red),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Active network'),
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    isOnline
                        ? 'Requests resume automatically after handover.'
                        : 'Pending requests are queued until connectivity returns.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
