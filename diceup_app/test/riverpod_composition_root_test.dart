/// Composition-root tests (M3.3, H-07; D-06).
///
/// The provider graph is the only path to a controller: these tests
/// prove the wiring (repositories → use cases → controller), the
/// lifecycle (disposal cancels timers), the test seams (provider
/// overrides, not constructor parameters), the startup wiring
/// (`initializeApp` → providers available before the first frame)
/// and the single-source-of-truth property (a state change driven
/// through the provider is what the screen renders — the screen
/// holds no copy of the game state).
library;

import 'dart:convert';

import 'package:diceup/core/design_system/diceup_theme.dart';
import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:diceup/domain/usecases/match_setup.dart';
import 'package:diceup/main.dart';
import 'package:diceup/presentation/feedback/feedback_service.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/game_screen.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repositories/fakes/fakes.dart';
import 'test_providers.dart';

void main() {
  AppDependencies fakeDeps(InMemoryStore store) => AppDependencies(
    matches: InMemoryLocalMatchRepository(store),
    statistics: InMemoryLocalStatisticsRepository(store),
    settings: InMemorySettingsRepository(store),
    players: InMemoryLocalPlayerRepository(store),
    snapshots: InMemorySnapshotRepository(store),
  );

  group('provider graph wiring', () {
    test('repository providers are the startup dependencies (one '
        'construction site, no second copy)', () {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final container = ProviderContainer(
        overrides: [startupResultProvider.overrideWithValue(testStartup(deps))],
      );
      addTearDown(container.dispose);

      expect(container.read(localMatchRepositoryProvider), same(deps.matches));
      expect(
        container.read(localStatisticsRepositoryProvider),
        same(deps.statistics),
      );
      expect(container.read(settingsRepositoryProvider), same(deps.settings));
      expect(container.read(localPlayerRepositoryProvider), same(deps.players));
      expect(container.read(snapshotRepositoryProvider), same(deps.snapshots));
      expect(container.read(snapshotWriterProvider), same(deps.snapshotSaver));
    });

    test('use-case providers are wired from the repositories; '
        'applyMove is null when degraded', () {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final container = ProviderContainer(
        overrides: [
          startupResultProvider.overrideWithValue(testStartup(deps)),
          diceRollerProvider.overrideWithValue(
            FixedDiceRoller(const [6], cycle: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      // The start use case rolls the fixed 6.
      final game = container.read(startOfflineMatchProvider)(
        const MatchSetup(playerCount: 2, aiSeats: {}),
      );
      expect(game.state.currentPlayerIndex, 0);
      expect(container.read(applyMoveProvider), isNotNull);

      final degraded = ProviderContainer(
        overrides: [startupResultProvider.overrideWithValue(testStartup(null))],
      );
      addTearDown(degraded.dispose);
      expect(degraded.read(applyMoveProvider), isNull);
      expect(degraded.read(localMatchRepositoryProvider), isNull);
    });

    test('controller provision + disposal: disposing the container '
        'disposes the controller (timers cancelled, later calls '
        'ignored)', () {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final container = ProviderContainer(
        overrides: [
          startupResultProvider.overrideWithValue(testStartup(deps)),
          diceRollerProvider.overrideWithValue(
            FixedDiceRoller(const [6], cycle: true),
          ),
        ],
      );
      // A listener keeps the autoDispose provider alive while the
      // test drives it (a bare read does not subscribe).
      final subscription = container.listen(
        offlineGameControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      addTearDown(container.dispose);

      final controller = container.read(offlineGameControllerProvider);
      controller.startMatch(const MatchSetup(playerCount: 2, aiSeats: {}));
      expect(controller.status, contains('roll the dice to start'));

      container.dispose();
      // The controller is disposed: a roll afterwards is ignored —
      // no tumble starts, no state changes, no timer fires.
      controller.rollDice();
      expect(controller.displayedRoll, isNull);
      expect(controller.status, contains('roll the dice to start'));
    });
  });

  group('GameScreen through the provider graph', () {
    testWidgets('boots with in-memory fakes and reaches the game '
        'screen; a move persists through the provider controller', (
      tester,
    ) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await tester.pumpWidget(
        withTestProviders(
          dependencies: deps,
          diceRoller: FixedDiceRoller([6, 6], cycle: true),
          child: MaterialApp(
            theme: DiceUpTheme.light(),
            home: const GameScreen(
              initialSetup: GameSetup(playerCount: 2, aiSeats: {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('roll the dice to start'), findsOneWidget);

      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.textContaining('choose a token'), findsOneWidget);

      final board = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
      );
      await tester.ensureVisible(board);
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(board);
      await tester.tapAt(origin + const Offset(64, 64));
      await tester.pump();
      await deps.snapshotSaver.flush;

      expect(find.textContaining('rolls again'), findsOneWidget);
      final saved = await deps.snapshots.loadSnapshot(kCurrentMatchKey);
      expect(saved, isNotNull);
      final json = jsonDecode(saved!.snapshotJson) as Map<String, Object?>;
      expect(json['moveCount'], 1);
    });

    testWidgets('no duplicated game state: a roll driven through '
        'the provider controller is what the screen renders', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await tester.pumpWidget(
        withTestProviders(
          dependencies: deps,
          diceRoller: FixedDiceRoller([6, 6], cycle: true),
          child: MaterialApp(
            theme: DiceUpTheme.light(),
            home: const GameScreen(
              initialSetup: GameSetup(playerCount: 2, aiSeats: {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drive the match from outside the screen, through the same
      // provider the screen watches. If the screen held its own
      // copy of the state, this roll would never reach it.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(GameScreen)),
      );
      container.read(offlineGameControllerProvider).rollDice();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      expect(find.textContaining('choose a token'), findsOneWidget);
    });

    testWidgets('provider overrides are the test seam: a fake '
        'feedback service is called once per move when vibration '
        'is enabled', (tester) async {
      final feedback = _FakeFeedbackService();
      await tester.pumpWidget(
        withTestProviders(
          diceRoller: FixedDiceRoller([6], cycle: true),
          feedbackService: feedback,
          vibrationEnabled: true,
          child: MaterialApp(
            theme: DiceUpTheme.light(),
            home: const GameScreen(
              initialSetup: GameSetup(playerCount: 2, aiSeats: {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      final board = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
      );
      await tester.ensureVisible(board);
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(board);
      await tester.tapAt(origin + const Offset(64, 64));
      await tester.pump();

      expect(feedback.calls, 1);
    });

    testWidgets('a GameScreen without a ProviderScope fails loudly '
        '(the provider graph is the only path to a controller)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: DiceUpTheme.light(),
          home: const GameScreen(
            initialSetup: GameSetup(playerCount: 2, aiSeats: {}),
          ),
        ),
      );
      final error = tester.takeException();
      expect(error, isNotNull);
      expect(error.toString(), contains('ProviderScope'));
    });
  });

  group('startup wiring', () {
    testWidgets('DiceUpApp with an awaited startup provides the '
        'graph before the first frame; test overrides compose '
        'with the app scope', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await tester.pumpWidget(
        DiceUpApp(
          startup: testStartup(deps),
          testDiceRoller: FixedDiceRoller([6, 6], cycle: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ready to play?'), findsOneWidget);
      await tester.tap(find.text('Play Offline'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play vs AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start match'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('roll the dice to start'), findsOneWidget);

      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.textContaining('choose a token'), findsOneWidget);

      final board = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
      );
      await tester.ensureVisible(board);
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(board);
      await tester.tapAt(origin + const Offset(64, 64));
      await tester.pump();
      await deps.snapshotSaver.flush;

      final saved = await deps.snapshots.loadSnapshot(kCurrentMatchKey);
      expect(saved, isNotNull);
      final json = jsonDecode(saved!.snapshotJson) as Map<String, Object?>;
      expect(json['moveCount'], 1);
    });
  });
}

/// A recording [FeedbackService] for the override test.
class _FakeFeedbackService implements FeedbackService {
  int calls = 0;

  @override
  Future<void> vibrateMove() async {
    calls++;
  }
}
