// Mode-selection online card (Phase 5, Stage 7): the online card
// routes signed-in users to the lobby and guests to login, and stays
// inert — never crashes — when the screen runs without a
// [ProviderScope] (bare layout / accessibility screens).
import 'package:diceup/l10n/app_localizations.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/mode_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_providers.dart';
import 'fakes.dart';

void main() {
  Widget modeApp(FakeAuthService service) {
    return ProviderScope(
      overrides: [
        startupResultProvider.overrideWithValue(testStartup(null)),
        authServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // The real app creates the auth provider at startup and its
        // restore completes before the user can reach this screen, so
        // the test reads it here too: without this the first tap
        // would see `restoring` and always land on login.
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(authStateProvider);
            return const ModeSelectionScreen();
          },
        ),
        routes: {
          AppRoutes.onlineLobby: (_) => const Text('lobby-screen'),
          AppRoutes.login: (_) => const Text('login-screen'),
        },
      ),
    );
  }

  Future<void> tapOnlineCard(WidgetTester tester) async {
    // The online card is the third card; make sure it is on-screen
    // at the 600 dp test height before tapping.
    final card = find.text('Online multiplayer');
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
  }

  testWidgets('signed-in tap on the online card opens the lobby', (
    tester,
  ) async {
    final service = FakeAuthService()
      ..restoreResult = FakeAuthService.cannedSession(verified: true);
    await tester.pumpWidget(modeApp(service));
    await tester.pumpAndSettle();
    await tapOnlineCard(tester);
    expect(find.text('lobby-screen'), findsOneWidget);
    expect(find.text('login-screen'), findsNothing);
  });

  testWidgets('guest tap on the online card opens login', (tester) async {
    await tester.pumpWidget(modeApp(FakeAuthService()));
    await tester.pumpAndSettle();
    await tapOnlineCard(tester);
    expect(find.text('login-screen'), findsOneWidget);
    expect(find.text('lobby-screen'), findsNothing);
  });

  testWidgets('tap without a ProviderScope does nothing, never crashes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ModeSelectionScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await tapOnlineCard(tester);
    // Still on the mode screen; no navigation happened.
    expect(find.text('Online multiplayer'), findsOneWidget);
    expect(find.text('login-screen'), findsNothing);
    expect(find.text('lobby-screen'), findsNothing);
  });
}
