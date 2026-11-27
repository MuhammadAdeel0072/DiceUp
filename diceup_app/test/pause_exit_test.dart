import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/local/app_startup.dart';
import 'package:diceup/data/local/snapshot_recovery.dart';
import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/move.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/token.dart';
import 'package:diceup/domain/offline_game_controller.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:diceup/domain/usecases/match_setup.dart';
import 'package:diceup/main.dart';
import 'package:diceup/presentation/app_dependencies_scope.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/game_screen.dart';
import 'package:diceup/presentation/screens/home_screen.dart';
import 'package:diceup/presentation/screens/offline_setup_screen.dart';
import 'package:diceup/presentation/screens/results_screen.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine/test_helpers.dart';
import 'repositories/fakes/fakes.dart';

/// M2.6 pause menu + back confirmation (M-01; D-10, D-30; FR-27/28):
/// the controller freeze (AI + dice timers stop, state preserved,
/// resume restarts the turn flow exactly once) and the screen flows
/// (pause menu actions, system back in each state, exit landing on
/// Home from every entry path, no stale resume re-offer).
void main() {
  // -- Manual timers (controller tests) -----------------------------------
  //
  // Same shape as `test/offline_game_controller_test.dart`'s helpers
  // (file-local there): a timer the test fires by hand, so the
  // freeze is asserted on scheduled callbacks, never wall-clock.

  group('OfflineGameController pause/resume', () {
    late InMemoryStore store;
    late InMemoryLocalMatchRepository matches;
    late InMemorySnapshotRepository snapshots;
    late InMemorySettingsRepository settings;
    late SnapshotSaver writer;
    late _ManualTimers timers;

    OfflineGameController makeController({DiceRoller? diceRoller}) {
      final controller = OfflineGameController(
        diceRoller: diceRoller,
        matches: matches,
        settings: settings,
        snapshots: snapshots,
        snapshotWriter: writer,
        now: _fixedNow,
        random: Random(42),
        oneShotTimer: timers.oneShot,
        periodicTimer: timers.periodic,
      );
      return controller;
    }

    setUp(() {
      store = InMemoryStore();
      matches = InMemoryLocalMatchRepository(store);
      snapshots = InMemorySnapshotRepository(store);
      settings = InMemorySettingsRepository(store);
      writer = SnapshotSaver(snapshots);
      timers = _ManualTimers();
    });

    const twoPlayerVsAi = MatchSetup(
      playerCount: 2,
      aiSeats: {1: AiDifficulty.easy},
    );
    const twoPlayerLocal = MatchSetup(playerCount: 2, aiSeats: {});

    void settleRoll() => timers.tickPeriodics(times: 6);

    Future<void> fireAiStep() async {
      timers.fireOneShots();
      await Future<void>.delayed(Duration.zero);
    }

    /// Plays the human's opening (roll 6, release, roll 1, move)
    /// so the turn passes to the AI and its pacing timer is pending.
    Future<void> reachAiTurn(OfflineGameController controller) async {
      controller.rollDice();
      settleRoll();
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      controller.rollDice();
      settleRoll();
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(controller.state.currentPlayerIndex, 1);
      expect(timers.oneShotDelays, hasLength(1));
    }

    test(
      'pause cancels the AI timer: the AI never acts while paused',
      () async {
        final controller = makeController(
          diceRoller: FixedDiceRoller(const [6, 1, 6, 3], cycle: true),
        );
        controller.startMatch(twoPlayerVsAi);
        await reachAiTurn(controller);
        final moveCount = controller.state.moveCount;

        controller.pause();
        expect(controller.isPaused, isTrue);
        expect(timers.oneShots.single.isActive, isFalse);

        // Firing every pending timer while paused changes nothing:
        // the cancelled callback never runs, and no new timer is
        // scheduled behind the pause.
        timers.fireOneShots();
        timers.tickPeriodics(times: 6);
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.currentPlayerIndex, 1);
        expect(controller.state.moveCount, moveCount);
        expect(controller.rolling, isFalse);
        expect(timers.oneShotDelays, hasLength(1));
        controller.dispose();
      },
    );

    test('resume re-schedules the AI exactly once, in the 700–1,199 ms '
        'band, and the AI then acts', () async {
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6, 1, 6, 3], cycle: true),
      );
      controller.startMatch(twoPlayerVsAi);
      await reachAiTurn(controller);

      controller.pause();
      controller.resume();
      expect(controller.isPaused, isFalse);
      expect(timers.oneShotDelays, hasLength(2));
      final delay = timers.oneShotDelays.last;
      expect(delay.inMilliseconds, greaterThanOrEqualTo(700));
      expect(delay.inMilliseconds, lessThanOrEqualTo(1199));

      // The AI rolls its 6, releases a token, rolls 3 and moves.
      await fireAiStep();
      expect(controller.rolling, isTrue);
      settleRoll();
      await fireAiStep();
      await fireAiStep();
      expect(controller.rolling, isTrue);
      settleRoll();
      await fireAiStep();
      expect(controller.state.currentPlayerIndex, 0);
      expect(controller.state.moveCount, 4);
      controller.dispose();
    });

    test('pause during a human turn preserves the exact state: turn, '
        'legal moves, displayed roll', () async {
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
      );
      controller.startMatch(twoPlayerLocal);
      controller.rollDice();
      settleRoll();
      final displayedRoll = controller.displayedRoll;
      final legalMoves = controller.legalMoves;
      final moveCount = controller.state.moveCount;
      final status = controller.status;
      expect(displayedRoll, 6);
      expect(legalMoves, hasLength(4));

      controller.pause();
      timers.fireOneShots();
      timers.tickPeriodics(times: 6);
      expect(controller.displayedRoll, displayedRoll);
      expect(controller.legalMoves, legalMoves);
      expect(controller.state.currentPlayerIndex, 0);
      expect(controller.state.moveCount, moveCount);
      expect(controller.status, status);

      // Resume on a human turn schedules nothing and changes nothing.
      controller.resume();
      expect(controller.displayedRoll, displayedRoll);
      expect(controller.legalMoves, legalMoves);
      expect(controller.state.moveCount, moveCount);
      expect(timers.oneShotDelays, isEmpty);
      controller.dispose();
    });

    test('pause mid-tumble freezes the tumble; resume settles it on '
        'the already-decided value', () {
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
      );
      controller.startMatch(twoPlayerLocal);
      controller.rollDice();
      timers.tickPeriodics(times: 3);
      expect(controller.rolling, isTrue);
      final face = controller.displayedRoll;

      controller.pause();
      timers.tickPeriodics(times: 6);
      expect(controller.rolling, isTrue);
      expect(controller.displayedRoll, face);
      expect(controller.legalMoves, isEmpty);

      controller.resume();
      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(controller.status, 'Player 1, choose a token to move.');
      // A second resume is a no-op: the roll settles exactly once.
      controller.resume();
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      controller.dispose();
    });

    test('roll and move input is ignored while paused', () async {
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
      );
      controller.startMatch(twoPlayerLocal);
      controller.pause();

      controller.rollDice();
      expect(controller.rolling, isFalse);
      expect(timers.periodicDelays, isEmpty);

      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(controller.state.moveCount, 0);

      controller.resume();
      expect(controller.state.phase, TurnPhase.awaitingRoll);
      controller.dispose();
    });

    test('pause and resume are idempotent; resume when not paused '
        'is a no-op', () {
      final controller = makeController();
      controller.startMatch(twoPlayerLocal);

      controller.resume();
      expect(controller.isPaused, isFalse);
      expect(timers.oneShotDelays, isEmpty);

      controller.pause();
      controller.pause();
      expect(controller.isPaused, isTrue);
      controller.resume();
      controller.resume();
      expect(controller.isPaused, isFalse);
      expect(timers.oneShotDelays, isEmpty);
      controller.dispose();
    });

    test('pause is a no-op on a finished match', () async {
      final controller = makeController();
      controller.restoreMatch(_nearWinState());
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 3));
      expect(controller.isFinished, isTrue);

      controller.pause();
      expect(controller.isPaused, isFalse);
      controller.dispose();
    });

    test('restart while paused starts a fresh, unpaused match', () async {
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6, 1, 6, 3], cycle: true),
      );
      controller.startMatch(twoPlayerVsAi);
      await reachAiTurn(controller);
      controller.pause();
      expect(controller.isPaused, isTrue);

      await controller.restart();
      expect(controller.isPaused, isFalse);
      expect(controller.state.moveCount, 0);
      expect(controller.state.currentPlayerIndex, 0);
      expect(controller.state.phase, TurnPhase.awaitingRoll);
      controller.dispose();
    });
  });

  // -- Widget tests ---------------------------------------------------------

  AppDependencies fakeDeps(InMemoryStore store) => AppDependencies(
    matches: InMemoryLocalMatchRepository(store),
    statistics: InMemoryLocalStatisticsRepository(store),
    settings: InMemorySettingsRepository(store),
    players: InMemoryLocalPlayerRepository(store),
    snapshots: InMemorySnapshotRepository(store),
  );

  StartupResult fakeStartup(
    AppDependencies deps, {
    SnapshotLoadOutcome outcome = const NoSnapshot(),
  }) => StartupResult(
    dependencies: deps,
    settings: Map<String, String>.of(kDefaultSettings),
    snapshotOutcome: outcome,
    databaseRecovered: false,
  );

  /// Pumps [home] under a [ProviderScope] with the fake startup
  /// (and an optional fixed dice roller) plus an
  /// [AppDependenciesScope], with the named routes the game screen
  /// navigates to (home, game, results). Returns the scope's
  /// [ProviderContainer], so tests can read the provider-owned
  /// controller. When [settle] is false only one frame is pumped:
  /// the AI-turn freeze test needs that, because settling would
  /// advance fake time and fire the AI pacing timer before the
  /// test pauses.
  Future<ProviderContainer> pumpRoutesApp(
    WidgetTester tester,
    AppDependencies deps,
    Widget home, {
    DiceRoller? diceRoller,
    SnapshotLoadOutcome outcome = const NoSnapshot(),
    bool settle = true,
  }) async {
    final startup = fakeStartup(deps, outcome: outcome);
    late final ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          startupResultProvider.overrideWithValue(startup),
          if (diceRoller != null)
            diceRollerProvider.overrideWithValue(diceRoller),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return AppDependenciesScope(
              startup: startup,
              child: MaterialApp(
                home: home,
                routes: {
                  AppRoutes.home: (_) => const HomeScreen(),
                  AppRoutes.game: (_) => const GameScreen(),
                  AppRoutes.results: (_) => const ResultsScreen(),
                },
              ),
            );
          },
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return container;
  }

  /// Pumps the real [DiceUpApp] (splash → Home) with the fake
  /// startup, for full-stack journeys.
  Future<void> pumpFullApp(
    WidgetTester tester,
    AppDependencies deps, {
    SnapshotLoadOutcome outcome = const NoSnapshot(),
    DiceRoller? diceRoller,
  }) async {
    await tester.pumpWidget(
      DiceUpApp(
        startup: fakeStartup(deps, outcome: outcome),
        testDiceRoller: diceRoller,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Drives Home → Mode → Setup → Game in the full app (the
  /// first-match stack: Home → Mode → Setup → Game).
  Future<void> driveToGame(WidgetTester tester) async {
    expect(find.text('Ready to play?'), findsOneWidget);
    await tester.tap(find.text('Play Offline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play vs AI'));
    await tester.pumpAndSettle();
    final start = find.text('Start match');
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsOneWidget);
  }

  Future<void> openPauseMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);
    expect(find.text('Main Menu'), findsOneWidget);
  }

  Future<void> tapPauseChoice(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// A match whose turn belongs to the AI (seat 1, Easy), about to
  /// roll — the freeze probe: pausing here must stop the AI
  /// pacing timer, and resuming must let the AI act.
  GameState aiTurnState() => GameState(
    players: [
      Player(
        index: 0,
        name: 'Player 1',
        colour: PlayerColour.red,
        type: PlayerType.human,
        tokens: List<Token>.generate(
          4,
          (i) => Token(
            playerIndex: 0,
            index: i,
            colour: PlayerColour.red,
            stepsTaken: 0,
          ),
        ),
      ),
      AiPlayer(
        index: 1,
        name: 'Robo',
        colour: PlayerColour.green,
        difficulty: AiDifficulty.easy,
        tokens: List<Token>.generate(
          4,
          (i) => Token(
            playerIndex: 1,
            index: i,
            colour: PlayerColour.green,
            stepsTaken: 0,
          ),
        ),
      ),
    ],
    currentPlayerIndex: 1,
    rulesetVersion: '1.0.0',
    startedAt: DateTime.utc(2026, 11, 21, 12, 0),
    phase: TurnPhase.awaitingRoll,
    lastRoll: 0,
  );

  group('pause menu', () {
    testWidgets('pause button opens the menu with Resume / Restart / '
        'Main Menu', (tester) async {
      final deps = fakeDeps(InMemoryStore());
      await pumpFullApp(tester, deps);
      await driveToGame(tester);

      await openPauseMenu(tester);
    });

    testWidgets('Resume returns to the playing match, state intact', (
      tester,
    ) async {
      final deps = fakeDeps(InMemoryStore());
      await pumpFullApp(tester, deps);
      await driveToGame(tester);

      await openPauseMenu(tester);
      await tapPauseChoice(tester, 'Resume');

      expect(find.text('Paused'), findsNothing);
      expect(find.byType(GameScreen), findsOneWidget);
      expect(
        find.textContaining('Player 1, roll the dice to start'),
        findsOneWidget,
      );
      expect(find.text('Roll dice'), findsOneWidget);
    });

    testWidgets('Restart from the menu asks confirmation, then '
        'restarts and records nothing', (tester) async {
      final deps = fakeDeps(InMemoryStore());
      await pumpFullApp(tester, deps);
      await driveToGame(tester);

      // Roll once so a snapshot exists to be discarded.
      final rollButton = find.text('Roll dice');
      await tester.ensureVisible(rollButton);
      await tester.pumpAndSettle();
      await tester.tap(rollButton);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await deps.snapshotSaver.flush;
      expect(await deps.snapshots.hasSnapshot(kCurrentMatchKey), isTrue);

      await openPauseMenu(tester);
      await tapPauseChoice(tester, 'Restart');
      expect(find.text('Restart match?'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();

      expect(find.byType(GameScreen), findsOneWidget);
      expect(
        find.textContaining('Player 1, roll the dice to start'),
        findsOneWidget,
      );
      expect(await deps.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      expect(await deps.matches.countMatches(), 0);
    });

    testWidgets('cancelling Restart resumes the match', (tester) async {
      final deps = fakeDeps(InMemoryStore());
      await pumpFullApp(tester, deps);
      await driveToGame(tester);

      await openPauseMenu(tester);
      await tapPauseChoice(tester, 'Restart');
      expect(find.text('Restart match?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Paused'), findsNothing);
      expect(find.byType(GameScreen), findsOneWidget);
      expect(
        find.textContaining('Player 1, roll the dice to start'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling Main Menu resumes the match', (tester) async {
      final deps = fakeDeps(InMemoryStore());
      await pumpFullApp(tester, deps);
      await driveToGame(tester);

      await openPauseMenu(tester);
      await tapPauseChoice(tester, 'Main Menu');
      expect(find.text('Leave the match?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Paused'), findsNothing);
      expect(find.byType(GameScreen), findsOneWidget);
      expect(
        find.textContaining('Player 1, roll the dice to start'),
        findsOneWidget,
      );
    });
  });

  /// Simulates the system back button: [WidgetTester.pageBack]
  /// needs a visible back button, and the game screen's AppBar
  /// leading is the pause button, so the platform pop route is
  /// driven directly.
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  group('system back', () {
    testWidgets('back while playing opens the pause menu, it does '
        'not pop', (tester) async {
      final deps = fakeDeps(InMemoryStore());
      await pumpFullApp(tester, deps);
      await driveToGame(tester);

      await systemBack(tester);

      expect(find.text('Paused'), findsOneWidget);
      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.byType(OfflineSetupScreen), findsNothing);
    });

    testWidgets('back while paused dismisses the menu and resumes', (
      tester,
    ) async {
      final deps = fakeDeps(InMemoryStore());
      await pumpFullApp(tester, deps);
      await driveToGame(tester);

      await systemBack(tester);
      expect(find.text('Paused'), findsOneWidget);

      // The dialog route is on top: back dismisses it, which
      // counts as Resume.
      await systemBack(tester);

      expect(find.text('Paused'), findsNothing);
      expect(find.byType(GameScreen), findsOneWidget);
      expect(
        find.textContaining('Player 1, roll the dice to start'),
        findsOneWidget,
      );
    });
  });

  group('freeze at the widget level', () {
    testWidgets('no AI move while paused for 5 s; the AI acts after '
        'Resume', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final container = await pumpRoutesApp(
        tester,
        deps,
        GameScreen(initialState: aiTurnState()),
        diceRoller: FixedDiceRoller(const [6, 3], cycle: true),
        settle: false,
      );
      final controller = container.read(offlineGameControllerProvider);
      // The AI timer is pending (restore schedules it); do not
      // pumpAndSettle here — it would advance time and fire it.
      // Pause immediately instead.
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(find.text('Paused'), findsOneWidget);
      expect(controller.isPaused, isTrue);

      await tester.pump(const Duration(seconds: 5));
      expect(controller.state.currentPlayerIndex, 1);
      expect(controller.state.moveCount, 0);
      expect(controller.state.phase, TurnPhase.awaitingRoll);
      expect(controller.rolling, isFalse);

      await tapPauseChoice(tester, 'Resume');
      // Drain the AI turn with explicit time advances: the AI
      // rolls 6, releases, rolls 3 and moves (one timer step per
      // pump). `pumpAndSettle` alone does not advance the fake
      // clock far enough to fire the pacing timers.
      for (var i = 0; i < 6 && controller.state.currentPlayerIndex == 1; i++) {
        await tester.pump(const Duration(seconds: 2));
      }
      await tester.pumpAndSettle();

      // The AI rolled its 6, released a token, rolled 3 and moved.
      expect(controller.state.currentPlayerIndex, 0);
      expect(controller.state.moveCount, 2);
    });

    testWidgets('pause preserves the displayed roll and legal moves '
        'on a human turn', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final container = await pumpRoutesApp(
        tester,
        deps,
        const GameScreen(initialSetup: GameSetup(playerCount: 2, aiSeats: {})),
        diceRoller: FixedDiceRoller(const [6], cycle: true),
      );
      final controller = container.read(offlineGameControllerProvider);
      final rollButton = find.text('Roll dice');
      await tester.ensureVisible(rollButton);
      await tester.pumpAndSettle();
      await tester.tap(rollButton);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));

      await openPauseMenu(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(controller.state.currentPlayerIndex, 0);

      await tapPauseChoice(tester, 'Resume');
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(
        find.textContaining('Player 1, choose a token to move'),
        findsOneWidget,
      );
    });
  });

  group('exit flows land on Home', () {
    testWidgets('Main Menu from a first match lands on Home, never '
        'on setup', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await pumpFullApp(tester, deps);
      await driveToGame(tester);

      await openPauseMenu(tester);
      await tapPauseChoice(tester, 'Main Menu');
      expect(find.text('Leave the match?'), findsOneWidget);
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(GameScreen), findsNothing);
      expect(find.byType(OfflineSetupScreen), findsNothing);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
      expect(await deps.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      expect(await deps.matches.countMatches(), 0);
    });

    testWidgets('Main Menu from a Play Again match lands on Home '
        'exactly once', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final container = await pumpRoutesApp(
        tester,
        deps,
        const HomeScreen(),
        diceRoller: FixedDiceRoller(const [6, 5, 4, 3, 2, 1], cycle: true),
      );
      // Home → Game (resumed near-win) → Results → Play Again.
      final homeContext = tester.element(find.byType(HomeScreen));
      Navigator.of(homeContext)
          .pushNamed(AppRoutes.game, arguments: _nearWinState());
      await tester.pumpAndSettle();
      await _tapWinningToken(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ResultsScreen), findsOneWidget);
      final playAgain = find.text('Play Again');
      await tester.ensureVisible(playAgain);
      await tester.pumpAndSettle();
      await tester.tap(playAgain);
      await tester.pumpAndSettle();
      expect(find.byType(GameScreen), findsOneWidget);
      expect(
        container.read(offlineGameControllerProvider).currentSetup,
        isNotNull,
      );

      await openPauseMenu(tester);
      await tapPauseChoice(tester, 'Main Menu');
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(GameScreen), findsNothing);
      expect(find.byType(OfflineSetupScreen), findsNothing);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
      expect(await deps.matches.countMatches(), 1);
    });

    testWidgets('exiting a resumed match never re-offers its deleted '
        'snapshot', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final state = stateWith(
        tokenSteps: const [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        current: 0,
        lastRoll: 0,
        phase: TurnPhase.awaitingRoll,
      );
      deps.snapshotSaver.save(state);
      await deps.snapshotSaver.flush;
      final outcome = ValidSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: jsonEncode(state.toJson()),
          savedAt: DateTime.now(),
        ),
      );
      await pumpFullApp(tester, deps, outcome: outcome);

      // Home offers the saved match: resume it.
      expect(find.text('Resume your match?'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(find.byType(GameScreen), findsOneWidget);

      // Exit from the pause menu: the snapshot is deleted, and the
      // fresh Home must not re-offer it (M2.6 re-check).
      await openPauseMenu(tester);
      await tapPauseChoice(tester, 'Main Menu');
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Ready to play?'), findsOneWidget);
      expect(find.text('Resume your match?'), findsNothing);
      expect(await deps.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
    });
  });
}

