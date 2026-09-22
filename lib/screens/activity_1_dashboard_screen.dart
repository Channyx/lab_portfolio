import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';
import '../widgets/dashboard_card.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class Activity1DashboardScreen extends StatelessWidget {
  static const routeName = '/activity-1';

  const Activity1DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    final dashboardActivities =
        kActivities.where((activity) => activity.number >= 3).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity 1 Dashboard'),
        actions: [
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
            final isWide = constraints.maxWidth > 640;
            const gutter = 16.0;
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
                  const SizedBox(height: 8),
                  Text(
                    'Activity 1 Dashboard',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.dashboard_outlined),
                      title: const Text('Dashboard ready'),
                      subtitle: Text(
                        '${appState.completedCount} of ${kActivities.length} activities completed',
                      ),
                    ),
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
                  Wrap(
                    spacing: gutter,
                    runSpacing: gutter,
                    children: dashboardActivities.map((activity) {
                      return SizedBox(
                        width: cardWidth,
                        child: DashboardCard(
                          title: activity.title,
                          subtitle: activity.subtitle,
                          icon: activity.icon,
                          color: activity.color,
                          isCompleted:
                              appState.isActivityCompleted(activity.number),
                          onTap: () => Navigator.pushNamed(
                            context,
                            activity.routeName,
                          ),
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
