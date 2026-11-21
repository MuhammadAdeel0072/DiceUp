import 'package:diceup/core/design_system/diceup_theme.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/screens/game_screen.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offline match: roll a 6 and release a token',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: DiceUpTheme.light(),
        home: GameScreen(
          initialSetup: const GameSetup(playerCount: 2, aiSeats: {}),
          diceRoller: FixedDiceRoller([6, 6, 6]),
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
      (widget) =>
          widget is CustomPaint && widget.painter is LudoBoardPainter,
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
}
