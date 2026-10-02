import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lab_portfolio/main.dart';
import 'package:lab_portfolio/providers/network_monitor_provider.dart';
import 'package:lab_portfolio/screens/home_screen.dart';
import 'package:lab_portfolio/screens/local_mesh_chat_screen.dart';
import 'package:lab_portfolio/screens/network_monitor_screen.dart';
import 'package:lab_portfolio/providers/network_diagnostic_provider.dart';
import 'package:lab_portfolio/screens/network_diagnostic_dashboard_screen.dart';
import 'package:flutter_nearby_connections_plus/flutter_nearby_connections_plus.dart';

const _nearbyChannel = MethodChannel('flutter_nearby_connections');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nearbyChannel, (call) async => true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nearbyChannel, null);
  });

  testWidgets('Home dashboard shows the portfolio name and all activities',
      (tester) async {
    await tester.pumpWidget(const LabPortfolioApp());
    await tester.pumpAndSettle();

    expect(find.text('Mobile Computing 2 Portfolio'), findsOneWidget);
    expect(find.text('Christian Dancel & Louiela Fernandez'), findsOneWidget);
    for (var i = 1; i <= 5; i++) {
      expect(find.text('Activity $i'), findsOneWidget);
    }
    expect(find.text('Welcome back,'), findsNothing);
    expect(find.text('Activities completed: 0 of 5'), findsNothing);
  });

  testWidgets('Settings theme toggle updates the Home Dashboard',
      (tester) async {
    await tester.pumpWidget(const LabPortfolioApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Progress'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Currently using dark mode'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final homeContext = tester.element(find.byType(HomeScreen));
    expect(Theme.of(homeContext).brightness, Brightness.dark);
  });

  testWidgets('Network Monitor opens beside Settings in the Home app bar',
      (tester) async {
    await tester.pumpWidget(const LabPortfolioApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Network Monitor'), findsOneWidget);
    await tester.tap(find.byTooltip('Network Monitor'));
    await tester.pumpAndSettle();

    expect(find.byType(NetworkMonitorScreen), findsOneWidget);
    expect(find.text('Active network'), findsOneWidget);
    expect(find.text('Connection controls'), findsNothing);
    expect(find.byType(SegmentedButton<NetworkInterfaceType>), findsNothing);
  });

  testWidgets('Profile name updates Home and survives refresh', (tester) async {
    await tester.pumpWidget(const LabPortfolioApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('profile-name-field')),
      'Ada Lovelace',
    );
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);

    await tester.pumpWidget(const LabPortfolioApp());
    await tester.pumpAndSettle();

    expect(find.text('Ada Lovelace'), findsOneWidget);
  });

  testWidgets('Activity 1 opens its dashboard without Network Monitor',
      (tester) async {
    await tester.pumpWidget(const LabPortfolioApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activity 1'));
    await tester.pumpAndSettle();

    expect(find.text('Activity 1 Dashboard'), findsNWidgets(2));
    expect(find.text('Active network'), findsNothing);
    expect(find.byType(NetworkMonitorProvider), findsNothing);
    expect(find.text('Activity 3'), findsOneWidget);
  });

  testWidgets('Activity 2 opens Network Monitor directly', (tester) async {
    await tester.pumpWidget(const LabPortfolioApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activity 2'));
    await tester.pumpAndSettle();

    expect(find.byType(NetworkMonitorScreen), findsOneWidget);
    expect(find.text('Active network'), findsOneWidget);
  });

  testWidgets('Activity 4 opens Local Mesh Chat with discovery controls',
      (tester) async {
    await tester.pumpWidget(const LabPortfolioApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activity 4'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LocalMeshChatScreen), findsOneWidget);
    expect(find.text('Local Mesh Chat'), findsOneWidget);
    expect(find.text('Bluetooth'), findsOneWidget);
    expect(find.text('Wi‑Fi'), findsOneWidget);
    expect(find.byTooltip('Refresh nearby devices'), findsOneWidget);
  });

  testWidgets('Activity 4 refresh remains available while discovery starts',
      (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nearbyChannel, (call) async {
      calls.add(call);
      return true;
    });
    await tester.pumpWidget(const LabPortfolioApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Activity 4'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final refreshButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.refresh),
        matching: find.byType(IconButton),
      ),
    );
    expect(refreshButton.onPressed, isNotNull);
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final methods = calls.map((call) => call.method).toList();
    expect(methods, contains('stop_nearby_service'));
    expect(methods.where((method) => method == 'init_nearby_service').length,
        greaterThanOrEqualTo(2));
  });

  test('Nearby radio requests reach the native channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nearbyChannel, (call) async {
      calls.add(call);
      return true;
    });

    final nearby = NearbyService();
    await nearby.requestWifiEnabled();
    await nearby.requestBluetoothEnabled();
    expect(
      calls.map((call) => call.method),
      containsAll(['request_wifi_enabled', 'request_bluetooth_enabled']),
    );
  });

  testWidgets('Activity 3 shows read-only connection type and hides offline metrics',
      (tester) async {
    final connectivity = StreamController<List<ConnectivityResult>>();
    final diagnostic = NetworkDiagnosticProvider(
      connectivityStream: connectivity.stream,
      currentConnectivity: () async => const [ConnectivityResult.none],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await connectivity.close();
      diagnostic.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<NetworkDiagnosticProvider>.value(
        value: diagnostic,
        child: const MaterialApp(home: NetworkDiagnosticDashboardScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SegmentedButton<DiagnosticNetworkType>), findsNothing);
    expect(find.text('Active network'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsNWidgets(2));
    expect(find.text('Live measurements'), findsNothing);
    expect(find.text('Live measurements unavailable'), findsOneWidget);
  });

  testWidgets('Activity 3 warns when cellular has no internet', (tester) async {
    final diagnostic = NetworkDiagnosticProvider(
      client: MockClient((_) => Completer<http.Response>().future),
      connectivityStream: const Stream<List<ConnectivityResult>>.empty(),
      currentConnectivity: () async => const [ConnectivityResult.mobile],
      requestTimeout: const Duration(milliseconds: 20),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      diagnostic.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<NetworkDiagnosticProvider>.value(
        value: diagnostic,
        child: const MaterialApp(home: NetworkDiagnosticDashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.text('Active network'), findsOneWidget);
    expect(find.text('Cellular'), findsOneWidget);
    expect(find.byIcon(Icons.signal_cellular_alt), findsOneWidget);
    expect(find.text('No internet connection'), findsOneWidget);
    expect(find.text('Live measurements'), findsNothing);
    expect(find.textContaining('TimeoutException'), findsNothing);
  });

  testWidgets('Activity 3 shows live measurements on working cellular',
      (tester) async {
    final diagnostic = NetworkDiagnosticProvider(
      client: MockClient((_) async => http.Response('ok', 200)),
      connectivityStream: const Stream<List<ConnectivityResult>>.empty(),
      currentConnectivity: () async => const [ConnectivityResult.mobile],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      diagnostic.dispose();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<NetworkDiagnosticProvider>.value(
        value: diagnostic,
        child: const MaterialApp(home: NetworkDiagnosticDashboardScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.text('Active network'), findsOneWidget);
    expect(find.text('Cellular'), findsOneWidget);
    expect(find.text('Live measurements'), findsOneWidget);
    expect(find.text('No internet connection'), findsNothing);
    expect(diagnostic.result, isNotNull);
  });
}
