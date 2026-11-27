/// The Riverpod composition root (M3.3, H-07; D-06).
///
/// The single wiring point (SDD §3.2): repositories → use cases →
/// [OfflineGameController] → screens. [main] awaits
/// [initializeApp] before the first frame and [DiceUpApp] exposes
/// the completed [StartupResult] here, so every provider below
/// reads from one startup outcome and no screen constructs a
/// repository, a use case or a controller directly (enforced by
/// `tool/check_boundaries.sh`).
///
/// The domain stays framework-free: [OfflineGameController] is
/// plain Dart and takes its collaborators by constructor injection;
/// this file is the only place that constructs it in production
/// code. The view ([GameScreen]) reads the controller through
/// [offlineGameControllerProvider] and holds no copy of the game
/// state — a state change driven through the provider is what the
/// screen renders, never a second copy.
///
/// Lifecycle: [offlineGameControllerProvider] is `autoDispose`. The
/// game screen watches it while mounted, which keeps the provider
/// alive; when the screen leaves, the last listener drops and the
/// provider disposes the controller (timers cancelled) via
/// `ref.onDispose`. The screen never disposes a provider-owned
/// controller itself. A fresh navigation to the game route creates
/// a fresh controller — a fresh match per navigation, exactly as
/// the pre-Riverpod screen built a fresh controller per screen.
///
/// Tests override providers in a [ProviderScope]: see
/// `test/test_providers.dart`. Overriding [diceRollerProvider]
/// (fixed dice), [feedbackServiceProvider] (recording fake) or
/// [vibrationEnabledProvider] replaces the production wiring
/// without touching the screen — those are the only seams, and
/// there is exactly one of each: [GameScreen] takes no controller,
/// dice, feedback or vibration parameter anymore.
///
/// Single-scope rule: there is exactly one [ProviderScope] per
/// widget tree. [DiceUpApp] owns the app tree's scope (with named
/// test seams — fixed dice, fake feedback, vibration flag — for
/// tests); a bare screen's tests build their own scope via
/// `test/test_providers.dart`. Never nest scopes: Riverpod owns a
/// non-overridden provider in the outermost scope, so its
/// transitive watches resolve there and cannot see an inner
/// scope's overrides — the controller graph would read the
/// un-overridden [startupResultProvider] and fail (verified by
/// probe 2026-11-22: a [DiceUpApp] wrapped in an outer scope
/// fails to start a match, while the same tree with a single
/// scope works).
///
/// Not yet migrated (explicit next step, recorded in
/// docs/IMPLEMENTATION-PLAN.md M3.3): the settings, history,
/// statistics, home and setup screens still read their
/// repositories through [AppDependenciesScope] (M1.6). They are
/// migrated one screen at a time; the game flow + startup wiring
/// in this file is the M3.3 scope.
library;

import 'dart:async';

import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/local/app_startup.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/offline_game_controller.dart';
import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/local_player_repository.dart';
import 'package:diceup/domain/repositories/local_statistics_repository.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:diceup/domain/snapshot_writer.dart';
import 'package:diceup/domain/usecases/apply_move.dart';
import 'package:diceup/domain/usecases/roll_dice.dart';
import 'package:diceup/domain/usecases/start_offline_match.dart';
import 'package:diceup/presentation/feedback/feedback_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The completed startup outcome. Must be provided by the app
/// entry ([DiceUpApp] overrides it with the awaited
/// [initializeApp] result, or with its own initializer's result in
/// tests). There is no default: a screen that reads the graph
/// without a provided startup fails loudly instead of silently
/// playing with the wrong repositories.
final startupResultProvider = Provider<StartupResult>(
  (ref) => throw UnimplementedError(
    'No StartupResult provided — the app must run inside DiceUpApp '
    '(or a test ProviderScope overriding startupResultProvider).',
  ),
);

/// The repositories built at startup, or null when the database
/// could not be opened even after recovery (degraded play: the
/// match stays playable, nothing is persisted).
final appDependenciesProvider = Provider<AppDependencies?>(
  (ref) => ref.watch(startupResultProvider).dependencies,
);

/// Repository providers: each is the same instance the startup
/// dependencies hold — one construction site, no second copy.
final localMatchRepositoryProvider = Provider<LocalMatchRepository?>(
  (ref) => ref.watch(appDependenciesProvider)?.matches,
);

final localStatisticsRepositoryProvider = Provider<LocalStatisticsRepository?>(
  (ref) => ref.watch(appDependenciesProvider)?.statistics,
);

final settingsRepositoryProvider = Provider<SettingsRepository?>(
  (ref) => ref.watch(appDependenciesProvider)?.settings,
);

final localPlayerRepositoryProvider = Provider<LocalPlayerRepository?>(
  (ref) => ref.watch(appDependenciesProvider)?.players,
);

