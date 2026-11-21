import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../navigation/app_routes.dart';

/// Main menu / home screen (SRS UI-01, FR-01).
///
/// Guests reach every offline feature from here with no account and no
/// internet. Online entries are present but not yet functional: the Play
/// Online button is enabled and shows a "coming in Phase 5" snackbar —
/// no login prompt yet (the login-prompt dialog is an M2 fix, M-13).
/// The online flow lands in Phase 5.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DiceUp'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: DiceUpSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: DiceUpSpacing.md),
              Text(
                'Ready to play?',
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: DiceUpSpacing.xs),
              Text(
                'Classic Ludo — offline, with friends, or online.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: DiceUpColors.textSecondary,
                    ),
              ),
              const SizedBox(height: DiceUpSpacing.xl),
              PrimaryButton(
                label: 'Play Offline',
                onPressed: () => Navigator.of(context)
                    .pushNamed(AppRoutes.modeSelection),
              ),
              const SizedBox(height: DiceUpSpacing.md),
              SecondaryButton(
                label: 'Play Online',
                onPressed: () => _showOnlineComingSoon(context),
              ),
              const SizedBox(height: DiceUpSpacing.md),
              SecondaryButton(
                label: 'Match History',
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.history),
              ),
              const Spacer(),
              const Text(
                'Offline play works without an account or internet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: DiceUpColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOnlineComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Online play arrives in Phase 5. Offline play is ready now.',
        ),
      ),
    );
  }

}
