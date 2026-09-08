import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state_provider.dart';

class SettingsScreen extends StatefulWidget {
  static const routeName = '/settings';

  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameController;
  late final FocusNode _nameFocusNode;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppStateProvider>();
    _nameController = TextEditingController(text: appState.userName);
    _nameFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _saveName() {
    context.read<AppStateProvider>().updateUserName(_nameController.text);
    _nameFocusNode.unfocus();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppStateProvider>();
    if (!_nameFocusNode.hasFocus &&
        _nameController.text != appState.userName) {
      _nameController.text = appState.userName;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Profile',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('profile-name-field'),
              controller: _nameController,
              focusNode: _nameFocusNode,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'User Profile Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              onSubmitted: (_) => _saveName(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saveName,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save name'),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Appearance',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: SwitchListTile(
                title: const Text('Dark theme'),
                subtitle: Text(
                  appState.isDarkMode
                      ? 'Currently using dark mode'
                      : 'Currently using light mode',
                ),
                secondary: Icon(
                  appState.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                ),
                value: appState.isDarkMode,
                onChanged: (value) =>
                    context.read<AppStateProvider>().toggleTheme(value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