final snapshotRepositoryProvider = Provider<SnapshotRepository?>(
  (ref) => ref.watch(appDependenciesProvider)?.snapshots,
);

/// The serialised snapshot writer (FR-29): the dependencies'
/// single ordered [SnapshotSaver], shared by the game screen's
/// roll saves and the controller's move saves.
final snapshotWriterProvider = Provider<SnapshotWriter?>(
  (ref) => ref.watch(appDependenciesProvider)?.snapshotSaver,
);

/// Dice source. Null in production (the engine's random roller);
/// tests override with a [FixedDiceRoller].
final diceRollerProvider = Provider<DiceRoller?>((ref) => null);

/// Haptics behind the [FeedbackService] abstraction (M1.7, D-32).
/// Production sends one light impact per completed move; tests
/// override with a recording fake.
final feedbackServiceProvider = Provider<FeedbackService>(
  (ref) => const HapticFeedbackService(),
);

/// Vibration override. Null in production (the controller resolves
/// the persisted setting itself); tests override with `true` /
/// `false` to pin the gate without touching storage.
final vibrationEnabledProvider = Provider<bool?>((ref) => null);

// -- Use cases (M3.1) -----------------------------------------------------

/// Starts a fresh offline match from a [MatchSetup] (thin
/// orchestration over the engine; the dice source comes from
/// [diceRollerProvider]).
final startOfflineMatchProvider = Provider<StartOfflineMatch>(
  (ref) => StartOfflineMatch(diceRoller: ref.watch(diceRollerProvider)),
);

/// Rolls the dice for the current player (synchronous, no
/// persistence of its own — the controller persists the result).
final rollDiceProvider = Provider<RollDice>((ref) => RollDice());

/// Applies one move and owns its persistence side effects
/// (snapshot-after-move, exactly-once completion recording).
/// Null when there is nothing to persist into (degraded startup):
/// the controller then applies the engine move without recording,
/// exactly as it did before M3.3.
final applyMoveProvider = Provider<ApplyMove?>((ref) {
  final matches = ref.watch(localMatchRepositoryProvider);
  final snapshots = ref.watch(snapshotRepositoryProvider);
  if (matches == null || snapshots == null) return null;
  return ApplyMove(
    matches: matches,
    snapshots: snapshots,
    snapshotWriter: ref.watch(snapshotWriterProvider),
  );
});

// -- Controller -----------------------------------------------------------

/// The offline match controller, owned by the provider graph.
///
/// Constructed from the repository, use-case and feedback
/// providers above; disposed (timers cancelled) when the last
/// listener — the game screen — leaves. Behaviour is bit-identical
/// to the pre-Riverpod screen: same 700–1,199 ms AI pacing (D-31),
/// same 6 x 90 ms dice tumble, same status strings, same win
/// trigger, same snapshot/completion semantics.
///
/// Vibration resolution preserves the M3.2 screen's exact
/// expression: the override wins, otherwise the startup-loaded
/// value, otherwise on. Note `loadedSettings` is currently always
/// empty from [AppDependencies.fromDatabase] (startup loads the
/// settings into [StartupResult.settings] instead), so the
/// effective initial value is on and the persisted value is picked
/// up by the controller's repository refresh after start — the
/// quirk is preserved, not silently fixed, in M3.3.
final offlineGameControllerProvider =
    Provider.autoDispose<OfflineGameController>((ref) {
      final dependencies = ref.watch(appDependenciesProvider);
      final feedback = ref.watch(feedbackServiceProvider);
      final vibrationOverride = ref.watch(vibrationEnabledProvider);
      final controller = OfflineGameController(
        diceRoller: ref.watch(diceRollerProvider),
        matches: ref.watch(localMatchRepositoryProvider),
        settings: ref.watch(settingsRepositoryProvider),
        snapshots: ref.watch(snapshotRepositoryProvider),
        snapshotWriter: ref.watch(snapshotWriterProvider),
        startOfflineMatch: ref.watch(startOfflineMatchProvider),
        rollDice: ref.watch(rollDiceProvider),
        applyMove: ref.watch(applyMoveProvider),
        vibrationEnabled:
            vibrationOverride ??
            (dependencies?.loadedSettings['vibration_enabled'] != '0'),
        vibrationRefreshEnabled: vibrationOverride == null,
        // One light haptic per completed move (M1.7, D-32), wired
        // here — the controller's [onMoveApplied] hook — so the
        // screen never touches haptics directly. Fire-and-forget
        // and never throwing into the turn loop, exactly as the
        // screen's `_vibrateOnMove` did.
        onMoveApplied: () {
          unawaited(feedback.vibrateMove().catchError((_) {}));
        },
      );
      ref.onDispose(controller.dispose);
      return controller;
    });
