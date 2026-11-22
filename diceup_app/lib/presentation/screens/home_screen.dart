import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../data/local/app_startup.dart';
import '../../data/local/snapshot_recovery.dart';
import '../../domain/engine/game_state.dart';
import '../../domain/repositories/snapshot_repository.dart';
import '../../l10n/app_strings.dart';
import '../app_dependencies_scope.dart';
import '../navigation/app_routes.dart';

/// Main menu / home screen (SRS UI-01, FR-01).
///
/// Guests reach every offline feature from here with no account and no
/// internet. Online entries are present but not yet functional: the Play
/// Online button is enabled and shows the login-prompt dialog (M2.10,
/// M-13) — online play itself lands in Phase 5, so the dialog is
/// honest about what exists today rather than navigating anywhere.
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
    final l10n = stringsOf(context);
    if (startup.startupError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.homeDatabaseError)));
    } else if (startup.databaseRecovered) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.homeDatabaseRecovered)));
    }
    final outcome = startup.snapshotOutcome;
    if (outcome is CorruptSnapshotDiscarded) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.homeSnapshotCorrupt)));
    } else if (outcome is ValidSnapshot) {
      await _offerResume(startup, outcome);
    }
  }

  /// Offers the saved match. Returns after the user chooses (or
  /// dismisses): Resume navigates to the game with the restored
  /// state, Discard deletes the snapshot and starts no match, a
  /// dismiss leaves the snapshot in place for the next launch.
  ///
  /// Re-check (M2.6): the startup outcome is frozen at launch, but
  /// the snapshot may have been deleted since — a match that
  /// finished, or was exited from the pause menu, after startup
  /// (the exit lands on a fresh Home mid-lifetime, which re-runs
  /// this offer). Never offer a snapshot that no longer exists:
  /// resuming it would restore — and, at completion, re-record —
  /// a match that is already gone. When there is nothing to check
  /// against (degraded startup, no repositories) the frozen
  /// outcome is offered as before.
  Future<void> _offerResume(
    StartupResult startup,
    ValidSnapshot outcome,
  ) async {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final snapshots = startup.dependencies?.snapshots;
    if (snapshots != null) {
      final stillThere = await snapshots.hasSnapshot(kCurrentMatchKey);
      if (!mounted || !stillThere) return;
    }
    final l10n = stringsOf(context);
    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.homeResumeTitle),
        content: Text(l10n.homeResumeMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.homeResumeDiscard),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.homeResumeResume),
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
    final l10n = stringsOf(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n.homeSettingsTooltip,
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.settings),
          ),
        ],
      ),
      body: SafeArea(
        // M2.12 (NFR-09): the column scrolls when it cannot fit
        // (320x568 with a wide font, or a large system text
        // scale) instead of overflowing — a Column + Spacer with
        // no scroll view overflowed by 27 px at 320x568 in the
        // test harness. The ConstrainedBox + IntrinsicHeight keep
        // the tall-screen layout identical: the column is at least
        // as tall as the viewport (minus the scroll padding), so
        // the Spacer still pins the footnote to the bottom and
        // nothing moves on screens where everything already fit.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: DiceUpSpacing.screenPadding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    constraints.maxHeight -
                    DiceUpSpacing.screenPadding.vertical,
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: DiceUpSpacing.md),
                    Text(
                      l10n.homeReadyTitle,
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: DiceUpSpacing.xs),
                    Text(
                      l10n.homeReadySubtitle,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(color: DiceUpColors.textSecondary),
                    ),
                    const SizedBox(height: DiceUpSpacing.xl),
                    PrimaryButton(
                      label: l10n.homePlayOffline,
                      onPressed: () =>
                          Navigator.of(context)
                              .pushNamed(AppRoutes.modeSelection),
                    ),
                    const SizedBox(height: DiceUpSpacing.md),
                    SecondaryButton(
                      label: l10n.homePlayOnline,
                      onPressed: () => _showOnlineLoginPrompt(context),
                    ),
                    const SizedBox(height: DiceUpSpacing.md),
                    SecondaryButton(
                      label: l10n.homeMatchHistory,
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.history),
                    ),
                    const SizedBox(height: DiceUpSpacing.md),
                    SecondaryButton(
                      label: l10n.homeStatistics,
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.statistics),
                    ),
                    const Spacer(),
                    Text(
                      l10n.homeOfflineNote,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: DiceUpColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Login prompt for the online entry (M2.10, M-13; UI-01/FR-42):
  /// guests are asked to log in, and told plainly that online play
  /// arrives in Phase 5 — a dialog, not a transient snackbar, so the
  /// prompt cannot be missed or mistaken for navigation.
  void _showOnlineLoginPrompt(BuildContext context) {
    final l10n = stringsOf(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.homePlayOnline),
        content: Text(l10n.homeOnlineMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }
}
