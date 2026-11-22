import 'dart:convert';

import 'package:diceup/core/design_system/diceup_components.dart';
import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/local/app_startup.dart';
import 'package:diceup/data/local/snapshot_recovery.dart';
import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/ruleset_config.dart';
import 'package:diceup/domain/engine/token.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
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

import 'repositories/fakes/fakes.dart';

/// M2.5 results screen (FR-26; D-02, D-30): the dedicated screen,
/// its match info, Play Again with the exact settings, Main Menu
/// landing on Home exactly once, and the end-to-end navigation
/// journeys. The completion tests in `test/app_lifecycle_test.dart`
/// cover the record itself (exactly-once, failure notice); these
/// tests cover the presentation and navigation around it.
void main() {
  // -- Shared helpers -----------------------------------------------------

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
  /// navigates to (results, game, home). Returns the scope's
  /// [ProviderContainer], captured via a [Builder] probe, so tests
  /// can read the provider-owned controller (the current setup of
  /// the match Play Again restarts from).
  Future<ProviderContainer> pumpRoutesApp(
    WidgetTester tester,
    AppDependencies deps,
    Widget home, {
    DiceRoller? diceRoller,
  }) async {
    final startup = fakeStartup(deps);
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
                  AppRoutes.results: (_) => const ResultsScreen(),
                  AppRoutes.game: (_) => const GameScreen(),
                  AppRoutes.home: (_) => const HomeScreen(),
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// A finished match's data, as the results screen receives it.
  MatchResult sampleResult({bool completionFailed = false}) => MatchResult(
    winnerSeat: 0,
    winnerName: 'Adeel',
    winnerColour: PlayerColour.red,
    players: const [
      MatchResultPlayer(
        seat: 0,
        name: 'Adeel',
        colour: PlayerColour.red,
        isAi: false,
      ),
      MatchResultPlayer(
        seat: 1,
        name: 'Robo',
        colour: PlayerColour.green,
        isAi: true,
      ),
    ],
    duration: const Duration(minutes: 1, seconds: 35),
    moveCount: 48,
    finishedAt: DateTime(2026, 11, 22, 10, 30),
    setup: const GameSetup(
      playerCount: 2,
      aiSeats: {1: AiDifficulty.hard},
      names: ['Adeel', 'Robo'],
      colours: [PlayerColour.red, PlayerColour.green],
      ruleset: RulesetConfig(releaseOnOne: true),
    ),
    completionFailed: completionFailed,
  );

  List<Token> tokensAt(int player, List<int> steps) => List<Token>.generate(
    4,
    (i) => Token(
      playerIndex: player,
      index: i,
      colour: PlayerColour.values[player],
      stepsTaken: steps[i],
    ),
  );

  /// A match one move from a win, with custom settings: human
  /// 'Adeel' (red) vs hard-AI 'Robo' (green), release-on-1 ruleset,
  /// started 95 seconds ago so the duration reads 01:35.
  GameState nearWinState() => GameState(
    players: [
      Player(
        index: 0,
        name: 'Adeel',
        colour: PlayerColour.red,
        type: PlayerType.human,
        tokens: tokensAt(0, [56, 56, 56, 55]),
      ),
      AiPlayer(
        index: 1,
        name: 'Robo',
        colour: PlayerColour.green,
        difficulty: AiDifficulty.hard,
        tokens: tokensAt(1, [0, 0, 0, 0]),
      ),
    ],
    currentPlayerIndex: 0,
    rulesetVersion: '1.0.0',
    ruleset: const RulesetConfig(releaseOnOne: true),
    startedAt: DateTime.now().subtract(const Duration(minutes: 1, seconds: 35)),
    phase: TurnPhase.awaitingMove,
    lastRoll: 1,
    moveCount: 47,
  );

  /// The same match, already finished (all four of Adeel's tokens
  /// home), for the resumed-finished-match path.
  GameState finishedState() => GameState(
    players: [
      Player(
        index: 0,
        name: 'Adeel',
        colour: PlayerColour.red,
        type: PlayerType.human,
        tokens: tokensAt(0, [56, 56, 56, 56]),
      ),
      AiPlayer(
        index: 1,
        name: 'Robo',
        colour: PlayerColour.green,
        difficulty: AiDifficulty.hard,
        tokens: tokensAt(1, [0, 0, 0, 0]),
      ),
    ],
    currentPlayerIndex: 0,
    rulesetVersion: '1.0.0',
    ruleset: const RulesetConfig(releaseOnOne: true),
    startedAt: DateTime.now().subtract(const Duration(minutes: 1, seconds: 35)),
    phase: TurnPhase.finished,
    winnerIndex: 0,
    moveCount: 48,
  );

  /// Taps the winning token (Adeel's fourth, one step from home) —
  /// the board-tap pattern from `test/app_lifecycle_test.dart`.
  Future<void> tapWinningToken(WidgetTester tester) async {
    final board = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
    );
    await tester.ensureVisible(board);
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(board);
    final tokens = [
      for (final player in nearWinState().players)
        for (final token in player.tokens)
          BoardToken(
            id: '${token.playerIndex}:${token.index}',
            seatIndex: token.playerIndex,
            stepsTaken: token.stepsTaken,
          ),
    ];
    final centre = boardTokenCenter(
      const BoardToken(id: '0:3', seatIndex: 0, stepsTaken: 55),
      const Size(480, 480),
      tokens,
    );
    await tester.tapAt(origin + centre);
    await tester.pump();
  }

  /// The results screen scrolls (winner + info + participants +
  /// buttons can exceed the 800x600 test viewport): bring the
  /// button into view before tapping it, as a real user would
  /// scroll to it.
  Future<void> tapResultsButton(WidgetTester tester, String label) async {
    final button = find.text(label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// Pushes the game route with a restored [state] from Home, the
  /// way Home's resume flow does — so the stack is Home → Game,
  /// exactly as in production, and Main Menu pops back to that Home.
  Future<void> pushGameFromHome(WidgetTester tester, GameState state) async {
    final homeContext = tester.element(find.byType(HomeScreen));
    Navigator.of(homeContext).pushNamed(AppRoutes.game, arguments: state);
    await tester.pumpAndSettle();
  }

  /// The `mm:ss` duration text on the results screen — any
  /// non-zero value, so a test never pins the exact wall-clock
  /// seconds of its own run.
  Finder durationText() => find.byWidgetPredicate(
    (widget) =>
        widget is Text &&
        widget.data != null &&
        RegExp(r'^[0-9]{2}:[0-5][0-9]$').hasMatch(widget.data!) &&
        widget.data != '00:00',
  );

  // -- The screen itself --------------------------------------------------

  group('results screen', () {
    testWidgets('shows the winner with avatar, mode, players, '
        'duration, moves and date', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await pumpRoutesApp(tester, deps, ResultsScreen(result: sampleResult()));

      expect(find.text('Adeel wins!'), findsOneWidget);
      // Winner hero + one avatar per participant.
      expect(find.byType(PlayerAvatar), findsNWidgets(3));
      final hero = tester.widget<PlayerAvatar>(find.byType(PlayerAvatar).first);
      expect(hero.name, 'Adeel');
      expect(hero.seatIndex, 0);
      expect(hero.colour, PlayerColour.red);
      expect(find.text('vs AI'), findsOneWidget);
      expect(find.text('2 players'), findsOneWidget);
      expect(find.text('01:35'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
      expect(find.text('Finished'), findsOneWidget);
      expect(find.textContaining('22 Nov 2026'), findsOneWidget);
      expect(find.text('Robo (AI)'), findsOneWidget);
      expect(find.text('Winner'), findsOneWidget);
      expect(find.text('Play Again'), findsOneWidget);
      expect(find.text('Main Menu'), findsOneWidget);
      expect(
        find.text(kMatchRecordFailedMessage),
        findsNothing,
        reason: 'a recorded match carries no failure notice',
      );
    });

    testWidgets('premium results (Q5/Q8): winner\'s mark, Home n/4 '
        'counts, one-shot confetti on entry', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final base = sampleResult();
      final result = MatchResult(
        winnerSeat: base.winnerSeat,
        winnerName: base.winnerName,
        winnerColour: base.winnerColour,
        players: const [
          MatchResultPlayer(
            seat: 0,
            name: 'Adeel',
            colour: PlayerColour.red,
            isAi: false,
            tokensHome: 4,
          ),
          MatchResultPlayer(
            seat: 1,
            name: 'Robo',
            colour: PlayerColour.green,
            isAi: true,
            tokensHome: 1,
          ),
        ],
        duration: base.duration,
        moveCount: base.moveCount,
        finishedAt: base.finishedAt,
        setup: base.setup,
      );
      await pumpRoutesApp(tester, deps, ResultsScreen(result: result));

      // Winner's mark: the enlarged per-seat shape marker in a teal
      // ring around the winner's avatar (Q5 — no crown).
      expect(find.byKey(const ValueKey('winner-shape-marker')), findsOneWidget);
      // Each player's tokens-home count next to their name (Q8).
      expect(find.text('Home 4/4'), findsOneWidget);
      expect(find.text('Home 1/4'), findsOneWidget);
      // One-shot hand-drawn confetti fires once on entry: the
      // overlay stays mounted after its finite burst, painting
      // nothing once the pieces have fallen.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter != null &&
              widget.painter.runtimeType.toString() == '_ConfettiPainter',
        ),
        findsOneWidget,
      );
    });

    testWidgets('iOS Reduce Motion skips the entrance and confetti', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await pumpRoutesApp(tester, deps, ResultsScreen(result: sampleResult()));

      final headlineFade = find
          .ancestor(
            of: find.text('Adeel wins!'),
            matching: find.byType(Opacity),
          )
          .first;
      expect(tester.widget<Opacity>(headlineFade).opacity, 1.0);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter != null &&
              widget.painter.runtimeType.toString() == '_ConfettiPainter',
        ),
        findsNothing,
      );
    });

    testWidgets('record failure shows the notice, success does not', (
      tester,
    ) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await pumpRoutesApp(
        tester,
        deps,
        ResultsScreen(result: sampleResult(completionFailed: true)),
      );

      expect(find.text('Adeel wins!'), findsOneWidget);
      expect(find.text(kMatchRecordFailedMessage), findsOneWidget);
    });

    testWidgets('a route opened without a result shows an honest '
        'empty state, never an invented result', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await pumpRoutesApp(tester, deps, const ResultsScreen());

      expect(find.text('No match result to show.'), findsOneWidget);
      expect(find.text('Adeel wins!'), findsNothing);

      await tapResultsButton(tester, 'Main Menu');
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('Main Menu lands on Home exactly once, never on '
        'setup', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await pumpRoutesApp(tester, deps, ResultsScreen(result: sampleResult()));

      await tapResultsButton(tester, 'Main Menu');

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ResultsScreen), findsNothing);
      expect(find.byType(OfflineSetupScreen), findsNothing);
      // Nothing underneath to pop back to: Main Menu left exactly
      // one route, Home — no stale screen, no double-pop target.
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
    });

    testWidgets('Play Again restarts with the exact setup, '
        'including the ruleset', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final container = await pumpRoutesApp(
        tester,
        deps,
        ResultsScreen(result: sampleResult()),
        diceRoller: FixedDiceRoller(const [1], cycle: true),
      );

      await tapResultsButton(tester, 'Play Again');

      // A fresh match, same players.
      expect(find.byType(GameScreen), findsOneWidget);
      expect(
        find.textContaining('Adeel, roll the dice to start'),
        findsOneWidget,
      );
      final setup = container.read(offlineGameControllerProvider).currentSetup!;
      expect(setup.playerCount, 2);
      expect(setup.aiSeats, {1: AiDifficulty.hard});
      expect(setup.names, ['Adeel', 'Robo']);
      expect(setup.colours, [PlayerColour.red, PlayerColour.green]);
      expect(setup.ruleset.releaseOnOne, isTrue);

      // Behaviour, not just fields: a roll of 1 releases a token
      // under the reused release-on-1 ruleset. The Roll button sits
      // below the fold in the test viewport — scroll to it first.
      final rollButton = find.text('Roll dice');
      await tester.ensureVisible(rollButton);
      await tester.tap(rollButton);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Adeel, choose a token to move'),
        findsOneWidget,
      );
    });
  });

  // -- Game to results journeys -------------------------------------------

  group('game to results journey', () {
    testWidgets('completing a match shows Results (not a dialog) '
        'and Play Again reuses the match settings', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final container = await pumpRoutesApp(tester, deps, const HomeScreen());
      await pushGameFromHome(tester, nearWinState());

      await tapWinningToken(tester);
      await tester.pumpAndSettle();

      expect(find.byType(ResultsScreen), findsOneWidget);
      expect(find.byType(GameScreen), findsNothing);
      expect(find.text('Adeel wins!'), findsOneWidget);
      expect(durationText(), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
      expect(await deps.matches.countMatches(), 1);

      await tapResultsButton(tester, 'Play Again');

      // A fresh match, same settings — and still one record.
      expect(find.byType(GameScreen), findsOneWidget);
      expect(
        find.textContaining('Adeel, roll the dice to start'),
        findsOneWidget,
      );
      expect(await deps.matches.countMatches(), 1);
      final setup = container.read(offlineGameControllerProvider).currentSetup!;
      expect(setup.playerCount, 2);
      expect(setup.aiSeats, {1: AiDifficulty.hard});
      expect(setup.names, ['Adeel', 'Robo']);
      expect(setup.colours, [PlayerColour.red, PlayerColour.green]);
      // The resumed match played under the stock ruleset, not the
      // state's embedded release-on-1: LudoGame.fromState uses the
      // default ruleset (recorded M3.2/M3.3 follow-up, NOT fixed
      // here). Play Again faithfully reuses the match's *effective*
      // setup — the loss happened at resume, not at Play Again.
      // A normal match keeps its custom ruleset (see the scripted
      // test below).
      expect(setup.ruleset.releaseOnOne, isFalse);
    });

    testWidgets('Main Menu from Results lands on Home exactly once', (
      tester,
    ) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await pumpRoutesApp(tester, deps, const HomeScreen());
      await pushGameFromHome(tester, nearWinState());

      await tapWinningToken(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ResultsScreen), findsOneWidget);

      await tapResultsButton(tester, 'Main Menu');

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ResultsScreen), findsNothing);
      expect(find.byType(OfflineSetupScreen), findsNothing);
      // Nothing underneath to pop back to: Main Menu left exactly
      // one route, Home — no stale screen, no double-pop target.
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
    });

    testWidgets('a resumed finished match shows Results without '
        'recording twice', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final state = finishedState();
      deps.snapshotSaver.save(state);
      await deps.snapshotSaver.flush;

      await pumpRoutesApp(tester, deps, const HomeScreen());
      await pushGameFromHome(tester, state);
      await tester.pumpAndSettle();

      expect(find.byType(ResultsScreen), findsOneWidget);
      expect(find.text('Adeel wins!'), findsOneWidget);
      expect(await deps.matches.countMatches(), 1);
      expect(await deps.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
    });
  });

  // -- Full-app journeys (real DiceUpApp stack) ---------------------------

  group('full-app journey', () {
    Future<void> pumpResumedApp(WidgetTester tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final state = nearWinState();
      // M2.6: Home re-checks snapshot existence before offering
      // resume, so the outcome must correspond to a real stored
      // row — a bare ValidSnapshot with no row is exactly the
      // stale offer the re-check refuses.
      deps.snapshotSaver.save(state);
      await deps.snapshotSaver.flush;
      final startup = fakeStartup(
        deps,
        outcome: ValidSnapshot(
          SavedSnapshot(
            matchKey: kCurrentMatchKey,
            snapshotJson: jsonEncode(state.toJson()),
            savedAt: DateTime.now(),
          ),
        ),
      );
      await tester.pumpWidget(DiceUpApp(startup: startup));
      await tester.pumpAndSettle();

      // Home offers the saved match: resume it.
      expect(find.text('Resume your match?'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(find.byType(GameScreen), findsOneWidget);

      await tapWinningToken(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ResultsScreen), findsOneWidget);
      expect(find.text('Adeel wins!'), findsOneWidget);
      expect(await deps.matches.countMatches(), 1);
    }

    testWidgets('Home → Resume → Game → Results → Play Again → '
        'Game', (tester) async {
      await pumpResumedApp(tester);

      await tapResultsButton(tester, 'Play Again');

      expect(find.byType(GameScreen), findsOneWidget);
      expect(
        find.textContaining('Adeel, roll the dice to start'),
        findsOneWidget,
      );
    });

    testWidgets('Home → Resume → Game → Results → Main Menu → '
        'Home', (tester) async {
      await pumpResumedApp(tester);

      await tapResultsButton(tester, 'Main Menu');

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Ready to play?'), findsOneWidget);
      expect(find.byType(ResultsScreen), findsNothing);
      expect(find.byType(OfflineSetupScreen), findsNothing);
      // Nothing underneath to pop back to: Main Menu left exactly
      // one route, Home — no stale screen, no double-pop target.
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
    });
  });

  // -- Scripted normal match (setup → game → results → play again) --------

  group('scripted normal match', () {
    testWidgets('a match started from setup completes and Play '
        'Again reuses the exact setup', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final startup = fakeStartup(deps);
      late final ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            startupResultProvider.overrideWithValue(startup),
            diceRollerProvider.overrideWithValue(
              FixedDiceRoller(const [6, 5, 4, 3, 2, 1], cycle: true),
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return AppDependenciesScope(
                startup: startup,
                child: MaterialApp(
                  home: const OfflineSetupScreen(),
                  onGenerateRoute: (settings) {
                    if (settings.name == AppRoutes.game) {
                      return MaterialPageRoute<void>(
                        builder: (_) => const GameScreen(),
                        settings: settings,
                      );
                    }
                    if (settings.name == AppRoutes.results) {
                      return MaterialPageRoute<void>(
                        builder: (_) => const ResultsScreen(),
                        settings: settings,
                      );
                    }
                    if (settings.name == AppRoutes.home) {
                      return MaterialPageRoute<void>(
                        builder: (_) => const HomeScreen(),
                        settings: settings,
                      );
                    }
                    return null;
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Setup: name seat 0 'Adeel', seat 1 AI on Hard, release-on-1.
      await tester.enterText(
        find.byKey(const ValueKey('seat-0-name')),
        'Adeel',
      );
      await tester.pump();
      final difficultyField = find
          .byType(DropdownButtonFormField<AiDifficulty>)
          .first;
      await tester.ensureVisible(difficultyField);
      await tester.pumpAndSettle();
      await tester.tap(difficultyField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hard'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      final releaseTile = find.byWidgetPredicate(
        (widget) =>
            widget is SwitchListTile &&
            (widget.title as Text?)?.data == 'Release on 1',
      );
      await tester.ensureVisible(releaseTile);
      await tester.pumpAndSettle();
      await tester.tap(releaseTile);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start match'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.textContaining('Adeel, roll the dice to start'),
        findsOneWidget,
      );

      // Drive the match to completion through the UI: human rolls
      // and moves the first legal token; the AI plays itself on its
      // timers. The cycling dice include 1s so tokens can finish
      // exactly (all-6s would strand tokens at 51–55 under exact
      // finish and the match could never end).
      //
      // The loop exits when the match is finished — either the
      // provider still reports it, or the results screen is already
      // showing. The second exit matters (M3 premium): the game
      // screen navigates to results the moment the finished match's
      // record is decided, and the `autoDispose` provider is then
      // disposed (Riverpod schedules the disposal on the next
      // microtask after the screen unmounts). A fresh read after
      // that yields a controller with no game — `isFinished` false
      // and `state` throwing — so the loop must not read the
      // provider's state once results is showing. The per-cell step
      // sequences (up to ~600 ms) plus the capture return (~600 ms)
      // keep frames scheduled across the gap between a human move
      // and the AI timer firing, so `pumpAndSettle` no longer
      // returns in that gap and the AI's reply — including a
      // match-ending win — can complete inside the human branch's
      // `pumpAndSettle`, with navigation + disposal following
      // before the next loop read. The pre-M3 hop (≤250 ms) ended
      // before the AI timer fired, so the loop always observed the
      // win from the AI branch instead. The results screen is
      // itself proof the match finished: navigation only happens
      // for a finished match.
      var steps = 0;
      while (!container.read(offlineGameControllerProvider).isFinished &&
          find.byType(ResultsScreen).evaluate().isEmpty &&
          steps < 800) {
        steps++;
        await tester.pump();
        final controller = container.read(offlineGameControllerProvider);
        if (controller.isFinished) break;
        if (find.byType(ResultsScreen).evaluate().isNotEmpty) break;
        if (controller.rolling) {
          await tester.pump(const Duration(milliseconds: 600));
          continue;
        }
        final state = controller.state;
        if (state.currentPlayer.isAi) {
          await tester.pump(const Duration(milliseconds: 1300));
          continue;
        }
        if (state.phase == TurnPhase.awaitingRoll) {
          final rollButton = find.text('Roll dice');
          await tester.ensureVisible(rollButton);
          await tester.tap(rollButton);
          await tester.pump(const Duration(milliseconds: 600));
        } else if (state.phase == TurnPhase.awaitingMove) {
          final move = controller.legalMoves.first;
          final board = find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is LudoBoardPainter,
          );
          await tester.ensureVisible(board);
          await tester.pump();
          final origin = tester.getTopLeft(board);
          final token = state.currentPlayer.tokens[move.tokenIndex];
          final tokens = [
            for (final player in state.players)
              for (final t in player.tokens)
                BoardToken(
                  id: '${t.playerIndex}:${t.index}',
                  seatIndex: t.playerIndex,
                  stepsTaken: t.stepsTaken,
                ),
          ];
          final centre = boardTokenCenter(
            BoardToken(
              id: '${token.playerIndex}:${token.index}',
              seatIndex: token.playerIndex,
              stepsTaken: token.stepsTaken,
            ),
            const Size(480, 480),
            tokens,
          );
          await tester.tapAt(origin + centre);
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }
      // Completion: either the provider still reports the finished
      // match, or the results screen is showing (navigation only
      // happens for a finished match, and the provider may already
      // be disposed after that navigation — see the loop comment).
      final finished =
          container.read(offlineGameControllerProvider).isFinished ||
          find.byType(ResultsScreen).evaluate().isNotEmpty;
      expect(
        finished,
        isTrue,
        reason: 'scripted match did not finish in $steps steps',
      );
      await tester.pumpAndSettle();

      // Results: the winner (whoever won), a real duration, one record.
      expect(find.byType(ResultsScreen), findsOneWidget);
      expect(find.textContaining('wins!'), findsOneWidget);
      expect(durationText(), findsOneWidget);
      expect(await deps.matches.countMatches(), 1);

      await tapResultsButton(tester, 'Play Again');

      // A fresh match with the exact setup the match started with —
      // names, colours, difficulty AND the custom ruleset.
      expect(find.byType(GameScreen), findsOneWidget);
      expect(
        find.textContaining('Adeel, roll the dice to start'),
        findsOneWidget,
      );
      expect(await deps.matches.countMatches(), 1);
      final setup = container.read(offlineGameControllerProvider).currentSetup!;
      expect(setup.playerCount, 2);
      expect(setup.aiSeats, {1: AiDifficulty.hard});
      // Seat 1's name field was left empty at setup, so it reads
      // as "Player 2" (D-28) — the name the match actually played with.
      expect(setup.names, ['Adeel', 'Player 2']);
      expect(setup.colours, [PlayerColour.red, PlayerColour.green]);
      expect(setup.ruleset.releaseOnOne, isTrue);
    });
  });
}
