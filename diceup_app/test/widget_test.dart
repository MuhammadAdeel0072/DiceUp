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

  testWidgets('Home to match in 3 taps (NFR-07)', (tester) async {
    await tester.pumpWidget(const DiceUpApp());
    await tester.pumpAndSettle();

    // Tap 1: Home → mode selection.
    await tester.tap(find.text('Play Offline'));
    await tester.pumpAndSettle();

    // Tap 2: mode selection → setup.
    await tester.tap(find.text('Play vs AI'));
    await tester.pumpAndSettle();

    // In the test environment startup is degraded, so Home shows the
    // "saved data couldn't be loaded" snackbar — it lives in the
    // root ScaffoldMessenger, persists across routes, and covers the
    // Start button at the bottom of the 600 px viewport. Let its 4 s
    // duration elapse before tapping. (Pumps are not taps: the
    // navigation itself is still 3 taps.)
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Tap 3: setup → match. The setup screen opens on the mode
    // defaults here (no stored last-used options in the test
    // environment), so Start is available immediately.
    await tester.tap(find.text('Start match'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('roll the dice to start'), findsOneWidget);
  });
}
