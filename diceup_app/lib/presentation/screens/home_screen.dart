import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../data/local/app_startup.dart';
import '../../data/local/database_recovery.dart';
import '../../data/local/snapshot_recovery.dart';
import '../../domain/engine/game_state.dart';
import '../app_dependencies_scope.dart';
import '../navigation/app_routes.dart';

/// Main menu / home screen (SRS UI-01, FR-01).
///
/// Guests reach every offline feature from here with no account and no
/// internet. Online entries are present but not yet functional: the Play
/// Online button is enabled and shows a "coming in Phase 5" snackbar —
/// no login prompt yet (the login-prompt dialog is an M2 fix, M-13).
/// The online flow lands in Phase 5.
///
/// Startup notices (M1.6) are shown here, exactly once, after the
/// first frame: the database-recovery message, the corrupt-snapshot
/// message, or the startup-failure message — each a snackbar, per
/// the app's existing snackbar usage. When a valid snapshot exists,
/// this screen offers the resume choice (SDD §6.6 "on launch"):
/// the dialog lives on Home, not on the splash, because the splash
/// is a brand moment that must never host a decision — Home is the
/// first interactive screen, so the choice is made where the user
/// can act on it. Resume navigates to the game with the restored
/// state; Discard deletes the snapshot and starts no match.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Guards the one-shot startup handling in [didChangeDependencies]
  /// (which can run more than once): notices and the resume dialog
  /// are offered exactly once per Home lifetime.
  bool _startupHandled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_startupHandled) return;
    _startupHandled = true;
    final startup = AppDependenciesScope.maybeOf(context)?.startup;
    if (startup == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showStartupNotices(startup);
    });
  }

  Future<void> _showStartupNotices(StartupResult startup) async {
    if (startup.startupError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kStartupDatabaseErrorMessage)),
      );
    } else if (startup.databaseRecovered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kDatabaseRecoveryMessage)),
      );
    }
    final outcome = startup.snapshotOutcome;
    if (outcome is CorruptSnapshotDiscarded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kCorruptSnapshotMessage)),
      );
    } else if (outcome is ValidSnapshot) {
      await _offerResume(startup, outcome);
    }
  }

  /// Offers the saved match. Returns after the user chooses (or
  /// dismisses): Resume navigates to the game with the restored
  /// state, Discard deletes the snapshot and starts no match, a
  /// dismiss leaves the snapshot in place for the next launch.
  Future<void> _offerResume(
    StartupResult startup,
    ValidSnapshot outcome,
  ) async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Resume your match?'),
        content: const Text(
          'You have a match in progress. Resume where you left '
          'off, or discard it and start fresh.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Discard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (resume == true) {
      final decoded = jsonDecode(outcome.snapshot.snapshotJson);
      final state = GameState.fromJson(decoded as Map<String, Object?>);
      Navigator.of(context).pushNamed(AppRoutes.game, arguments: state);
    } else if (resume == false) {
      // Discard through the saver so a queued snapshot write can
      // never resurrect the discarded match.
      await startup.dependencies?.snapshotSaver.discard();
    }
  }

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
              const SizedBox(height: DiceUpSpacing.md),
              SecondaryButton(
                label: 'Statistics',
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.statistics),
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
