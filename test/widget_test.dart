import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lab_portfolio/main.dart';
import 'package:lab_portfolio/providers/network_monitor_provider.dart';
import 'package:lab_portfolio/screens/home_screen.dart';
import 'package:lab_portfolio/screens/network_monitor_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
}
