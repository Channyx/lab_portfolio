import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../widgets/dashboard_card.dart';
// ignore: unused_import
import 'activity_placeholder_screen.dart';
import 'network_monitor_screen.dart';
import 'settings_screen.dart';

class ActivityInfo {
  final int number;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String routeName;

  const ActivityInfo({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.routeName,
  });
}

const List<ActivityInfo> kActivities = [
  ActivityInfo(
    number: 1,
    title: 'Activity 1',
    subtitle: 'Open the portfolio dashboard',
    icon: Icons.looks_one_outlined,
    color: Colors.teal,
    routeName: '/activity-1',
  ),
  ActivityInfo(
    number: 2,
    title: 'Activity 2',
    subtitle: 'Open Network Monitor',
    icon: Icons.looks_two_outlined,
    color: Colors.deepPurple,
    routeName: '/activity-2',
  ),
  ActivityInfo(
    number: 3,
    title: 'Activity 3',
    subtitle: 'Empty — add your project here',
    icon: Icons.looks_3_outlined,
    color: Colors.orange,
    routeName: '/activity-3',
  ),
  ActivityInfo(
    number: 4,
    title: 'Activity 4',
    subtitle: 'Empty — add your project here',
    icon: Icons.looks_4_outlined,
    color: Colors.indigo,
    routeName: '/activity-4',
  ),
  ActivityInfo(
    number: 5,
    title: 'Activity 5',
    subtitle: 'Empty — add your project here',
    icon: Icons.looks_5_outlined,
    color: Colors.pink,
    routeName: '/activity-5',
  ),
];

class HomeScreen extends StatelessWidget {
  static const routeName = '/';
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // context.watch subscribes this widget to rebuilds whenever
    // AppStateProvider calls notifyListeners().
    final appState = context.watch<AppStateProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile Computing 2 Portfolio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.network_check_outlined),
            tooltip: 'Network Monitor',
            onPressed: () => Navigator.pushNamed(
              context,
              NetworkMonitorScreen.routeName,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () =>
                Navigator.pushNamed(context, SettingsScreen.routeName),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Simple responsive breakpoint: two cards per row on wider
            // screens (tablets/desktop/web), one per row on phones.
            final isWide = constraints.maxWidth > 640;
            // ignore: prefer_const_declarations
            final gutter = 16.0;
            final cardWidth = isWide
                ? (constraints.maxWidth - gutter) / 2
                : constraints.maxWidth;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appState.userName,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Activities',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  // Wrap lays cards out left-to-right, top-to-bottom and
                  // adapts to any activity count without manual row math.
                  Wrap(
                    spacing: gutter,
                    runSpacing: gutter,
                    children: kActivities.map((activity) {
                      return SizedBox(
                        width: cardWidth,
                        child: DashboardCard(
                          title: activity.title,
                          subtitle: activity.subtitle,
                          icon: activity.icon,
                          color: activity.color,
                          isCompleted:
                              appState.isActivityCompleted(activity.number),
                          onTap: () =>
                              Navigator.pushNamed(context, activity.routeName),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
