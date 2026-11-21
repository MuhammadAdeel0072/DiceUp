import 'package:flutter/material.dart';

import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../navigation/app_routes.dart';

/// Game mode selection (SRS UI-02, FR-12).
///
/// Offline modes are fully available. The online card is visible but
/// honestly unavailable until Phase 5 — it explains that instead of
/// navigating to a dead end.
class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a mode')),
      body: Padding(
        padding: DiceUpSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DiceUpCard(
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.offlineSetup,
                arguments: OfflineMode.vsAi,
              ),
              child: const _ModeRow(
                icon: Icons.smart_toy_outlined,
                title: 'Play vs AI',
                subtitle: 'You against computer opponents (Easy, Medium, Hard).',
              ),
            ),
            const SizedBox(height: DiceUpSpacing.md),
            DiceUpCard(
              onTap: () => Navigator.of(context).pushNamed(
                AppRoutes.offlineSetup,
                arguments: OfflineMode.local,
              ),
              child: const _ModeRow(
                icon: Icons.people_outline,
                title: 'Local multiplayer',
                subtitle: '2–4 players sharing this device.',
              ),
            ),
            const SizedBox(height: DiceUpSpacing.md),
            const DiceUpCard(
              child: _ModeRow(
                icon: Icons.public_outlined,
                title: 'Online multiplayer',
                subtitle: 'Rooms, friends and live matches — coming in Phase 5.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: DiceUpSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: DiceUpSpacing.xxs),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const Icon(Icons.chevron_right),
      ],
    );
  }
}
