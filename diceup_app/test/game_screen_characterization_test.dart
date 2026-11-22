import 'package:diceup/core/design_system/diceup_theme.dart';
import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/screens/game_screen.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_providers.dart';

/// Characterization tests for M3.2 (H-07).
///
/// These pin the game screen's observable behaviour EXACTLY as it is
/// before the `OfflineGameController` extraction: a scripted
/// human-vs-AI game asserting the exact sequence of statuses, turn
/// ownership, Roll-button enablement and AI pacing bounds. They were
/// written against the pre-extraction screen and must pass
/// identically after the extraction — if one fails after the move,
/// the extraction is wrong; the test is never weakened to fit it.
///
/// Dice script (2 players: Player 1 human, Player 2 AI easy):
/// * P1 rolls 6 → releases a token → extra turn (six).
/// * P1 rolls 1 → advances the token one step → turn passes to AI.
/// * AI rolls 6 → releases a token → extra turn → rolls 3 → moves.
/// * Back to P1, who rolls 6 again (sequence cycles) → moves again.
///
/// The AI pacing bounds (FR-40, D-31: 700–1,199 ms) are asserted as
/// bounds, not wall-clock: before 700 ms the AI has not started;
/// by 1,199 ms it has started (status leaves "Player 2, roll the
/// dice."). The AI turn is then driven by polling in 100 ms steps
/// ([pumpUntil]): each AI status persists at least 540 ms (a dice
/// tumble) or 700 ms (an AI step), so polling always observes it,
/// while a single long pump could skip a transient status when the
/// random AI delay is short. `pumpAndSettle` is never used for the
/// AI turn — it does not advance fake time through the AI timers.
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

  Future<void> pumpGame(WidgetTester tester) async {
    await tester.pumpWidget(
      withTestProviders(
        diceRoller: FixedDiceRoller(const [6, 1, 6, 3], cycle: true),
        child: MaterialApp(
          theme: DiceUpTheme.light(),
          home: const GameScreen(
            initialSetup: GameSetup(
              playerCount: 2,
              aiSeats: {1: AiDifficulty.easy},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> roll(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Roll dice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roll dice'));
    // The dice tumble is 6 x 90 ms = ~540 ms.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
  }

  Future<void> tapToken(
    WidgetTester tester,
    BoardToken token,
    List<BoardToken> allTokens,
  ) async {
    final board = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
    );
    expect(board, findsOneWidget);
    await tester.ensureVisible(board);
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(board);
    final centre = boardTokenCenter(token, boardSize, allTokens);
    await tester.tapAt(origin + centre);
    await tester.pump();
  }

  /// Advances fake time in 100 ms steps until [finder] matches
  /// [matcher] (or [maxMs] elapses, failing the test). Each AI
  /// status persists at least 540 ms (a dice tumble) or 700 ms (an
  /// AI step), so 100 ms polling always observes it — a single
  /// long pump could skip straight past a transient status when the
  /// random AI delay is short.
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder,
    Matcher matcher, {
    int maxMs = 5000,
  }) async {
    var waited = 0;
    while (finder.evaluate().isEmpty && waited < maxMs) {
      await tester.pump(const Duration(milliseconds: 100));
      waited += 100;
    }
    expect(finder, matcher);
  }

  testWidgets('scripted human-vs-AI game: exact status/turn sequence', (
    tester,
  ) async {
    await pumpGame(tester);

    // Fresh match: Player 1 to roll, Roll enabled.
    expect(
      find.textContaining('Player 1, roll the dice to start'),
      findsOneWidget,
    );
    expect(find.text('Roll dice'), findsOneWidget);

    // P1 rolls 6.
    await roll(tester);
    expect(
      find.textContaining('Player 1, choose a token to move'),
      findsOneWidget,
    );

    // Release the first yard token (yard slot 0 at (64, 64)).
    final board = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
    );
    await tester.ensureVisible(board);
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(board);
    await tester.tapAt(origin + const Offset(64, 64));
    await tester.pump();

    // A six grants an extra roll, so Player 1 rolls again.
    expect(find.textContaining('rolls again'), findsOneWidget);
    expect(
      find.textContaining('Player 1, roll the dice to start'),
      findsNothing,
    );

    // P1 rolls 1: exactly one legal move (token 0: step 1 -> 2).
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

    // The turn passes to the AI: Player 2 rolls next.
    expect(find.textContaining('Player 2, roll the dice'), findsOneWidget);

    // AI pacing (FR-40, D-31: 700-1,199 ms): before 700 ms the AI
    // has not started its turn.
    await tester.pump(const Duration(milliseconds: 699));
    expect(find.textContaining('Player 2, roll the dice'), findsOneWidget);
    // By 1,199 ms the AI has started: the dice are tumbling (the
    // status banner and the Roll button both read "Rolling…").
    await pumpUntil(tester, find.text('Rolling…'), findsNWidgets(2));

    // The AI's roll (6) settles: it has a token to move.
    await pumpUntil(
      tester,
      find.textContaining('Green (AI) rolled 6, choose a token to move'),
      findsOneWidget,
    );

    // The AI releases a token: a six means it rolls again.
    await pumpUntil(
      tester,
      find.textContaining('Green (AI) rolled a six and rolls again'),
      findsOneWidget,
    );

    // The AI rolls again (3) and it settles...
    await pumpUntil(
      tester,
      find.textContaining('Green (AI) rolled 3, choose a token to move'),
      findsOneWidget,
    );

    // ...and moves, passing the turn back to Player 1.
    await pumpUntil(
      tester,
      find.textContaining('Green (AI) moved a token. Player 1, roll the dice'),
      findsOneWidget,
    );
    expect(find.text('Roll dice'), findsOneWidget);

    // P1 rolls again (sequence cycles back to 6) and moves token 0
    // (step 2 -> 8). The AI's released token sits at step 4; which
    // index it is is the AI's random pick, and it never shares
    // Player 1's cell, so only its step matters for the tap centre.
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
        stepsTaken: 2,
        colour: PlayerColour.red,
      ),
      tokensAt(const [2, 0, 0, 0], const [4, 0, 0, 0]),
    );
    // A six again: extra roll for Player 1.
    expect(find.textContaining('rolls again'), findsOneWidget);
  });

  testWidgets('Roll button is disabled while the dice tumble', (tester) async {
    await pumpGame(tester);

    await tester.ensureVisible(find.text('Roll dice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roll dice'));
    // Mid-tumble the button reads "Rolling…" and cannot be tapped;
    // the status banner shows the same text, so there are two.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Rolling…'), findsNWidgets(2));
    expect(find.text('Roll dice'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Roll dice'), findsOneWidget);
  });
}
