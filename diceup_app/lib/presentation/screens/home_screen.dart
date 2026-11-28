import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_shadows.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../core/design_system/diceup_typography.dart';
import '../../data/local/app_startup.dart';
import '../../data/local/snapshot_recovery.dart';
import '../../domain/engine/game_state.dart';
import '../../domain/repositories/snapshot_repository.dart';
import '../../l10n/app_strings.dart';
import '../app_dependencies_scope.dart';
import '../navigation/app_routes.dart';
import '../providers/app_providers.dart';

/// Main menu / home screen (SRS UI-01, FR-01).
///
/// Guests reach every offline feature from here with no account and no
/// internet. Online entries are present but not yet functional: the Play
/// Online button is enabled and shows the login-prompt dialog (M2.10,
/// M-13) — its Log in action routes to the login screen (Phase 5,
/// Stage 2), and signed-in players see their account state there;
/// online play itself (rooms, matches) lands in later stages, so the
/// dialog stays honest about what exists today rather than navigating
/// anywhere playable.
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
///
/// Presentation (redesign Stage 3A, REDESIGN-PLAN.md §3.1): a navy
/// brand panel — the four seat shapes in their on-dark player
/// colours, the "Ready to play?" headline and the tagline in white
/// on the table field, one restrained gold rule — then a single
/// primary Play action, History and Statistics as a secondary row,
/// the online entry as a quiet muted row (never a primary-styled
/// button), and the offline footnote in the caption style. Content
/// centres in a [DiceUpSpacing.maxContentWidth] column on wide
/// screens. Navigation, resume and settings behaviour are unchanged.
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
    // Start the auth session restore (Phase 5, Stage 2; FR-09):
    // Home is the first interactive screen, so the persisted
    // session restores at launch, not at the first Play Online tap.
    // Read, not watch — Home renders the same either way, and a
    // Consumer in build would crash bare-screen tests (no
    // ProviderScope; see the Play Online note below).
    try {
      ProviderScope.containerOf(context).read(authStateProvider);
    } on StateError {
      // No scope — a bare-screen test; the online prompt falls back
      // to the guest dialog.
    }
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
    // DiceUpDialog shell (redesign Stage 2, F7): same copy, same
    // non-dismissible barrier, same Discard/Resume actions.
    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DiceUpDialog(
        title: l10n.homeResumeTitle,
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
        // The Align + maxContentWidth centre the column on wide
        // screens (tablets) instead of stretching it full-width.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: DiceUpSpacing.screenPadding,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DiceUpSpacing.maxContentWidth,
                ),
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
                        _BrandHeader(
                          title: l10n.homeReadyTitle,
                          subtitle: l10n.homeReadySubtitle,
                        ),
                        const SizedBox(height: DiceUpSpacing.xl),
                        PrimaryButton(
                          label: l10n.homePlayOffline,
                          onPressed: () =>
                              Navigator.of(context)
                                  .pushNamed(AppRoutes.modeSelection),
                        ),
                        const SizedBox(height: DiceUpSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: SecondaryButton(
                                label: l10n.homeMatchHistory,
                                onPressed: () =>
                                    Navigator.of(context)
                                        .pushNamed(AppRoutes.history),
                              ),
                            ),
                            const SizedBox(width: DiceUpSpacing.md),
                            Expanded(
                              child: SecondaryButton(
                                label: l10n.homeStatistics,
                                onPressed: () =>
                                    Navigator.of(context)
                                        .pushNamed(AppRoutes.statistics),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: DiceUpSpacing.md),
                        // The online entry stays honest (M-13) and
                        // visually quiet: a muted text row, never a
                        // primary- or secondary-styled button, so it
                        // never reads as a playable mode. The tap
                        // opens the online prompt (Phase 5, Stage 2:
                        // guests get the login prompt with a Log in
                        // action; signed-in players get their
                        // account state). The prompt reads the auth
                        // state at tap time, not in build — bare
                        // screens (layout / accessibility tests) run
                        // without a ProviderScope, and a Consumer
                        // here would crash them (verified 2026-11-28:
                        // "No ProviderScope found" in layout_320).
                        TextButton.icon(
                          icon: const Icon(Icons.public_outlined, size: 20),
                          label: Text(l10n.homePlayOnline),
                          style: TextButton.styleFrom(
                            foregroundColor: DiceUpColors.textSecondary,
                          ),
                          onPressed: () => _showOnlinePrompt(context),
                        ),
                        const Spacer(),
                        Text(
                          l10n.homeOfflineNote,
                          textAlign: TextAlign.center,
                          style: DiceUpTypography.caption,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Online entry (M2.10, M-13; UI-01/FR-42; Phase 5, Stage 2):
  /// guests are asked to log in — the dialog's Log in action routes
  /// to the login screen — and told plainly that online play
  /// arrives in Phase 5. Signed-in players see who they are signed
  /// in as, with account and log-out actions; rooms themselves
  /// arrive in the next stage, so nothing here pretends a match can
  /// start. A dialog, not a transient snackbar, so the prompt
  /// cannot be missed or mistaken for navigation.
  ///
  /// The auth state is read at tap time through the enclosing
  /// [ProviderScope] — never watched in build (see the note on the
  /// Play Online row): without a scope (bare-screen tests) the
  /// prompt falls back to the guest dialog instead of crashing.
  void _showOnlinePrompt(BuildContext context) {
    final l10n = stringsOf(context);
    AuthState? auth;
    ProviderContainer? container;
    try {
      container = ProviderScope.containerOf(context);
      auth = container.read(authStateProvider);
    } on StateError {
      auth = null;
      container = null;
    }
    final user = auth?.user;
    if (auth?.status == AuthStatus.signedIn && user != null) {
      DiceUpDialog.show<void>(
        context,
        title: l10n.homePlayOnline,
        content: Text(l10n.homeOnlineSignedIn(user.displayName)),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await container?.read(authStateProvider.notifier).logout();
            },
            child: Text(l10n.homeOnlineLogOut),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed(AppRoutes.account);
            },
            child: Text(l10n.homeOnlineViewAccount),
          ),
          // Phase 5, Stage 3: rooms are live — the lobby is one tap
          // from the signed-in prompt.
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed(AppRoutes.onlineLobby);
            },
            child: Text(l10n.homeOnlinePlay),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ok),
          ),
        ],
      );
      return;
    }
    DiceUpDialog.show<void>(
      context,
      title: l10n.homePlayOnline,
      content: Text(l10n.homeOnlineMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.ok),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed(AppRoutes.login);
          },
          child: Text(l10n.loginTitle),
        ),
      ],
    );
  }
}

