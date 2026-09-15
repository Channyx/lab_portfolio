import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lab_portfolio/providers/network_monitor_provider.dart';

void main() {
  test('stream updates interface and resumes queued request after handover',
      () async {
    final connectivity = StreamController<List<ConnectivityResult>>();
    final monitor = NetworkMonitorProvider(
      connectivityStream: connectivity.stream,
      currentConnectivity: () async => const [ConnectivityResult.wifi],
    );
    addTearDown(() async {
      await connectivity.close();
      monitor.dispose();
    });

    await Future<void>.delayed(Duration.zero);
    expect(monitor.activeInterface, NetworkInterfaceType.wifi);

    monitor.enqueueRequest();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    connectivity.add(const [ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(monitor.activeInterface, NetworkInterfaceType.offline);
    expect(monitor.queuedRequests.single.status, 'Waiting for connection');

    connectivity.add(const [ConnectivityResult.mobile]);
    await Future<void>.delayed(const Duration(milliseconds: 3200));

    expect(monitor.activeInterface, NetworkInterfaceType.cellular);
    expect(monitor.queuedRequests, isEmpty);
    expect(monitor.completedRequestCount, 1);
  });
}
