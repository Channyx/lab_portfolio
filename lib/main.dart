import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/app_state_provider.dart';
import 'screens/activity_1_dashboard_screen.dart';
import 'screens/home_screen.dart';
import 'screens/activity_placeholder_screen.dart';
import 'screens/network_monitor_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(const LabPortfolioApp());
}

class LabPortfolioApp extends StatelessWidget {
  const LabPortfolioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppStateProvider(),
      child: Consumer<AppStateProvider>(
        builder: (context, appState, _) {
          return MaterialApp(
            title: 'Mobile Computing Portfolio',
            debugShowCheckedModeBanner: false,
            themeMode: appState.themeMode,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
            ),
            darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: Brightness.dark,
              ),
            ),
            initialRoute: HomeScreen.routeName,
            routes: {
              HomeScreen.routeName: (_) => const HomeScreen(),
              Activity1DashboardScreen.routeName: (_) =>
                  const Activity1DashboardScreen(),
              '/activity-2': (_) => const NetworkMonitorScreen(),
              NetworkMonitorScreen.routeName: (_) =>
                  const NetworkMonitorScreen(),
              SettingsScreen.routeName: (_) => const SettingsScreen(),
              for (final activity in kActivities.where(
                (activity) => activity.number >= 3,
              ))
                activity.routeName: (_) => ActivityPlaceholderScreen(
                      activityNumber: activity.number,
                      title: activity.title,
                      icon: activity.icon,
                      color: activity.color,
                    ),
            },
          );
        },
      ),
    );
  }
}
