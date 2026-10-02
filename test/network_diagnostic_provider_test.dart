import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lab_portfolio/providers/network_diagnostic_provider.dart';

void main() {
  test('detects Wi-Fi, cellular, and offline handover automatically', () async {
    final connectivity = StreamController<List<ConnectivityResult>>();
    final diagnostic = NetworkDiagnosticProvider(
      connectivityStream: connectivity.stream,
      currentConnectivity: () async => const [ConnectivityResult.wifi],
      handoverGracePeriod: const Duration(milliseconds: 30),
    );
    addTearDown(() async {
      await connectivity.close();
      diagnostic.dispose();
    });

    await Future<void>.delayed(Duration.zero);
    expect(diagnostic.networkType, DiagnosticNetworkType.wifi);

    connectivity.add(const [ConnectivityResult.mobile]);
    await Future<void>.delayed(Duration.zero);
    expect(diagnostic.networkType, DiagnosticNetworkType.mobileData);

    connectivity.add(const [ConnectivityResult.none]);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(diagnostic.networkType, DiagnosticNetworkType.offline);
    expect(diagnostic.result, isNull);

    await diagnostic.runDiagnostic();
    expect(diagnostic.result, isNull);
  });

  test('times out stalled requests instead of waiting forever', () async {
    final diagnostic = NetworkDiagnosticProvider(
      client: MockClient((_) => Completer<http.Response>().future),
      connectivityStream: const Stream<List<ConnectivityResult>>.empty(),
      currentConnectivity: () async => const [ConnectivityResult.mobile],
      requestTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(diagnostic.dispose);

    await Future<void>.delayed(Duration.zero);
    await diagnostic.runDiagnostic();

    expect(diagnostic.isTesting, isFalse);
    expect(diagnostic.result, isNull);
    expect(diagnostic.hasInternet, isFalse);
    expect(diagnostic.errorMessage, contains('Cellular'));
  });

  test('completes measurements over cellular with smaller probe payloads',
      () async {
    final requests = <http.Request>[];
    final diagnostic = NetworkDiagnosticProvider(
      client: MockClient((request) async {
        requests.add(request);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('ok', 200);
      }),
      connectivityStream: const Stream<List<ConnectivityResult>>.empty(),
      currentConnectivity: () async => const [ConnectivityResult.mobile],
      requestTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(diagnostic.dispose);

    await Future<void>.delayed(Duration.zero);
    await diagnostic.runDiagnostic();

    expect(diagnostic.result, isNotNull);
    expect(
      requests
          .firstWhere((request) => request.url.path.endsWith('__down'))
          .url
          .queryParameters['bytes'],
      '500000',
    );
    expect(
      requests
          .firstWhere((request) => request.url.path.endsWith('__up'))
          .bodyBytes
          .length,
      100000,
    );
  });

  test('completes full live measurements over Wi-Fi', () async {
    final requests = <http.Request>[];
    final diagnostic = NetworkDiagnosticProvider(
      client: MockClient((request) async {
        requests.add(request);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('ok', 200);
      }),
      connectivityStream: const Stream<List<ConnectivityResult>>.empty(),
      currentConnectivity: () async => const [ConnectivityResult.wifi],
      requestTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(diagnostic.dispose);

    await Future<void>.delayed(Duration.zero);
    expect(diagnostic.networkType, DiagnosticNetworkType.wifi);
    await diagnostic.runDiagnostic();

    expect(diagnostic.result, isNotNull);
    expect(
      requests
          .firstWhere((request) => request.url.path.endsWith('__down'))
          .url
          .queryParameters['bytes'],
      '2000000',
    );
    expect(
      requests
          .firstWhere((request) => request.url.path.endsWith('__up'))
          .bodyBytes
          .length,
      500000,
    );
  });
}
