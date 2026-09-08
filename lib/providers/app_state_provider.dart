import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds all global, app-wide state.
///
/// Anything placed here is accessible from every screen via
/// `context.watch<AppStateProvider>()` (to rebuild on change) or
/// `context.read<AppStateProvider>()` (to call methods without rebuilding).
class AppStateProvider extends ChangeNotifier {
  static const _userNameKey = 'user_name';
  static const _defaultUserName = 'Christian Dancel & Louiela Fernandez';

  ThemeMode _themeMode = ThemeMode.light;
  String _userName = _defaultUserName;

  AppStateProvider() {
    _loadUserName();
  }

  // Tracks which activity numbers (1-5) have been marked complete.
  // A Set is used so toggling the same activity twice is a safe
  // add/remove rather than an ever-growing counter.
  final Set<int> _completedActivities = {};

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  String get userName => _userName;

  Set<int> get completedActivities => Set.unmodifiable(_completedActivities);
  int get completedCount => _completedActivities.length;
  bool isActivityCompleted(int activityNumber) =>
      _completedActivities.contains(activityNumber);

  /// Flips between light and dark theme. Called from the Settings screen,
  /// but instantly reflected on the Home Dashboard and every other screen
  /// because they all listen to this provider.
  void toggleTheme(bool useDark) {
    _themeMode = useDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  /// Updates the global user profile name.
  void updateUserName(String newName) {
    final trimmedName = newName.trim();
    if (trimmedName.isEmpty || trimmedName == _userName) return;

    _userName = trimmedName;
    notifyListeners();
    _saveUserName(trimmedName);
  }

  Future<void> _loadUserName() async {
    final preferences = await SharedPreferences.getInstance();
    final savedName = preferences.getString(_userNameKey)?.trim();

    if (savedName == null || savedName.isEmpty) {
      await preferences.setString(_userNameKey, _defaultUserName);
      return;
    }

    if (savedName == _userName) return;
    _userName = savedName;
    notifyListeners();
  }

  Future<void> _saveUserName(String name) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_userNameKey, name);
  }

  /// Marks an activity complete/incomplete. Called from any Activity
  /// screen; the Home Dashboard's progress banner and card badges update
  /// instantly because they watch this provider.
  void toggleActivityCompletion(int activityNumber) {
    if (_completedActivities.contains(activityNumber)) {
      _completedActivities.remove(activityNumber);
    } else {
      _completedActivities.add(activityNumber);
    }
    notifyListeners();
  }

  void resetProgress() {
    _completedActivities.clear();
    notifyListeners();
  }
}
