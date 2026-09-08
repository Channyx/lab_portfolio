import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';


class ActivityPlaceholderScreen extends StatelessWidget {
  final int activityNumber;
  final String title;
  final IconData icon;
  final Color color;

  const ActivityPlaceholderScreen({
    super.key,
    required this.activityNumber,
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    // watch() so the "mark complete" button reflects state changes made
    // from elsewhere (e.g. if you add a "reset progress" action later).
    final appState = context.watch<AppStateProvider>();
    final isCompleted = appState.isActivityCompleted(activityNumber);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          // Column + Expanded keeps this centered and responsive on any
          // screen size without needing fixed heights.
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: color, size: 44),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'This activity is empty.\n'
                        'Build your project inside this screen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
              // A small demo hook into global state, so this placeholder
              // still shows the Home Dashboard updating live. Remove this
              // once your real activity has its own completion logic.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context
                      .read<AppStateProvider>()
                      .toggleActivityCompletion(activityNumber),
                  icon: Icon(
                    isCompleted
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    color: isCompleted ? Colors.green : null,
                  ),
                  label: Text(
                    isCompleted
                        ? 'Marked complete — tap to undo'
                        : 'Mark this activity complete',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
