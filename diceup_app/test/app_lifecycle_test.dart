import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/local/app_startup.dart';
import 'package:diceup/data/local/database_recovery.dart';
import 'package:diceup/data/local/snapshot_recovery.dart';
import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:diceup/main.dart';
import 'package:diceup/presentation/app_dependencies_scope.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/game_screen.dart';
import 'package:diceup/presentation/screens/history_screen.dart';
import 'package:diceup/presentation/screens/home_screen.dart';
import 'package:diceup/presentation/screens/results_screen.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine/test_helpers.dart';
import 'repositories/fakes/fakes.dart';

/// M1.6 lifecycle integration tests: real startup, resume/discard,
/// snapshot persistence, clean exit, exactly-once completion and
/// the failure paths. Widget tests use the in-memory fakes;
/// startup tests use real ffi SQLite on temp files.
void main() {
  sqfliteFfiInit();

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

  /// M3.3: also inside a [ProviderScope] with the fake startup,
  /// so a [GameScreen] reads the provider graph (fixed dice via
  /// [diceRoller], fake feedback, vibration flag — the only seams).
  /// M2.5: the named routes the game screen navigates to are
  /// registered here (results, game, home) — `home:` alone has no
  /// route table, and the game screen's completion navigation is a
  /// `pushNamedAndRemoveUntil`. The splash route is deliberately
  /// absent: `home:` already occupies `/`.
  Widget scopedApp(
    AppDependencies deps,
    Widget home, {
    SnapshotLoadOutcome outcome = const NoSnapshot(),
    DiceRoller? diceRoller,
  }) {
    final startup = fakeStartup(deps, outcome: outcome);
    return ProviderScope(
      overrides: [
        startupResultProvider.overrideWithValue(startup),
        if (diceRoller != null)
          diceRollerProvider.overrideWithValue(diceRoller),
      ],
      child: AppDependenciesScope(
        startup: startup,
        child: MaterialApp(
          home: home,
          routes: {
            AppRoutes.results: (_) => const ResultsScreen(),
            AppRoutes.game: (_) => const GameScreen(),
            AppRoutes.home: (_) => const HomeScreen(),
          },
        ),
      ),
    );
  }

  Future<Map<String, Object?>> savedSnapshotJson(AppDependencies deps) async {
    final saved = await deps.snapshots.loadSnapshot(kCurrentMatchKey);
    expect(saved, isNotNull, reason: 'expected a saved snapshot');
    return jsonDecode(saved!.snapshotJson) as Map<String, Object?>;
  }

  LocalMatch sampleMatch({
    required DateTime playedAt,
    required String winnerName,
    required int winnerIndex,
  }) => LocalMatch(
    playedAt: playedAt,
    mode: LocalMatchMode.vsAi,
    playerCount: 2,
    players: [
      LocalMatchPlayer(name: 'Player 1', colour: PlayerColour.red, isAi: false),
      LocalMatchPlayer(
        name: 'Player 2',
        colour: PlayerColour.green,
        isAi: true,
        difficulty: AiDifficulty.easy,
      ),
    ],
    winnerIndex: winnerIndex,
    winnerName: winnerName,
    durationSeconds: 95,
    rulesetVersion: '1.0.0',
    createdAt: playedAt,
  );

  /// A temp directory, deleted synchronously after the test (sync
  /// delete: the tearDown runs inside the widget-test zone, where
  /// real async work needs `runAsync`).
  Future<Directory> tempDir() async {
    final dir = await Directory.systemTemp.createTemp('diceup_m16_');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return dir;
  }

  /// Runs real ffi work inside the widget-test zone. Real async
  /// work (sqflite_ffi) done outside [WidgetTester.runAsync] leaves
  /// the test binding unable to pump afterwards (verified by probe:
  /// a `pumpWidget` after an out-of-`runAsync` ffi open stalls the
  /// isolate); inside `runAsync` it works. The M1.4/M1.5 tests use
  /// plain `test()` for ffi for the same reason.
  Future<T> ffi<T>(WidgetTester tester, Future<T> Function() work) async {
    final result = await tester.runAsync(work);
    return result as T;
  }

  // -- Startup ------------------------------------------------------------

  group('startup', () {
    testWidgets('first launch (fresh DB, no snapshot) reaches Home, '
        'no dialogs', (tester) async {
      final startup = await ffi(
        tester,
        () => initializeApp(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        ),
      );
      await tester.pumpWidget(DiceUpApp(startup: startup));
      await tester.pumpAndSettle();

      expect(find.text('Ready to play?'), findsOneWidget);
      expect(find.text('Resume your match?'), findsNothing);
      await ffi(tester, () async {
        await startup.dependencies?.database?.close();
      });
    });

    testWidgets('startup with a valid snapshot offers resume with the '
        'exact copy, and Resume restores the match', (tester) async {
      final (boot, outcome) = await ffi(tester, () async {
        final boot = await initializeApp(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        final deps = boot.dependencies!;
        final game = LudoGame.newMatch(
          seats: const [
            SeatConfig(name: 'Player 1', colour: PlayerColour.red),
            SeatConfig(name: 'Player 2', colour: PlayerColour.green),
          ],
        );
        await deps.snapshots.saveSnapshot(
          SavedSnapshot(
            matchKey: kCurrentMatchKey,
            snapshotJson: jsonEncode(game.snapshot()),
            savedAt: DateTime.now(),
          ),
        );
        final outcome = await loadSnapshotForResume(deps.snapshots);
        return (boot, outcome);
      });
      expect(outcome, isA<ValidSnapshot>());

      await tester.pumpWidget(
        DiceUpApp(
          startup: StartupResult(
            dependencies: boot.dependencies,
            settings: boot.settings,
            snapshotOutcome: outcome,
            databaseRecovered: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // M2.6: Home re-checks snapshot existence (a real ffi read)
      // before offering resume, and that read only completes on
      // real async time — drain it, then settle, before expecting
      // the dialog (same runAsync rule as all other ffi work here).
      await ffi(tester, () async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(find.text('Resume your match?'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(find.textContaining('roll the dice to start'), findsOneWidget);
      await ffi(tester, () async {
        await boot.dependencies?.database?.close();
      });
    });

    testWidgets('Discard deletes the snapshot and starts no match', (
      tester,
    ) async {
      final (boot, outcome) = await ffi(tester, () async {
        final boot = await initializeApp(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
        );
        final deps = boot.dependencies!;
        final game = LudoGame.newMatch(
          seats: const [
            SeatConfig(name: 'Player 1', colour: PlayerColour.red),
            SeatConfig(name: 'Player 2', colour: PlayerColour.green),
          ],
        );
        await deps.snapshots.saveSnapshot(
          SavedSnapshot(
            matchKey: kCurrentMatchKey,
            snapshotJson: jsonEncode(game.snapshot()),
            savedAt: DateTime.now(),
          ),
        );
        final outcome = await loadSnapshotForResume(deps.snapshots);
        return (boot, outcome);
      });

      await tester.pumpWidget(
        DiceUpApp(
          startup: StartupResult(
            dependencies: boot.dependencies,
            settings: boot.settings,
            snapshotOutcome: outcome,
            databaseRecovered: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // M2.6: Home re-checks snapshot existence (a real ffi read)
      // before offering resume — drain it on real async time, then
      // settle, before expecting the dialog (see above).
      await ffi(tester, () async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Ready to play?'), findsOneWidget);
      // The delete is real async ffi work triggered by the tap, so
      // it can still be in flight after the pumps settle: poll for
      // it (bounded) instead of racing the read against the delete.
      final gone = await ffi(tester, () async {
        for (var i = 0; i < 50; i++) {
          if (!await boot.dependencies!.snapshots.hasSnapshot(
            kCurrentMatchKey,
          )) {
            return true;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return false;
      });
      expect(gone, isTrue);
      await ffi(tester, () async {
        await boot.dependencies?.database?.close();
      });
    });

    testWidgets('startup after recovery shows the recovery message once', (
      tester,
    ) async {
      final dir = await ffi(tester, () => tempDir());
      final path = '${dir.path}/diceup.db';
      final startup = await ffi(tester, () async {
        await File(path).writeAsBytes([0, 1, 2, 3, 4, 5]);
        return initializeApp(factory: databaseFactoryFfi, path: path);
      });
      expect(startup.databaseRecovered, isTrue);

      await tester.pumpWidget(DiceUpApp(startup: startup));
      await tester.pumpAndSettle();

      expect(find.text(kDatabaseRecoveryMessage), findsOneWidget);
      expect(find.text('Ready to play?'), findsOneWidget);
      await ffi(tester, () async {
        await startup.dependencies?.database?.close();
      });
    });

    testWidgets('startup with a corrupt snapshot discards it and shows the '
        'notice once', (tester) async {
      final dir = await ffi(tester, () => tempDir());
      final path = '${dir.path}/diceup.db';
      final second = await ffi(tester, () async {
        final first = await initializeApp(
          factory: databaseFactoryFfi,
          path: path,
        );
        await first.dependencies!.snapshots.saveSnapshot(
          SavedSnapshot(
            matchKey: kCurrentMatchKey,
            snapshotJson: 'this is not JSON',
            savedAt: DateTime.now(),
          ),
        );
        final second = await initializeApp(
          factory: databaseFactoryFfi,
          path: path,
        );
        // Do NOT close `first` here: both handles share sqflite's
        // single instance for this path, so closing it would close
        // the database `second` uses. Only `second` is closed, at
        // the end of the test.
        return second;
      });
      expect(second.snapshotOutcome, isA<CorruptSnapshotDiscarded>());
      final stillThere = await ffi(
        tester,
        () => second.dependencies!.snapshots.hasSnapshot(kCurrentMatchKey),
      );
      expect(stillThere, isFalse);

      await tester.pumpWidget(DiceUpApp(startup: second));
      await tester.pumpAndSettle();

      expect(find.text(kCorruptSnapshotMessage), findsOneWidget);
      expect(find.text('Ready to play?'), findsOneWidget);
      await ffi(tester, () async {
        await second.dependencies?.database?.close();
      });
    });

    testWidgets('startup with a throwing factory still reaches Home '
        'with an error notice', (tester) async {
      // No ffi call happens on this path: the throwing factory
      // throws before delegating, and the in-memory path skips the
      // delete step — so the DiceUpApp fallback initializer can run
      // it directly.
      await tester.pumpWidget(
        DiceUpApp(
          initializer: () => initializeApp(
            factory: _ThrowingDatabaseFactory(),
            path: inMemoryDatabasePath,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ready to play?'), findsOneWidget);
      expect(find.text(kStartupDatabaseErrorMessage), findsOneWidget);
    });

    test('existing-DB startup loads settings', () async {
      final dir = await tempDir();
      final path = '${dir.path}/diceup.db';
      final first = await initializeApp(
        factory: databaseFactoryFfi,
        path: path,
      );
      await first.dependencies!.settings.setSetting('sound_volume', '42');
      await first.dependencies!.database!.close();

      final second = await initializeApp(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(() async => second.dependencies?.database?.close());
      expect(second.settings['sound_volume'], '42');
      expect(second.settings['sound_enabled'], '1');
    });

    test('recovery after restart: history + statistics persist', () async {
      final dir = await tempDir();
      final path = '${dir.path}/diceup.db';
      final first = await initializeApp(
        factory: databaseFactoryFfi,
        path: path,
      );
      await first.dependencies!.matches.recordMatch(
        sampleMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 0),
          winnerName: 'Player 1',
          winnerIndex: 0,
        ),
      );
      await first.dependencies!.database!.close();

      final second = await initializeApp(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(() async => second.dependencies?.database?.close());
      expect(await second.dependencies!.matches.countMatches(), 1);
      final stats = await second.dependencies!.statistics.getStatistics();
      expect(stats.matchesPlayed, 1);
      expect(stats.matchesWon, 1);
    });
  });

  // -- Resume (exact state) -----------------------------------------------

  group('resume', () {
    testWidgets('resume restores the exact state incl. AI difficulty', (
      tester,
    ) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      // A live match: human rolled a 6 against a hard AI.
      final game = LudoGame.newMatch(
        seats: const [
          SeatConfig(name: 'Player 1', colour: PlayerColour.red),
          SeatConfig(
            name: 'Player 2',
            colour: PlayerColour.green,
            type: PlayerType.ai,
            difficulty: AiDifficulty.hard,
          ),
        ],
        diceRoller: FixedDiceRoller([6]),
      );
      game.rollDice();
      final resumedState = game.state;

      await tester.pumpWidget(
        scopedApp(
          deps,
          GameScreen(initialState: resumedState),
          diceRoller: FixedDiceRoller([6], cycle: true),
        ),
      );
      await tester.pumpAndSettle();

      // The restored turn: Player 1 has a 6 outstanding.
      expect(find.textContaining('choose a token'), findsOneWidget);

      // Release the first token (yard slot 0).
      final board = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
      );
      await tester.ensureVisible(board);
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(board);
      await tester.tapAt(origin + const Offset(64, 64));
      await tester.pump();
      await deps.snapshotSaver.flush;

      // The saved snapshot carries the resumed state forward: one
      // move applied, still Player 1 (six = extra turn), and the AI
      // seat is still hard — not reset to easy.
      final json = await savedSnapshotJson(deps);
      expect(json['moveCount'], 1);
      expect(json['currentPlayerIndex'], 0);
      expect(json['phase'], 'awaitingRoll');
      final players = json['players'] as List;
      expect((players[1] as Map<String, Object?>)['difficulty'], 'hard');
      expect((players[1] as Map<String, Object?>)['type'], 'ai');
    });
  });

  // -- Snapshots ----------------------------------------------------------

  group('snapshots', () {
    testWidgets('roll settle saves the rolled state; a completed move '
        'saves the moved state', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await tester.pumpWidget(
        scopedApp(
          deps,
          const GameScreen(
            initialSetup: GameSetup(playerCount: 2, aiSeats: {}),
          ),
          diceRoller: FixedDiceRoller([6, 6], cycle: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await deps.snapshotSaver.flush;

      var json = await savedSnapshotJson(deps);
      expect(json['lastRoll'], 6);
      expect(json['phase'], 'awaitingMove');
      expect(json['moveCount'], 0);

      final board = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
      );
      await tester.ensureVisible(board);
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(board);
      await tester.tapAt(origin + const Offset(64, 64));
      await tester.pump();
      await deps.snapshotSaver.flush;

      json = await savedSnapshotJson(deps);
      expect(json['moveCount'], 1);
      expect(json['phase'], 'awaitingRoll');
      expect(json['lastRoll'], 0);
    });
  });

  // -- Clean exit ---------------------------------------------------------

  group('clean exit', () {
    Future<void> seedSnapshot(AppDependencies deps) async {
      final game = LudoGame.newMatch(
        seats: const [
          SeatConfig(name: 'Player 1', colour: PlayerColour.red),
          SeatConfig(name: 'Player 2', colour: PlayerColour.green),
        ],
      );
      deps.snapshotSaver.save(game.state);
      await deps.snapshotSaver.flush;
    }

    Future<void> openGame(
      WidgetTester tester,
      AppDependencies deps,
      GameScreen game,
    ) async {
      await tester.pumpWidget(scopedApp(deps, _HostScreen(game: game)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open game'));
      await tester.pumpAndSettle();
    }

    testWidgets('pause menu Main Menu (confirm) deletes the snapshot '
        'and records nothing', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await seedSnapshot(deps);
      await openGame(
        tester,
        deps,
        const GameScreen(initialSetup: GameSetup(playerCount: 2, aiSeats: {})),
      );

      // M2.6: the AppBar close button is the pause button now;
      // leaving goes through the pause menu's Main Menu.
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(find.text('Paused'), findsOneWidget);
      await tester.tap(find.text('Main Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Leave the match?'), findsOneWidget);
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();

      expect(find.text('Ready to play?'), findsOneWidget);
      expect(await deps.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      expect(await deps.matches.countMatches(), 0);
      final stats = await deps.statistics.getStatistics();
      expect(stats.matchesPlayed, 0);
    });

    testWidgets('restart from the pause menu discards the snapshot '
        'and records nothing', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await seedSnapshot(deps);
      await openGame(
        tester,
        deps,
        const GameScreen(initialSetup: GameSetup(playerCount: 2, aiSeats: {})),
      );

      // M2.6: Restart lives in the pause menu now.
      await tester.tap(find.byTooltip('Pause'));
      await tester.pumpAndSettle();
      expect(find.text('Paused'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();
      expect(find.text('Restart match?'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pumpAndSettle();

      expect(find.textContaining('roll the dice to start'), findsOneWidget);
      expect(await deps.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      expect(await deps.matches.countMatches(), 0);
    });
  });

  // -- Completion ---------------------------------------------------------

  group('completion', () {
    /// A match one move from a win: Player 1 has three tokens home
    /// and the fourth one step away, with a 1 outstanding.
    GameState nearWinState() => stateWith(
      tokenSteps: const [
        [56, 56, 56, 55],
        [0, 0, 0, 0],
      ],
      current: 0,
      lastRoll: 1,
      phase: TurnPhase.awaitingMove,
    );

    Future<void> tapWinningToken(WidgetTester tester, GameState state) async {
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
        const Size(480, 480),
        tokens,
      );
      await tester.tapAt(origin + centre);
      await tester.pump();
    }

    testWidgets('finishing records exactly once and deletes the '
        'snapshot', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final state = nearWinState();
      deps.snapshotSaver.save(state);
      await deps.snapshotSaver.flush;

      await tester.pumpWidget(scopedApp(deps, GameScreen(initialState: state)));
      await tester.pumpAndSettle();
      await tapWinningToken(tester, state);
      await tester.pumpAndSettle();

      // M2.5: completion navigates to the results *route*, not a
      // dialog — the game screen is gone, the results screen shows
      // the winner.
      expect(find.byType(ResultsScreen), findsOneWidget);
      expect(find.byType(GameScreen), findsNothing);
      expect(find.text('Player 1 wins!'), findsOneWidget);
      expect(await deps.matches.countMatches(), 1);
      final matches = await deps.matches.listMatches();
      expect(matches.single.winnerName, 'Player 1');
      expect(matches.single.mode, LocalMatchMode.localMultiplayer);
      expect(matches.single.rulesetVersion, '1.0.0');
      final stats = await deps.statistics.getStatistics();
      expect(stats.matchesPlayed, 1);
      expect(stats.matchesWon, 1);
      expect(await deps.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);

      // Play Again starts a fresh match without recording again.
      // The button sits below the fold in the test viewport.
      final playAgain = find.text('Play Again');
      await tester.ensureVisible(playAgain);
      await tester.tap(playAgain);
      await tester.pumpAndSettle();
      expect(await deps.matches.countMatches(), 1);
      expect(find.byType(GameScreen), findsOneWidget);
      expect(find.textContaining('roll the dice to start'), findsOneWidget);
    });

    testWidgets('record failure shows a notice, keeps the app usable, '
        'and leaves the snapshot for retry', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final state = nearWinState();
      deps.snapshotSaver.save(state);
      await deps.snapshotSaver.flush;

      await tester.pumpWidget(scopedApp(deps, GameScreen(initialState: state)));
      await tester.pumpAndSettle();
      store.failNextCall();
      await tapWinningToken(tester, state);
      await tester.pumpAndSettle();

      expect(find.byType(ResultsScreen), findsOneWidget);
      expect(find.text('Player 1 wins!'), findsOneWidget);
      expect(find.text(kMatchRecordFailedMessage), findsOneWidget);
      expect(await deps.matches.countMatches(), 0);
      // Defined failure handling: the snapshot is left in place so
      // the finished match stays resumable and recording is retried
      // on resume.
      expect(await deps.snapshots.hasSnapshot(kCurrentMatchKey), isTrue);

      final playAgain = find.text('Play Again');
      await tester.ensureVisible(playAgain);
      await tester.tap(playAgain);
      await tester.pumpAndSettle();
      expect(find.text('Roll dice'), findsOneWidget);
    });
  });

  // -- History ------------------------------------------------------------

  group('history screen', () {
    testWidgets('lists matches newest first with Local labels and a '
        'detail view', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await deps.matches.recordMatch(
        sampleMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 0),
          winnerName: 'Player 1',
          winnerIndex: 0,
        ),
      );
      await deps.matches.recordMatch(
        sampleMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 30),
          winnerName: 'Player 2',
          winnerIndex: 1,
        ),
      );

      await tester.pumpWidget(scopedApp(deps, const HistoryScreen()));
      await tester.pumpAndSettle();

      // Newest first: Player 2's match is the first tile.
      final firstTile = find.textContaining('Player 2 won');
      expect(firstTile, findsOneWidget);
      expect(find.text('Local'), findsNWidgets(2));

      await tester.tap(firstTile);
      await tester.pumpAndSettle();
      expect(find.text('vs AI'), findsOneWidget);
      expect(find.textContaining('Player 2'), findsWidgets);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('empty history shows the empty state', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await tester.pumpWidget(scopedApp(deps, const HistoryScreen()));
      await tester.pumpAndSettle();
      expect(find.text('No matches yet'), findsOneWidget);
    });

    testWidgets('unavailable database shows the unavailable state', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HistoryScreen()));
      await tester.pumpAndSettle();
      expect(find.text('History unavailable'), findsOneWidget);
    });
  });
}

/// A host screen that pushes a [GameScreen] on tap, so exit tests
/// can observe the pop back to a live screen.
class _HostScreen extends StatelessWidget {
  const _HostScreen({required this.game});

  final Widget game;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => game)),
          child: const Text('Open game'),
        ),
      ),
    );
  }
}

/// A [DatabaseFactory] that throws on every open, delegating
/// everything else to the real ffi factory — the M1.5 pattern, so
/// a test can prove startup degrades instead of crashing.
class _ThrowingDatabaseFactory implements DatabaseFactory {
  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) =>
      throw StateError('Simulated database open failure.');

  @override
  Future<void> deleteDatabase(String path) =>
      databaseFactoryFfi.deleteDatabase(path);

  @override
  Future<bool> databaseExists(String path) =>
      databaseFactoryFfi.databaseExists(path);

  @override
  Future<String> getDatabasesPath() => databaseFactoryFfi.getDatabasesPath();

  @override
  Future<void> setDatabasesPath(String path) =>
      databaseFactoryFfi.setDatabasesPath(path);

  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      databaseFactoryFfi.readDatabaseBytes(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      databaseFactoryFfi.writeDatabaseBytes(path, bytes);
}
