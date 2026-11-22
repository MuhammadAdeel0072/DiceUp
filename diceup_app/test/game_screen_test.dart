import 'package:diceup/core/design_system/diceup_theme.dart';
import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/offline_game_controller.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/game_screen.dart';
import 'package:diceup/presentation/widgets/dice_widget.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_providers.dart';

void main() {
  testWidgets('offline match: roll a 6 and release a token', (tester) async {
    await tester.pumpWidget(
      withTestProviders(
        diceRoller: FixedDiceRoller([6, 6, 6]),
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

    // Roll a 6 (fixed dice). The animation settles after ~540 ms.
    // The dice row sits below the fold in the 800x600 test viewport,
    // so scroll it into view first — a real user scrolls the same way.
    await tester.ensureVisible(find.text('Roll dice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roll dice'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.textContaining('choose a token'), findsOneWidget);

    // Tap the first red yard token (yard slot 0: board cell 32px,
    // slot centre at (64, 64) inside the board). Scroll the board back
    // into view first — the earlier ensureVisible scrolled it up.
    final board = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
    );
    expect(board, findsOneWidget);
    await tester.ensureVisible(board);
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(board);
    await tester.tapAt(origin + const Offset(64, 64));
    await tester.pump();

    // A 6 grants an extra roll, so Player 1 rolls again.
    expect(find.textContaining('rolls again'), findsOneWidget);
  });

  // -- M2.8: illegal-tap feedback + tappable dice (FR-21, M-02) ------
  //
  // The dice taps exactly as the Roll button does, under the same
  // guards — a tap that cannot roll is never queued and never rolls
  // the dice: it gets a SnackBar + status update naming the reason,
  // and the game state is untouched. A tap on a token that cannot
  // move gets the plan's message ("That token can't move now");
  // taps on empty board area stay silent, as the plan requires
  // feedback for token taps only. No haptic: the plan names the
  // SnackBar + status only, and haptics are reserved for completed
  // moves (M1.7, D-32).
  //
  // Test-framework notes: a SnackBar lives 2 s in fake time, so
  // tests assert it right after the tap with a bounded pump — a
  // later `pumpAndSettle` would dismiss it first. While a roll is
  // tumbling the turn banner shows a `CircularProgressIndicator`
  // (an infinite animation), so mid-tumble tests use bounded pumps
  // only, never `pumpAndSettle` (M2.7 note) — and a settle after
  // the turn passes to the AI would fire its pacing timer, so dice
  // taps on the AI turn are made with no settle at all.

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

  /// Pumps a [GameScreen] under a [ProviderScope] with a fixed dice
  /// roller and degraded play (no repositories — nothing is
  /// persisted), and returns the provider-owned controller so tests
  /// can assert engine state alongside the feedback. Same shape as
  /// `test/animation_test.dart`'s `pumpGame`, except the viewport
  /// is tall (800x1400) so the whole column fits with no scrolling:
  /// no `ensureVisible` is ever needed, and no helper has to settle
  /// (a settle mid-tumble or on the AI turn would advance fake time
  /// past the state under test).
  Future<OfflineGameController> pumpGame(
    WidgetTester tester, {
    required List<int> dice,
    bool vsAi = false,
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
            return MaterialApp(
              theme: DiceUpTheme.light(),
              home: GameScreen(
                initialSetup: GameSetup(
                  playerCount: 2,
                  aiSeats: vsAi ? {1: AiDifficulty.easy} : {},
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container.read(offlineGameControllerProvider);
  }

  /// Taps Roll and lets the ~540 ms tumble settle.
  Future<void> roll(WidgetTester tester) async {
    await tester.tap(find.text('Roll dice'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
  }

  /// Taps the dice and lets the ~540 ms tumble settle (the
  /// happy-path dice roll).
  Future<void> rollByDiceTap(WidgetTester tester) async {
    await tester.tap(find.byType(DiceWidget));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
  }

  /// Taps the board at [offset] inside the board (origin at the
  /// board's top-left) and lets the tap land. Ends with one bounded
  /// pump — never a settle, so a SnackBar shown by the tap is still
  /// up when the test asserts on it.
  Future<void> tapBoardAt(WidgetTester tester, Offset offset) async {
    final origin = tester.getTopLeft(boardFinder());
    await tester.tapAt(origin + offset);
    await tester.pump();
  }

  /// Taps the token at [stepsTaken] among [allTokens].
  Future<void> tapToken(
    WidgetTester tester,
    BoardToken token,
    List<BoardToken> allTokens,
  ) async {
    final centre = boardTokenCenter(token, boardSize, allTokens);
    await tapBoardAt(tester, centre);
  }

  /// Taps the dice with no settle — the caller decides the pumps,
  /// so a mid-tumble or AI-turn state can be read first.
  Future<void> tapDice(WidgetTester tester) async {
    await tester.tap(find.byType(DiceWidget));
    await tester.pump();
  }

  /// Plays the human's opening (roll 6, release token 0, roll 2,
  /// move token 0) so the turn passes to the AI and its pacing
  /// timer is pending — the AI has not acted yet (no pump past
  /// 700 ms), so the turn still belongs to seat 1.
  Future<void> reachAiTurn(
    WidgetTester tester,
    OfflineGameController controller,
  ) async {
    await roll(tester);
    await tapToken(
      tester,
      const BoardToken(id: '0:0', seatIndex: 0, stepsTaken: 0),
      tokensAt([0, 0, 0, 0], [0, 0, 0, 0]),
    );
    expect(controller.state.moveCount, 1);
    await tester.pump(const Duration(milliseconds: 300));
    await roll(tester);
    expect(controller.displayedRoll, 2);
    await tapToken(
      tester,
      const BoardToken(
        id: '0:0',
        seatIndex: 0,
        stepsTaken: 1,
        colour: PlayerColour.red,
      ),
      tokensAt([1, 0, 0, 0], [0, 0, 0, 0]),
    );
    expect(controller.state.moveCount, 2);
    expect(controller.state.currentPlayerIndex, 1);
    expect(controller.rolling, isFalse);
  }

  /// A token that can move after rolling a 6 then a 2: token 0
  /// released (steps 1), three yard tokens still stuck, one legal
  /// move (token 0 by 2). Returns the controller for assertions.
  Future<OfflineGameController> oneLegalMoveState(WidgetTester tester) async {
    final controller = await pumpGame(tester, dice: const [6, 2]);
    await roll(tester);
    await tapToken(
      tester,
      const BoardToken(id: '0:0', seatIndex: 0, stepsTaken: 0),
      tokensAt([0, 0, 0, 0], [0, 0, 0, 0]),
    );
    expect(controller.state.moveCount, 1);
    await tester.pump(const Duration(milliseconds: 300));
    await roll(tester);
    expect(controller.displayedRoll, 2);
    expect(controller.legalMoves, hasLength(1));
    return controller;
  }

  /// Asserts the illegal-tap feedback for [message]: the SnackBar
  /// is up carrying it, and the status line shows the same text.
  void expectIllegalFeedback(
    WidgetTester tester,
    OfflineGameController controller,
    String message,
  ) {
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.text(message)),
      findsOneWidget,
    );
    expect(controller.status, message);
  }

  double diceOpacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(DiceWidget),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  group('tappable dice (M2.8)', () {
    testWidgets('tapping the dice rolls when allowed', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      expect(
        tester.widget<DiceWidget>(find.byType(DiceWidget)).enabled,
        isTrue,
      );
      expect(find.byTooltip('Tap to roll'), findsOneWidget);
      expect(diceOpacity(tester), 1.0);

      await rollByDiceTap(tester);

      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(controller.state.moveCount, 0);
      expect(find.textContaining('choose a token to move'), findsOneWidget);
    });

    testWidgets('dice looks disabled while rolling', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(controller.rolling, isTrue);
      expect(
        tester.widget<DiceWidget>(find.byType(DiceWidget)).enabled,
        isFalse,
      );
      expect(diceOpacity(tester), 0.6);
      expect(find.byTooltip('Tap to roll'), findsNothing);

      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.displayedRoll, 6);
    });

    testWidgets('rapid double-tap on the dice rolls exactly once', (
      tester,
    ) async {
      final controller = await pumpGame(tester, dice: const [6]);

      // Two taps with no pump between: the tightest race — the
      // second tap lands while the first roll's tumble is starting.
      await tester.tap(find.byType(DiceWidget));
      await tester.tap(find.byType(DiceWidget));
      await tester.pump();

      // The second tap was illegal-tap feedback, not a second roll.
      expectIllegalFeedback(tester, controller, 'Wait for the dice to settle.');
      expect(controller.rolling, isTrue);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(controller.state.moveCount, 0);
    });

    testWidgets('Roll button then dice tap rolls exactly once (shared guard)', (
      tester,
    ) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await tester.tap(find.text('Roll dice'));
      await tester.tap(find.byType(DiceWidget));
      await tester.pump();

      expectIllegalFeedback(tester, controller, 'Wait for the dice to settle.');

      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(controller.state.moveCount, 0);
    });

    testWidgets('dice tap during the AI turn is ignored with feedback', (
      tester,
    ) async {
      final controller = await pumpGame(tester, dice: const [6, 2], vsAi: true);
      await reachAiTurn(tester, controller);
      expect(
        tester.widget<DiceWidget>(find.byType(DiceWidget)).enabled,
        isFalse,
      );
      expect(diceOpacity(tester), 0.45);
      expect(find.byTooltip('Tap to roll'), findsNothing);

      await tapDice(tester);

      expectIllegalFeedback(tester, controller, "It's not your turn yet.");
      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, 2);
      expect(controller.state.moveCount, 2);
      expect(controller.state.currentPlayerIndex, 1);
      expect(controller.legalMoves, isEmpty);
    });

    testWidgets('dice tap after rolling tells the player to move '
        'a token', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await roll(tester);
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));

      await tapDice(tester);

      expectIllegalFeedback(tester, controller, 'Choose a token to move.');
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(controller.state.moveCount, 0);
      expect(controller.rolling, isFalse);
    });
  });

  group('illegal board taps (M2.8)', () {
    testWidgets("tapping a token that can't move shows the SnackBar + status, "
        'state unchanged', (tester) async {
      final controller = await oneLegalMoveState(tester);
      // Yard token 1: stuck (needs a 6), while token 0 can move.
      await tapToken(
        tester,
        const BoardToken(id: '0:1', seatIndex: 0, stepsTaken: 0),
        tokensAt([1, 0, 0, 0], [0, 0, 0, 0]),
      );

      expectIllegalFeedback(tester, controller, "That token can't move now");
      expect(controller.state.moveCount, 1);
      expect(controller.displayedRoll, 2);
      expect(controller.legalMoves, hasLength(1));
      expect(controller.state.currentPlayerIndex, 0);
      expect(controller.state.phase, TurnPhase.awaitingMove);
    });

    testWidgets(
      "tapping an opponent's token is illegal feedback, state unchanged",
      (tester) async {
        final controller = await oneLegalMoveState(tester);
        await tapToken(
          tester,
          const BoardToken(
            id: '1:0',
            seatIndex: 1,
            stepsTaken: 0,
            colour: PlayerColour.green,
          ),
          tokensAt([1, 0, 0, 0], [0, 0, 0, 0]),
        );

        expectIllegalFeedback(tester, controller, "That token can't move now");
        expect(controller.state.moveCount, 1);
        expect(controller.displayedRoll, 2);
        expect(controller.legalMoves, hasLength(1));
        expect(controller.state.currentPlayerIndex, 0);
      },
    );

    testWidgets('tapping a token during the AI turn gives feedback, '
        'state unchanged', (tester) async {
      final controller = await pumpGame(tester, dice: const [6, 2], vsAi: true);
      await reachAiTurn(tester, controller);
      await tapToken(
        tester,
        const BoardToken(id: '0:1', seatIndex: 0, stepsTaken: 0),
        tokensAt([1, 0, 0, 0], [0, 0, 0, 0]),
      );

      expectIllegalFeedback(tester, controller, "That token can't move now");
      expect(controller.state.moveCount, 2);
      expect(controller.displayedRoll, 2);
      expect(controller.state.currentPlayerIndex, 1);
      expect(controller.rolling, isFalse);
    });

    testWidgets('tapping a token while rolling gives feedback and '
        'the roll still settles', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.rolling, isTrue);

      // Direct tap at the token's centre: no settle in between,
      // so the tumble is still running when the tap lands.
      final origin = tester.getTopLeft(boardFinder());
      final centre = boardTokenCenter(
        const BoardToken(id: '0:0', seatIndex: 0, stepsTaken: 0),
        boardSize,
        tokensAt([0, 0, 0, 0], [0, 0, 0, 0]),
      );
      await tester.tapAt(origin + centre);
      await tester.pump();

      expectIllegalFeedback(tester, controller, "That token can't move now");
      expect(controller.rolling, isTrue);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(controller.state.moveCount, 0);
    });

    testWidgets('tapping empty board area stays silent', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await roll(tester);
      expect(controller.displayedRoll, 6);

      // The board centre (home triangle): no token lives there.
      await tapBoardAt(tester, const Offset(240, 240));

      expect(find.byType(SnackBar), findsNothing);
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(controller.state.moveCount, 0);
      expect(controller.status, 'Player 1, choose a token to move.');
    });

    testWidgets('feedback does not consume the turn: a legal tap '
        'still moves afterwards', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await roll(tester);
      // A 6 makes all four releases legal, so the illegal tap is
      // an opponent's token, not a stuck yard token.
      expect(controller.legalMoves, hasLength(4));
      await tapToken(
        tester,
        const BoardToken(
          id: '1:0',
          seatIndex: 1,
          stepsTaken: 0,
          colour: PlayerColour.green,
        ),
        tokensAt([0, 0, 0, 0], [0, 0, 0, 0]),
      );
      expectIllegalFeedback(tester, controller, "That token can't move now");
      expect(controller.state.moveCount, 0);

      // The SnackBar is still up at the bottom of the screen; the
      // board above it is tappable, and the legal tap still moves.
      await tapToken(
        tester,
        const BoardToken(id: '0:0', seatIndex: 0, stepsTaken: 0),
        tokensAt([0, 0, 0, 0], [0, 0, 0, 0]),
      );
      expect(controller.state.moveCount, 1);
      expect(find.textContaining('rolls again'), findsOneWidget);
    });
  });
}
