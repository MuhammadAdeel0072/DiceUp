import 'package:flutter/material.dart';

import '../../core/design_system/diceup_spacing.dart';

/// Application settings (SRS FR-08, FR-32).
///
/// Sound and vibration preferences work for the session. They are
/// persisted to SQLite in Phase 3 (local_settings table, SDD §9.1);
/// until then a restart resets them to on — this is recorded in
/// docs/IMPLEMENTATION-PLAN.md, not hidden from the user.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _soundOn = true;
  bool _vibrationOn = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: DiceUpSpacing.screenPadding,
        children: [
          SwitchListTile(
            title: const Text('Sound'),
            subtitle: const Text('Dice and move sounds'),
            value: _soundOn,
            onChanged: (value) => setState(() => _soundOn = value),
          ),
          SwitchListTile(
            title: const Text('Vibration'),
            subtitle: const Text('Haptic feedback on moves'),
            value: _vibrationOn,
            onChanged: (value) => setState(() => _vibrationOn = value),
          ),
          const SizedBox(height: DiceUpSpacing.lg),
          Text(
            'DiceUp 1.0.0 — offline-first Ludo. Online play, friends and '
            'leaderboards arrive in later phases.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