/// The Home brand header (redesign Stage 3A): the navy table field
/// as a panel, with the four seat shapes in their on-dark player
/// colours (shape + colour, never colour alone — D-27), the headline
/// and tagline in white, and a single restrained gold rule. No new
/// asset, no gradient, no glow — typography and the seat shapes
/// carry the brand moment. The shapes are decorative: the headline
/// already names the screen for a screen reader.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DiceUpSpacing.lg),
      decoration: BoxDecoration(
        color: DiceUpColors.table,
        borderRadius: DiceUpSpacing.radiusLgBorder,
        boxShadow: DiceUpShadows.table,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                for (var seat = 0; seat < 4; seat++) ...[
                  if (seat > 0) const SizedBox(width: DiceUpSpacing.xs),
                  PlayerShapeMarker(
                    shape: PlayerShape.forSeat(seat),
                    color: DiceUpColors.playerColorOnDark(seat),
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: DiceUpSpacing.md),
          Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.displayLarge
                  ?.copyWith(color: DiceUpColors.textOnDark),
            ),
          ),
          const SizedBox(height: DiceUpSpacing.xs),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: DiceUpColors.textOnDark),
          ),
          const SizedBox(height: DiceUpSpacing.md),
          Container(
            width: 48,
            height: 3,
            decoration: const BoxDecoration(
              color: DiceUpColors.gold,
              borderRadius: DiceUpSpacing.radiusSmBorder,
            ),
          ),
        ],
      ),
    );
  }
}