/// The fixed clock for the controller under test: `stateWith` stamps
/// `startedAt` at 2026-11-21 12:00 UTC, so a completion recorded at
/// this time has a duration of exactly 90 seconds.
DateTime _fixedNow() => DateTime.utc(2026, 11, 21, 12, 1, 30);

/// A match one move from a win: Player 1 has three tokens home and
/// the fourth one step away, with a 1 outstanding.
GameState _nearWinState() => stateWith(
  tokenSteps: const [
    [56, 56, 56, 55],
    [0, 0, 0, 0],
  ],
  current: 0,
  lastRoll: 1,
  phase: TurnPhase.awaitingMove,
);

/// Taps the winning token (seat 0, token 3, one step from home) on
/// the board, as `test/app_lifecycle_test.dart` does: the centre is
/// computed from the board geometry, never a magic offset.
Future<void> _tapWinningToken(WidgetTester tester) async {
  final state = _nearWinState();
  final board = find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
  );
  await tester.ensureVisible(board);
  await tester.pumpAndSettle();
  final origin = tester.getTopLeft(board);
  final tokens = [
    for (final player in state.players)
      for (final token in player.tokens)
        BoardToken(
          id: '${token.playerIndex}:${token.index}',
          seatIndex: token.playerIndex,
          stepsTaken: token.stepsTaken,
        ),
  ];
  final centre = boardTokenCenter(
    const BoardToken(id: '0:3', seatIndex: 0, stepsTaken: 55),
    // The rendered board size, not an assumed 480 dp: the game
    // screen's board is height-aware (Stage 2 redesign, F8), so
    // at the default 800x600 viewport it renders smaller than
    // 480 dp and a 480-based centre would miss the token.
    tester.getSize(board),
    tokens,
  );
  await tester.tapAt(origin + centre);
  await tester.pump();
}

