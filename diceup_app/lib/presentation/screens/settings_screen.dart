import 'package:flutter/material.dart';

import '../../core/design_system/diceup_spacing.dart';

/// Application settings (SRS FR-08, FR-32).
///
/// Sound and vibration preferences work for the session only — they are
/// not persisted yet (SQLite `local_settings`, SDD §9.1, lands in M1);
/// a restart resets them to on. The toggles are placebos today: no sound
/// or haptics code exists behind them (M-12). The vibration toggle becomes
/// real in M2.11 (haptics per D-32); the sound toggle is removed or shown
/// disabled with an honest note until sound lands. Phase 3 is reopened —
/// see docs/IMPLEMENTATION-PLAN.md §5. The UI itself shows no note yet
/// (a visible note is an M2 fix, C-12).
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
