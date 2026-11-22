import 'package:diceup/core/design_system/diceup_theme.dart';
import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
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

/// M2.7 (CON-01, H-05): AnimationController-driven dice tumble,
/// token hop, legal-move pulse, RepaintBoundary, content-based
/// repaint, pause/dispose interaction — plus the M-16 UI pacing
/// test (FR-40, D-31).
///
/// The dice tumble is ~540 ms and ends on the engine-decided value;
/// the hop interpolates one token's rendered centre from its old
/// cell to its new one in ≤250 ms (engine state already final — the
/// animation never changes the game); the legal ring plays one
/// 1,200 ms pulse cycle each time legal moves newly appear (not a
/// continuous repeat — a running ticker would make
/// `pumpAndSettle` never terminate; see the game screen's
/// [_pulseController] note). The M3 upgrade (brief §4(C)) sequences a
/// multi-cell move one cell at a time; this hop crosses straight
/// from the old cell to the new one.
///
/// The AI timeout fallback (UC-03 E1, M-16) is an accepted risk,
/// NOT implemented here — see the plan's M2.7 record.
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

  /// Pumps a [GameScreen] under a [ProviderScope] with a fixed dice
  /// roller and degraded play (no repositories — nothing is
  /// persisted), and returns the provider-owned controller so tests
  /// can assert engine state alongside the animation.
  Future<OfflineGameController> pumpGame(
    WidgetTester tester, {
    required List<int> dice,
    bool vsAi = false,
  }) async {
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
    await tester.ensureVisible(find.text('Roll dice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roll dice'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
  }

  /// Taps the board at [offset] inside the board (origin at the
  /// board's top-left) and lets the move apply.
  Future<void> tapBoardAt(WidgetTester tester, Offset offset) async {
    await tester.ensureVisible(boardFinder());
    await tester.pumpAndSettle();
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

  /// Opens the pause menu with bounded pumps, never
  /// `pumpAndSettle`: while a roll is tumbling the turn banner
  /// shows a `CircularProgressIndicator` (an infinite animation),
  /// so settling would time out — and the dialog's entrance is a
  /// finite ~150 ms transition, covered by the 300 ms pump.
  Future<void> openPauseMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Paused'), findsOneWidget);
  }

  group('dice tumble (M2.7)', () {
    testWidgets('tumble runs ~540 ms: still tumbling at 500 ms, '
        'settled by 600 ms', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));

      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.rolling, isTrue);
      expect(find.text('Rolling…'), findsNWidgets(2));
      expect(diceFace(tester), inInclusiveRange(1, 6));

      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, 6);
      expect(diceFace(tester), 6);
      expect(find.textContaining('choose a token to move'), findsOneWidget);
    });

    testWidgets('tumble cycles faces and settles on the engine value, '
        'never a random one', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));

      // Five 90 ms steps across the tumble: the displayed face must
      // cycle (at least two distinct faces), never leave 1..6.
      final faces = <int>{};
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 90));
        faces.add(diceFace(tester));
      }
      expect(faces.every((face) => face >= 1 && face <= 6), isTrue);
      expect(faces.length, greaterThan(1));

      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, 6);
      expect(diceFace(tester), 6);
    });

    testWidgets('tumble settles on the engine value for a 3 as well', (
      tester,
    ) async {
      // A 3 from the yard has no legal move, so release a token
      // first (roll 6), then roll the 3 and move the released token.
      final controller = await pumpGame(tester, dice: const [6, 3]);
      await roll(tester);
      expect(controller.displayedRoll, 6);
      await tapBoardAt(tester, const Offset(64, 64));
      expect(controller.state.moveCount, 1);
      await tester.pump(const Duration(milliseconds: 300));
      await roll(tester);
      expect(controller.displayedRoll, 3);
      expect(diceFace(tester), 3);
      expect(find.textContaining('choose a token to move'), findsOneWidget);
    });

    testWidgets('input is locked during the tumble', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 200));

      // The Roll button is gone mid-tumble: the roll cannot be
      // re-tapped, and no move is applied (no legal moves exist
      // until the roll settles, so a board tap is a no-op too).
      expect(find.text('Roll dice'), findsNothing);
      expect(find.text('Rolling…'), findsNWidgets(2));
      expect(controller.state.moveCount, 0);
      expect(controller.rolling, isTrue);

      await tester.pump(const Duration(milliseconds: 340));
      expect(controller.displayedRoll, 6);
      expect(find.textContaining('choose a token to move'), findsOneWidget);
    });
  });

  group('token hop (M2.7)', () {
    testWidgets('hop interpolates from the old cell to the new one '
        'in ≤250 ms and ends at the engine position', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await roll(tester);
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));

      // Release the first yard token: yard slot 0 (64, 64) to the
      // red start cell (48, 208) on the 480 board.
      const fromCentre = Offset(64, 64);
      const toCentre = Offset(48, 208);
      await tapBoardAt(tester, fromCentre);
      expect(controller.state.moveCount, 1);
      expect(controller.state.players[0].tokens[0].stepsTaken, 1);

      // The hop starts at the old cell.
      var painter = boardPainter(tester);
      expect(painter.hopTokenId, '0:0');
      expect(painter.hopCenter, fromCentre);

      // Mid-hop the rendered centre is strictly between the cells
      // — the token is drawn mid-flight, never teleported.
      await tester.pump(const Duration(milliseconds: 125));
      painter = boardPainter(tester);
      final mid = painter.hopCenter!;
      expect(mid.dx, greaterThan(48));
      expect(mid.dx, lessThan(64));
      expect(mid.dy, greaterThan(64));
      expect(mid.dy, lessThan(208));
      // The animation never changes the game: the engine state is
      // identical before and after the hop frames.
      expect(controller.state.moveCount, 1);
      expect(controller.state.players[0].tokens[0].stepsTaken, 1);

      // By 250 ms the hop is done: no override, the token sits at
      // its engine position, and input unlocks (a six: roll again).
      await tester.pump(const Duration(milliseconds: 200));
      painter = boardPainter(tester);
      expect(painter.hopTokenId, isNull);
      expect(painter.hopCenter, isNull);
      expect(
        painter.tokens,
        contains(const BoardToken(id: '0:0', seatIndex: 0, stepsTaken: 1)),
      );
      expect(
        boardTokenCenter(
          const BoardToken(id: '0:0', seatIndex: 0, stepsTaken: 1),
          boardSize,
          painter.tokens,
        ),
        toCentre,
      );
      expect(find.text('Roll dice'), findsOneWidget);
    });

    testWidgets('no hop on restart: a fresh match starts with every '
        'token in the yard', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await roll(tester);
      await tapBoardAt(tester, const Offset(64, 64));
      expect(controller.state.moveCount, 1);
      await tester.pump(const Duration(milliseconds: 300));

      await openPauseMenu(tester);
      await tester.tap(find.text('Restart'));
      // Bounded pumps for the dialog transitions (this file's pause
      // flows use them uniformly; see openPauseMenu).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Restart match?'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(controller.state.moveCount, 0);
      expect(controller.state.players[0].tokens[0].stepsTaken, 0);
      final painter = boardPainter(tester);
      expect(painter.hopTokenId, isNull);
      expect(painter.hopCenter, isNull);
      expect(
        find.textContaining('Player 1, roll the dice to start'),
        findsOneWidget,
      );
    });

    testWidgets('pause mid-hop cancels the hop; resume does not '
        'restart it', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await roll(tester);
      await tapBoardAt(tester, const Offset(64, 64));
      expect(boardPainter(tester).hopTokenId, '0:0');

      await openPauseMenu(tester);
      expect(controller.isPaused, isTrue);
      // The hop is cancelled: the token is drawn at its engine
      // position (steps 1), not mid-flight.
      expect(boardPainter(tester).hopTokenId, isNull);
      expect(boardPainter(tester).hopCenter, isNull);
      expect(controller.state.players[0].tokens[0].stepsTaken, 1);

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(controller.isPaused, isFalse);
      expect(boardPainter(tester).hopTokenId, isNull);
      expect(find.text('Roll dice'), findsOneWidget);
    });
  });

  group('legal-move pulse + repaint (M2.7)', () {
    testWidgets('board is wrapped in a RepaintBoundary', (tester) async {
      await pumpGame(tester, dice: const [6]);
      // The nearest RepaintBoundary above the board's CustomPaint
      // is the board's own (the framework adds more higher up).
      final boardElement = tester.element(boardFinder());
      expect(
        boardElement.findAncestorWidgetOfExactType<RepaintBoundary>(),
        isNotNull,
      );
    });

    testWidgets('pulse is 0 with no legal moves and changes while '
        'moves are legal', (tester) async {
      await pumpGame(tester, dice: const [6]);
      expect(boardPainter(tester).pulse, 0.0);

      await roll(tester);
      await tester.pump(const Duration(milliseconds: 300));
      final first = boardPainter(tester).pulse;
      await tester.pump(const Duration(milliseconds: 300));
      final second = boardPainter(tester).pulse;
      expect(first, inInclusiveRange(0.0, 1.0));
      expect(second, inInclusiveRange(0.0, 1.0));
      expect(first, isNot(second));
    });

    testWidgets('pulse stops on pause', (tester) async {
      await pumpGame(tester, dice: const [6]);
      await roll(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(boardPainter(tester).pulse, isNot(0.0));

      await openPauseMenu(tester);
      expect(boardPainter(tester).pulse, 0.0);

      await tester.tap(find.text('Resume'));
      // Bounded pumps, not pumpAndSettle: settling would advance
      // fake time through the whole 1,200 ms pulse cycle the
      // resume restarts, and the pulse would read 0.0 again.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(boardPainter(tester).pulse, isNot(0.0));
    });
  });

  group('dice-tick repaint isolation (M3.8, NFR-02)', () {
    testWidgets('a dice-tumble tick does not rebuild the board', (
      tester,
    ) async {
      // M2.7 wired the dice tumble to its own AnimatedBuilder
      // around the DiceWidget and the board to a separate
      // AnimatedBuilder (pulse + hop) inside a RepaintBoundary —
      // so a tumble tick must rebuild the dice subtree only. The
      // board's AnimatedBuilder builds a fresh LudoBoardPainter
      // on every rebuild, so the painter instance is the rebuild
      // detector: identical across ticks means the board was not
      // rebuilt. The changing dice face proves ticks happened.
      final controller = await pumpGame(tester, dice: const [6]);
      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      // First tumble tick: the roll has started and the face is
      // cycling; capture the board painter as the baseline.
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.rolling, isTrue);
      final firstPainter = boardPainter(tester);
      final firstFace = diceFace(tester);
      // More ticks: the dice face advances...
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.rolling, isTrue);
      expect(diceFace(tester), isNot(firstFace));
      // ...but the board's CustomPaint is the very same widget.
      expect(identical(boardPainter(tester), firstPainter), isTrue);
      // Let the tumble settle so the test leaves a clean state.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(controller.rolling, isFalse);
    });
  });

  group('pause + dispose interaction (M2.7, M2.6)', () {
    testWidgets('pause mid-tumble freezes the displayed face; resume '
        'settles on the engine value', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.rolling, isTrue);
      final frozenFace = diceFace(tester);
      final frozenRoll = controller.displayedRoll;

      await openPauseMenu(tester);
      expect(controller.isPaused, isTrue);
      // Five seconds paused: nothing advances — the face is frozen
      // where the tumble stopped, and the controller's displayed
      // roll is unchanged too.
      await tester.pump(const Duration(seconds: 5));
      expect(controller.rolling, isTrue);
      expect(diceFace(tester), frozenFace);
      expect(controller.displayedRoll, frozenRoll);

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, 6);
      expect(diceFace(tester), 6);
      expect(find.textContaining('choose a token to move'), findsOneWidget);
    });

    testWidgets('restart mid-tumble starts a fresh match; no '
        'animation acts on the old match', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.rolling, isTrue);

      await openPauseMenu(tester);
      await tester.tap(find.text('Restart'));
      // Bounded pumps, not pumpAndSettle: the match is paused
      // mid-tumble, so the turn banner's spinner is still spinning
      // and settling would time out.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Restart match?'), findsOneWidget);
      await tester.tap(find.text('Restart'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, isNull);
      expect(controller.state.moveCount, 0);
      expect(diceFace(tester), -1);
      expect(
        find.textContaining('Player 1, roll the dice to start'),
        findsOneWidget,
      );
    });

    testWidgets('disposing the screen mid-tumble throws nothing '
        'afterwards', (tester) async {
      final controller = await pumpGame(tester, dice: const [6]);
      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.rolling, isTrue);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });
  });

  group('M-16 UI pacing (FR-40, D-31)', () {
    testWidgets('the AI acts within 700–1,199 ms of its turn '
        'starting', (tester) async {
      // Dice script: P1 rolls 6 (release), 1 (advance) — the turn
      // passes to the AI; the AI then rolls 6, releases, rolls 3.
      final controller = await pumpGame(
        tester,
        dice: const [6, 1, 6, 3],
        vsAi: true,
      );

      // P1 rolls 6 and releases the first yard token.
      await roll(tester);
      expect(
        find.textContaining('Player 1, choose a token to move'),
        findsOneWidget,
      );
      await tapBoardAt(tester, const Offset(64, 64));
      expect(find.textContaining('Six! Player 1 rolls again'), findsOneWidget);

      // P1 rolls 1 and advances that token one step: the turn
      // passes to the AI, and its pacing timer starts now.
      await roll(tester);
      expect(
        find.textContaining('Player 1, choose a token to move'),
        findsOneWidget,
      );
      await tapToken(
        tester,
        const BoardToken(
          id: '0:0',
          seatIndex: 0,
          stepsTaken: 1,
          colour: PlayerColour.red,
        ),
        tokensAt(const [1, 0, 0, 0], const [0, 0, 0, 0]),
      );
      expect(controller.state.currentPlayerIndex, 1);
      expect(find.textContaining('Player 2, roll the dice'), findsOneWidget);

      // Before 700 ms the AI has not acted.
      await tester.pump(const Duration(milliseconds: 699));
      expect(find.textContaining('Player 2, roll the dice'), findsOneWidget);
      expect(controller.rolling, isFalse);

      // The AI acts (starts its roll) within the band: step in
      // 100 ms increments from 699 ms and record when the status
      // leaves "Player 2, roll the dice".
      var elapsedMs = 699;
      while (find
          .textContaining('Player 2, roll the dice')
          .evaluate()
          .isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 100));
        elapsedMs += 100;
        expect(elapsedMs, lessThanOrEqualTo(1199));
      }
      expect(elapsedMs, greaterThanOrEqualTo(700));
      expect(elapsedMs, lessThanOrEqualTo(1199));
      expect(controller.rolling, isTrue);
      expect(find.text('Rolling…'), findsNWidgets(2));
    });
  });
}
