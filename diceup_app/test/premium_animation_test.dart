import 'package:diceup/core/design_system/diceup_theme.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/offline_game_controller.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/game_screen.dart';
import 'package:diceup/presentation/widgets/dice_widget.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine/test_helpers.dart';
import 'test_providers.dart';

/// M3 premium animation (brief §4): per-cell token stepping, capture
/// return-to-base, dice polish, reduced-motion collapse.
///
/// The step sequence (Q1) moves one token one cell at a time —
/// ~110 ms per cell, total clamped to 250–600 ms — so a multi-cell
/// move visibly occupies each intermediate cell in turn. The
/// capture return (Q6) plays only after the mover settles: lift →
/// shrink/fade → arc to the yard → pop-in. Reduced motion (Q7)
/// honours Android's [MediaQuery.disableAnimations] and iOS's Reduce
/// Motion accessibility feature, collapsing every sequence to an
/// instant settle. Pause freeze/resume (Q2) is proven by the
/// rewritten pause test in `test/animation_test.dart` — it pauses
/// a six-step sequence mid-flight, pumps 5 s (frozen), resumes,
/// and asserts completion — so it is not duplicated here.
///
/// All tests use [GameScreen.initialState] with exact token
/// positions ([stateWith]), so no scripted play is needed to reach
/// the position under test. The board is 480 dp in these tests;
/// expected centres come from [boardTokenCenter] (the same
/// geometry the painter uses), never from the test's own copy.
void main() {
  const boardSize = Size(480, 480);

  /// All eight tokens at the given step counts, in seat order.
  List<BoardToken> tokensAt(List<int> p1Steps, List<int> p2Steps) {
    return [
      for (var i = 0; i < 4; i++)
        BoardToken(
          id: '0:$i',
          seatIndex: 0,
          stepsTaken: p1Steps[i],
          colour: PlayerColour.red,
        ),
      for (var i = 0; i < 4; i++)
        BoardToken(
          id: '1:$i',
          seatIndex: 1,
          stepsTaken: p2Steps[i],
          colour: PlayerColour.green,
        ),
    ];
  }

  Finder boardFinder() => find.byWidgetPredicate(
    (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
  );

  LudoBoardPainter boardPainter(WidgetTester tester) =>
      tester.widget<CustomPaint>(boardFinder()).painter as LudoBoardPainter;

  int diceFace(WidgetTester tester) =>
      tester.widget<DiceWidget>(find.byType(DiceWidget)).value ?? -1;

  void enableReduceMotion(WidgetTester tester) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  }

  /// Pumps a [GameScreen] from an exact [GameState] under a
  /// [ProviderScope] with a fixed dice roller and degraded play
  /// (no repositories — nothing is persisted). The viewport is
  /// tall (800x1400) so the whole column fits with no scrolling.
  /// [reducedMotion] wraps the screen in a [MediaQuery] with its
  /// animation flag overridden, so Android's setting is testable
  /// without changing the platform value.
  Future<OfflineGameController> pumpGame(
    WidgetTester tester, {
    required GameState state,
    List<int> dice = const [6],
    MediaQueryData Function(MediaQueryData data)? reducedMotion,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late final ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          startupResultProvider.overrideWithValue(testStartup(null)),
          diceRollerProvider.overrideWithValue(
            FixedDiceRoller(dice, cycle: true),
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            // The game screen is captured in its own final before
            // the wrapper is built: the wrapper's builder closes
            // over the variable, so reassigning `screen` to the
            // wrapper itself made the MediaQuery's child the
            // wrapper — an infinitely self-nesting tree that
            // overflowed the stack on every reduced-motion pump
            // (54k nested mounts, 53+ min hung run).
            final Widget gameScreen = GameScreen(initialState: state);
            Widget screen = gameScreen;
            if (reducedMotion != null) {
              screen = Builder(
                builder: (context) => MediaQuery(
                  data: reducedMotion(MediaQuery.of(context)),
                  child: gameScreen,
                ),
              );
            }
            return MaterialApp(theme: DiceUpTheme.light(), home: screen);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container.read(offlineGameControllerProvider);
  }

  /// Taps the board at [offset] inside the board (origin at the
  /// board's top-left) and lets the move apply.
  Future<void> tapBoardAt(WidgetTester tester, Offset offset) async {
    final origin = tester.getTopLeft(boardFinder());
    await tester.tapAt(origin + offset);
    await tester.pump();
  }

  /// The centre of the token at [stepsTaken] for seat [seatIndex]
  /// among [allTokens], on the 480 board.
  Offset centreFor(int seatIndex, int stepsTaken, List<BoardToken> all) =>
      boardTokenCenter(
        BoardToken(
          id: '$seatIndex:0',
          seatIndex: seatIndex,
          stepsTaken: stepsTaken,
        ),
        boardSize,
        all,
      );

  group('per-cell token movement (§2.2, Q1)', () {
    testWidgets('a multi-cell move renders the token at each '
        'intermediate cell in order', (tester) async {
      // Red token 0 at step 1, last roll 6, awaiting a move: the
      // tap moves it six cells (steps 1 → 7). Six segments at
      // ~110 ms each, total clamped to 600 ms → 100 ms per segment.
      final controller = await pumpGame(
        tester,
        state: stateWith(
          tokenSteps: const [
            [1, 0, 0, 0],
            [0, 0, 0, 0],
          ],
          lastRoll: 6,
          phase: TurnPhase.awaitingMove,
        ),
      );
      final all = tokensAt(const [1, 0, 0, 0], const [0, 0, 0, 0]);
      await tapBoardAt(tester, centreFor(0, 1, all));
      expect(controller.state.moveCount, 1);
      expect(controller.state.players[0].tokens[0].stepsTaken, 7);

      // The sequence starts at the old cell.
      expect(boardPainter(tester).hopTokenId, '0:0');
      expect(boardPainter(tester).hopCenter, centreFor(0, 1, all));

      // At each 100 ms segment boundary the token is exactly on
      // the next intermediate cell — never between cells at a
      // boundary, never skipping one.
      for (var step = 2; step <= 6; step++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(boardPainter(tester).hopTokenId, '0:0');
        expect(
          boardPainter(tester).hopCenter,
          centreFor(0, step, tokensAt([step, 0, 0, 0], const [0, 0, 0, 0])),
          reason: 'at segment boundary the token must sit on step $step',
        );
      }

      // The final segment lands on step 7, the sequence ends, the
      // last-moved ring marks the token, and input unlocks (a six:
      // roll again).
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(boardPainter(tester).hopTokenId, isNull);
      expect(boardPainter(tester).hopCenter, isNull);
      expect(boardPainter(tester).lastMovedTokenId, '0:0');
      expect(boardPainter(tester).lastMovedOpacity, greaterThan(0.0));
      expect(find.text('Roll dice'), findsOneWidget);
    });
  });

  group('capture animation (§2.3, Q6)', () {
    testWidgets('a capture plays the return-to-base sequence after '
        'the mover settles and ends with the token in its yard', (
      tester,
    ) async {
      // Red token 0 at step 12, green token 0 at step 2 (track 14),
      // last roll 3, awaiting a move: red moves 12 → 15 and lands
      // on green's cell. Three segments at 110 ms = 330 ms, then
      // the ~600 ms capture return.
      final controller = await pumpGame(
        tester,
        state: stateWith(
          tokenSteps: const [
            [12, 0, 0, 0],
            [2, 0, 0, 0],
          ],
          lastRoll: 3,
          phase: TurnPhase.awaitingMove,
        ),
      );
      final before = tokensAt(const [12, 0, 0, 0], const [2, 0, 0, 0]);
      final after = tokensAt(const [15, 0, 0, 0], const [0, 0, 0, 0]);
      await tapBoardAt(tester, centreFor(0, 12, before));
      expect(controller.state.moveCount, 1);
      expect(controller.state.players[0].tokens[0].stepsTaken, 15);
      expect(controller.state.players[1].tokens[0].stepsTaken, 0);

      // No capture while the mover is still stepping.
      await tester.pump(const Duration(milliseconds: 110));
      expect(boardPainter(tester).hopTokenId, '0:0');
      expect(boardPainter(tester).captureTokenId, isNull);

      // The final step of a capturing move settles larger: the
      // mid-step lift peaks at 1.18, not the usual 1.12.
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 55));
      expect(boardPainter(tester).hopScale, closeTo(1.18, 0.01));

      // The mover settles, then the capture starts: the captured
      // token lifts off its cell, shrinks and fades on an arc
      // toward its yard.
      await tester.pump(const Duration(milliseconds: 55));
      await tester.pump(const Duration(milliseconds: 300));
      final painter = boardPainter(tester);
      expect(painter.hopTokenId, isNull);
      expect(painter.captureTokenId, '1:0');
      expect(painter.captureScale, lessThan(1.0));
      expect(painter.captureOpacity, lessThan(1.0));
      expect(painter.captureCenter, isNot(centreFor(1, 2, before)));
      expect(painter.captureCenter, isNot(centreFor(1, 0, after)));

      // The capture completes: the token pops into its yard slot
      // and the engine state is the final one.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(boardPainter(tester).captureTokenId, isNull);
      expect(controller.state.players[1].tokens[0].stepsTaken, 0);
      expect(controller.state.players[0].tokens[0].stepsTaken, 15);
      // The mover keeps the last-moved ring after the capture.
      expect(boardPainter(tester).lastMovedTokenId, '0:0');
    });

    testWidgets('reduced motion collapses the capture to an instant '
        'settle', (tester) async {
      final controller = await pumpGame(
        tester,
        state: stateWith(
          tokenSteps: const [
            [12, 0, 0, 0],
            [2, 0, 0, 0],
          ],
          lastRoll: 3,
          phase: TurnPhase.awaitingMove,
        ),
        reducedMotion: (data) => data.copyWith(disableAnimations: true),
      );
      final before = tokensAt(const [12, 0, 0, 0], const [2, 0, 0, 0]);
      await tapBoardAt(tester, centreFor(0, 12, before));
      expect(boardPainter(tester).hopTokenId, isNull);
      expect(boardPainter(tester).captureTokenId, isNull);
      expect(controller.state.players[1].tokens[0].stepsTaken, 0);
      expect(controller.state.players[0].tokens[0].stepsTaken, 15);
    });
  });

  group('dice polish (§2.4)', () {
    testWidgets('the dice settles on the engine value with input '
        'locked during the roll', (tester) async {
      final controller = await pumpGame(
        tester,
        state: stateWith(
          tokenSteps: const [
            [0, 0, 0, 0],
            [0, 0, 0, 0],
          ],
        ),
        dice: const [6],
      );
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.rolling, isTrue);
      expect(find.text('Roll dice'), findsNothing);
      expect(find.text('Rolling…'), findsNWidgets(2));
      expect(diceFace(tester), inInclusiveRange(1, 6));

      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, 6);
      expect(diceFace(tester), 6);
      expect(find.textContaining('choose a token to move'), findsOneWidget);
    });
  });

  group('reduced motion (§2.7, Q7)', () {
    testWidgets('disableAnimations collapses a step sequence to an '
        'instant settle', (tester) async {
      final controller = await pumpGame(
        tester,
        state: stateWith(
          tokenSteps: const [
            [1, 0, 0, 0],
            [0, 0, 0, 0],
          ],
          lastRoll: 6,
          phase: TurnPhase.awaitingMove,
        ),
        reducedMotion: (data) => data.copyWith(disableAnimations: true),
      );
      final all = tokensAt(const [1, 0, 0, 0], const [0, 0, 0, 0]);
      await tapBoardAt(tester, centreFor(0, 1, all));
      // No sequence at all: the token is already at its engine
      // position and input is unlocked.
      expect(boardPainter(tester).hopTokenId, isNull);
      expect(boardPainter(tester).hopCenter, isNull);
      expect(controller.state.players[0].tokens[0].stepsTaken, 7);
      expect(find.text('Roll dice'), findsOneWidget);
    });

    testWidgets('iOS Reduce Motion collapses a step sequence to an '
        'instant settle', (tester) async {
      enableReduceMotion(tester);
      final controller = await pumpGame(
        tester,
        state: stateWith(
          tokenSteps: const [
            [1, 0, 0, 0],
            [0, 0, 0, 0],
          ],
          lastRoll: 6,
          phase: TurnPhase.awaitingMove,
        ),
      );
      final all = tokensAt(const [1, 0, 0, 0], const [0, 0, 0, 0]);
      await tapBoardAt(tester, centreFor(0, 1, all));
      expect(boardPainter(tester).hopTokenId, isNull);
      expect(boardPainter(tester).hopCenter, isNull);
      expect(controller.state.players[0].tokens[0].stepsTaken, 7);
      expect(find.text('Roll dice'), findsOneWidget);
    });

    testWidgets('reduced motion freezes the dice face at its pre-roll '
        'value until the roll settles (disableAnimations)', (tester) async {
      final controller = await pumpGame(
        tester,
        state: stateWith(
          tokenSteps: const [
            [0, 0, 0, 0],
            [0, 0, 0, 0],
          ],
        ),
        dice: const [6],
        reducedMotion: (data) => data.copyWith(disableAnimations: true),
      );
      await tester.tap(find.text('Roll dice'));
      // Mid-roll the face is frozen at the pre-roll value (none
      // yet: -1) — no tumble frames are shown.
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.rolling, isTrue);
      expect(diceFace(tester), -1);

      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, 6);
      expect(diceFace(tester), 6);
    });
  });
}
