import 'package:diceup/core/design_system/diceup_theme.dart';
import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/local/app_startup.dart';
import 'package:diceup/data/local/snapshot_recovery.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/main.dart';
import 'package:diceup/presentation/app_dependencies_scope.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/settings_screen.dart';
import 'package:diceup/presentation/screens/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repositories/fakes/fakes.dart';

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

  // -- Honesty fixes (M2.10, M-12/M-13) --------------------------------
  //
  // One test per plan item. Items verified as already-correct by M1
  // are proved here too (no session-only note; splash performs a
  // real load) rather than re-implemented; the two doc-comment items
  // ("not hidden from the user", the false FR-42 claim) have no
  // runtime surface and were verified by grep — neither string
  // exists anywhere in lib/ or test/ — and are recorded in the plan,
  // not asserted here.
  group('honesty fixes (M2.10)', () {
    testWidgets('home subtitle no longer claims online play', (tester) async {
      await tester.pumpWidget(const DiceUpApp());
      await tester.pumpAndSettle();

      expect(
        find.text('Classic Ludo — offline, with friends.'),
        findsOneWidget,
      );
      expect(find.textContaining('or online'), findsNothing);
    });

    testWidgets('Play Online shows the login-prompt dialog, not a snackbar', (
      tester,
    ) async {
      await tester.pumpWidget(const DiceUpApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Play Online'));
      await tester.pump();

      // The M-13 dialog copy, verbatim; the old snackbar copy is gone.
      expect(find.text('Log in to play online with friends.'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(
        find.text('Online play arrives in Phase 5. Offline play is ready now.'),
        findsNothing,
      );

      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(find.text('Log in to play online with friends.'), findsNothing);
    });

    testWidgets('online mode card renders a chevron', (tester) async {
      await tester.pumpWidget(const DiceUpApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Play Offline'));
      await tester.pumpAndSettle();

      // Three mode rows, three chevrons: Play vs AI, Local
      // multiplayer, and — since Phase 5, Stage 7 — the online card,
      // which now navigates (lobby for signed-in users, login for
      // guests) instead of sitting inert.
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));
    });

    testWidgets('settings footer reads the pubspec version 0.1.0+1', (
      tester,
    ) async {
      final deps = _fakeDeps(InMemoryStore());
      await tester.pumpWidget(_scopedApp(deps, const SettingsScreen()));
      await tester.pumpAndSettle();

      // The footer is the last item of the settings ListView: at
      // 800x600 it sits below the fold (the redesign, Stage 3C,
      // made the screen taller with section headings), so a default
      // finder skips it as offstage. It is built — scroll it into
      // view first, as a real user would; the assertions below are
      // unchanged.
      final footer = find.textContaining('DiceUp 0.1.0+1', skipOffstage: false);
      await tester.ensureVisible(footer);
      await tester.pumpAndSettle();

      expect(find.textContaining('DiceUp 0.1.0+1'), findsOneWidget);
      expect(find.textContaining('DiceUp 1.0.0'), findsNothing);
    });

    testWidgets('no session-only note: settings persist (M1.7)', (
      tester,
    ) async {
      // The M2.10 plan item asked for a "settings apply for this
      // session" note until M1 landed. M1.6/M1.7 landed persistence,
      // so the note must NOT exist — the screen shows real persisted
      // values instead (persistence itself is proved by the M1.7
      // tests in test/settings_haptics_test.dart).
      final deps = _fakeDeps(InMemoryStore());
      await deps.settings.setSetting('vibration_enabled', '0');
      await tester.pumpWidget(_scopedApp(deps, const SettingsScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('reset when the app closes'), findsNothing);
      expect(find.textContaining('this session'), findsNothing);
    });

    testWidgets('splash styles through the typography tokens', (tester) async {
      final deps = _fakeDeps(InMemoryStore());
      await tester.pumpWidget(
        MaterialApp(
          theme: DiceUpTheme.light(),
          // The ready splash navigates to /home after 500 ms; a stub
          // route lets the timer fire cleanly at the end of the test.
          routes: <String, WidgetBuilder>{'/home': (_) => const SizedBox()},
          home: SplashScreen(startup: _fakeStartup(deps)),
        ),
      );
      await tester.pump();

      // Title = displayLarge (32 sp, w800), tagline = bodyLarge
      // (16 sp) — the raw 44 sp / 16 sp TextStyles are gone.
      final title = tester.widget<Text>(find.text('DiceUp'));
      expect(title.style?.fontSize, 32);
      expect(title.style?.fontWeight, FontWeight.w800);
      expect(title.style?.color, Colors.white);
      final tagline = tester.widget<Text>(find.text('Multiplayer Ludo'));
      expect(tagline.style?.fontSize, 16);

      // Drain the 500 ms navigation timer so no timer is pending
      // at teardown.
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('splash spinner stays through the brand moment (M2.10)', (
      tester,
    ) async {
      // DEFERRED, not fixed: the spinner should show only while the
      // real load runs, but removing it from the ready splash broke
      // 26 pumpAndSettle boot tests — with nothing animating, the
      // harness returns before the 500 ms navigation timer fires
      // (probe: ready splash shown, spinner absent, Home never
      // reached). Removing it needs the boot tests' pumpAndSettle
      // reliance reworked first. This test locks the current
      // behaviour in so a future removal re-breaks loudly, not
      // silently. The real load itself (M1.6) is proved by the boot
      // test above.
      final deps = _fakeDeps(InMemoryStore());

      // Still initialising: a real load is in progress, so the
      // spinner is honest.
      await tester.pumpWidget(
        MaterialApp(theme: DiceUpTheme.light(), home: const SplashScreen()),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Load complete: the spinner stays through the 500 ms brand
      // moment (the follow-up above).
      await tester.pumpWidget(
        MaterialApp(
          theme: DiceUpTheme.light(),
          // Stub route so the ready splash's 500 ms navigation
          // timer can fire cleanly at the end of the test.
          routes: <String, WidgetBuilder>{'/home': (_) => const SizedBox()},
          home: SplashScreen(startup: _fakeStartup(deps)),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Drain the 500 ms navigation timer so no timer is pending
      // at teardown.
      await tester.pump(const Duration(milliseconds: 600));
    });
  });
}

AppDependencies _fakeDeps(InMemoryStore store) => AppDependencies(
  matches: InMemoryLocalMatchRepository(store),
  statistics: InMemoryLocalStatisticsRepository(store),
  settings: InMemorySettingsRepository(store),
  players: InMemoryLocalPlayerRepository(store),
  snapshots: InMemorySnapshotRepository(store),
);

StartupResult _fakeStartup(AppDependencies deps) => StartupResult(
  dependencies: deps,
  settings: Map<String, String>.of(kDefaultSettings),
  snapshotOutcome: const NoSnapshot(),
  databaseRecovered: false,
);

/// A single-scope test app (M3.3) with the fake startup, so screens
/// that read repositories through [AppDependenciesScope] work.
Widget _scopedApp(AppDependencies deps, Widget home) {
  final startup = _fakeStartup(deps);
  return ProviderScope(
    overrides: [startupResultProvider.overrideWithValue(startup)],
    child: AppDependenciesScope(
      startup: startup,
      child: MaterialApp(theme: DiceUpTheme.light(), home: home),
    ),
  );
}
