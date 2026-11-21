import 'package:diceup/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DiceUp boots to the home screen', (tester) async {
    await tester.pumpWidget(const DiceUpApp());

    // Splash shows briefly, then navigates to Home.
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump();

    expect(find.text('Ready to play?'), findsOneWidget);
    expect(find.text('Play Offline'), findsOneWidget);
    expect(find.text('Play Online'), findsOneWidget);
  });

  testWidgets('Home navigates to mode selection', (tester) async {
    await tester.pumpWidget(const DiceUpApp());
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump();

    await tester.tap(find.text('Play Offline'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a mode'), findsOneWidget);
    expect(find.text('Play vs AI'), findsOneWidget);
    expect(find.text('Local multiplayer'), findsOneWidget);
  });
}