/// A [Timer] the test drives by hand: one-shot callbacks fire via
/// [fire], periodic callbacks via [tickOnce].
class _ManualTimer implements Timer {
  _ManualTimer.oneShot(this._callback) : _periodicCallback = null;

  _ManualTimer.periodic(this._periodicCallback) : _callback = null;

  final void Function()? _callback;
  final void Function(Timer)? _periodicCallback;
  bool _cancelled = false;
  bool _fired = false;
  int _ticks = 0;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => _ticks;

  bool get isPending => !_cancelled && !_fired;

  void fire() {
    if (_cancelled || _fired) return;
    _fired = true;
    _callback?.call();
  }

  void tickOnce() {
    if (_cancelled) return;
    _ticks++;
    _periodicCallback?.call(this);
  }
}

/// Manual time for the controller: records every scheduled delay and
/// lets the test fire timers exactly when it chooses.
class _ManualTimers {
  final List<Duration> oneShotDelays = [];
  final List<Duration> periodicDelays = [];
  final List<_ManualTimer> oneShots = [];
  final List<_ManualTimer> periodics = [];

  Timer oneShot(Duration duration, void Function() callback) {
    oneShotDelays.add(duration);
    final timer = _ManualTimer.oneShot(callback);
    oneShots.add(timer);
    return timer;
  }

  Timer periodic(Duration duration, void Function(Timer) callback) {
    periodicDelays.add(duration);
    final timer = _ManualTimer.periodic(callback);
    periodics.add(timer);
    return timer;
  }

  /// Fires pending one-shot timers until none remain (a callback may
  /// schedule the next one). Capped so a scheduling loop fails the
  /// test instead of hanging it.
  void fireOneShots() {
    var guard = 0;
    while (oneShots.any((t) => t.isPending)) {
      assert(++guard <= 100, 'one-shot timers keep rescheduling');
      oneShots.firstWhere((t) => t.isPending).fire();
    }
  }

  /// Advances every live periodic timer by [times] ticks.
  void tickPeriodics({int times = 1}) {
    for (var i = 0; i < times; i++) {
      for (final timer in List.of(periodics)) {
        timer.tickOnce();
      }
    }
  }
}
