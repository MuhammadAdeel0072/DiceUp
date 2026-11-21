import 'package:diceup/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DiceUp boots to the home screen', (tester) async {
    await tester.pumpWidget(const DiceUpApp());

    // Startup is a real async load now (M1.6): wait for the splash
    // to finish and Home to appear.
    await tester.pumpAndSettle();

    expect(find.text('Ready to play?'), findsOneWidget);
    expect(find.text('Play Offline'), findsOneWidget);
    expect(find.text('Play Online'), findsOneWidget);
  });

  testWidgets('Home navigates to mode selection', (tester) async {
    await tester.pumpWidget(const DiceUpApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play Offline'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a mode'), findsOneWidget);
    expect(find.text('Play vs AI'), findsOneWidget);
    expect(find.text('Local multiplayer'), findsOneWidget);
  });
}
