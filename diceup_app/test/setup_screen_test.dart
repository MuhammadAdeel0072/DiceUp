import 'dart:async';

import 'package:diceup/core/design_system/diceup_components.dart';
import 'package:diceup/core/design_system/diceup_theme.dart';
import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/local/app_startup.dart';
import 'package:diceup/data/local/snapshot_recovery.dart';
import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/ruleset_config.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/presentation/app_dependencies_scope.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/game_screen.dart';
import 'package:diceup/presentation/screens/offline_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repositories/fakes/fakes.dart';
import 'test_providers.dart';

/// Setup-screen state retention (M2.1, L-01).
///
/// The setup screen used to initialise its state in
/// `didChangeDependencies` with no guard, so any dependency change
/// (rotation, keyboard, theme, navigating away and back) silently
/// reset the seat types and AI difficulties to the mode defaults,
/// wiping the user's selections. Initialisation now runs exactly once.
/// These tests change a selection, trigger a dependency change, and
/// assert the selection is retained.
void main() {
  /// The app shell used by these tests: a "go" button on `home` that
  /// navigates to the setup screen the way the mode selection screen
  /// does. Only the setup and game routes are generated here (the
  /// full route table cannot be used with a `home` widget — it already
  /// defines "/"). Re-pumping this widget with a different theme
  /// preserves the Navigator stack, which is what the theme-rebuild
  /// test relies on. [onGameSetup] captures the [GameSetup] the setup
  /// screen navigates with, so M2.2 tests can assert what reached
  /// the match without probing the game screen's paint output.
  Widget appWidget(
    OfflineMode mode, {
    ThemeData? theme,
    void Function(GameSetup)? onGameSetup,
  }) {
    // M3.3: the /game route builds a GameScreen, which reads the
    // provider graph — degraded startup here (no repositories), so
    // the match is playable but nothing is persisted.
    return withTestProviders(
      child: MaterialApp(
        theme: theme ?? DiceUpTheme.light(),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                Navigator.of(context)
                    .pushNamed(AppRoutes.offlineSetup, arguments: mode),
            child: const Text('go'),
          ),
        ),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.offlineSetup) {
            return MaterialPageRoute<void>(
              builder: (_) => const OfflineSetupScreen(),
              settings: settings,
            );
          }
          if (settings.name == AppRoutes.game) {
            if (settings.arguments is GameSetup) {
              onGameSetup?.call(settings.arguments as GameSetup);
            }
            return MaterialPageRoute<void>(
              builder: (_) => const GameScreen(),
              settings: settings,
            );
          }
          return null;
        },
      ),
    );
  }

  /// Pumps the app and navigates to the setup screen with [mode] as
  /// the route argument, so the screen reads its mode from the route
  /// arguments.
  Future<void> pumpSetup(
    WidgetTester tester,
    OfflineMode mode, {
    void Function(GameSetup)? onGameSetup,
  }) async {
    await tester.pumpWidget(appWidget(mode, onGameSetup: onGameSetup));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  /// In-memory dependencies for the prefill tests (same fakes as the
  /// M1.7 settings tests). [settingsOverride] replaces the settings
  /// repository — the loading-state test gates reads behind a
  /// [Completer] so the spinner is observable deterministically.
  AppDependencies fakeDeps(
    InMemoryStore store, {
    SettingsRepository? settingsOverride,
  }) => AppDependencies(
    matches: InMemoryLocalMatchRepository(store),
    statistics: InMemoryLocalStatisticsRepository(store),
    settings: settingsOverride ?? InMemorySettingsRepository(store),
    players: InMemoryLocalPlayerRepository(store),
    snapshots: InMemorySnapshotRepository(store),
  );

  StartupResult fakeStartup(AppDependencies deps) => StartupResult(
    dependencies: deps,
    settings: Map<String, String>.of(kDefaultSettings),
    snapshotOutcome: const NoSnapshot(),
    databaseRecovered: false,
  );

  /// The setup screen inside [AppDependenciesScope], so it can load
  /// and persist last-used options through the fake repositories.
  /// M3.3: also inside a [ProviderScope] with the fake startup, so
  /// the /game route's GameScreen reads the provider graph.
  Widget scopedAppWidget(
    OfflineMode mode,
    AppDependencies deps, {
    void Function(GameSetup)? onGameSetup,
  }) {
    final startup = fakeStartup(deps);
    return ProviderScope(
      overrides: [startupResultProvider.overrideWithValue(startup)],
      child: AppDependenciesScope(
        startup: startup,
        child: MaterialApp(
          theme: DiceUpTheme.light(),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  Navigator.of(context)
                      .pushNamed(AppRoutes.offlineSetup, arguments: mode),
              child: const Text('go'),
            ),
          ),
          onGenerateRoute: (settings) {
            if (settings.name == AppRoutes.offlineSetup) {
              return MaterialPageRoute<void>(
                builder: (_) => const OfflineSetupScreen(),
                settings: settings,
              );
            }
            if (settings.name == AppRoutes.game) {
              if (settings.arguments is GameSetup) {
                onGameSetup?.call(settings.arguments as GameSetup);
              }
              return MaterialPageRoute<void>(
                builder: (_) => const GameScreen(),
                settings: settings,
              );
            }
            return null;
          },
        ),
      ),
    );
  }

  Future<void> pumpScopedSetup(
    WidgetTester tester,
    OfflineMode mode,
    AppDependencies deps, {
    void Function(GameSetup)? onGameSetup,
  }) async {
    await tester.pumpWidget(
      scopedAppWidget(mode, deps, onGameSetup: onGameSetup),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  /// Toggles a ruleset switch by its title (M2.2). The ruleset card
  /// is the last list item. It is built — the setup ListView's
  /// cacheExtent keeps the whole bounded form in the tree — but a
  /// default finder skips it: sliver children outside the paint
  /// extent are "offstage" to finders, so the lookup needs
  /// `skipOffstage: false`. `ensureVisible` then scrolls it into
  /// view; no fixed drag is needed, and none is reliable against
  /// the seat cards' height, which changes with the player count
  /// (Stage 5: the fixed -600 drag passed only via route-push luck).
  Future<void> toggleRule(WidgetTester tester, String title) async {
    final tile = find.byWidgetPredicate(
      (widget) =>
          widget is SwitchListTile && (widget.title as Text?)?.data == title,
      skipOffstage: false,
    );
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  int selectedPlayerCount(WidgetTester tester) {
    final segments = tester.widget<SegmentedButton<int>>(
      find.byType(SegmentedButton<int>),
    );
    return segments.selected.single;
  }

  testWidgets('setup selections survive rotation (size change)', (
    tester,
  ) async {
    await pumpSetup(tester, OfflineMode.vsAi);

    // Change two selections away from the vs-AI defaults (2 players,
    // seats 2+ AI on Easy): 3 players, seat 2 difficulty Hard.
    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(selectedPlayerCount(tester), 3);

    // The M2.2 seat cards are taller (name field + colour picker),
    // so the difficulty dropdown sits below the fold in the 800x600
    // test viewport — scroll it into view first, as a real user
    // would. The assertions below are unchanged.
    final difficultyField = find
        .byType(DropdownButtonFormField<AiDifficulty>)
        .first;
    await tester.ensureVisible(difficultyField);
    await tester.pumpAndSettle();
    await tester.tap(difficultyField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hard'));
    await tester.pumpAndSettle();
    expect(find.text('Hard'), findsOneWidget);

    // Rotate: swap the viewport from landscape (800x600) to a
    // portrait phone size.
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpAndSettle();

    // Both selections retained — the pre-fix code reset the difficulty
    // to Easy (and the seat types to the mode defaults) here.
    expect(selectedPlayerCount(tester), 3);
    expect(find.text('Player 3'), findsWidgets);
    expect(find.text('Hard'), findsOneWidget);
    expect(find.text('AI difficulty'), findsNWidgets(2));
  });

  testWidgets('setup selections survive a dependency change (theme rebuild)', (
    tester,
  ) async {
    await pumpSetup(tester, OfflineMode.local);

    // In local mode every seat starts human. Flip seat 2 to AI.
    // (M2.2: the taller seat cards mean the second card is not even
    // built until the list scrolls — ListView.builder only builds
    // visible cards — so scroll first, then take the last 'AI'
    // segment, which is seat 2's whether or not seat 1's card is
    // still built. The assertions are unchanged.)
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final seat2Ai = find.text('AI').last;
    await tester.ensureVisible(seat2Ai);
    await tester.pumpAndSettle();
    await tester.tap(seat2Ai);
    await tester.pumpAndSettle();
    expect(find.text('AI difficulty'), findsOneWidget);

    // Rebuild the app with a different theme: the setup screen depends
    // on Theme (via Theme.of in build), so this deterministically calls
    // didChangeDependencies on its state. The Navigator stack (and the
    // setup screen's state) is preserved across the re-pump. Only the
    // primary colour changes — swapping the whole theme (light to dark)
    // trips an unrelated TextStyle.lerp assertion mid-transition.
    final altTheme = DiceUpTheme.light().copyWith(
      colorScheme: DiceUpTheme.light().colorScheme.copyWith(
        primary: Colors.deepPurple,
      ),
    );
    await tester.pumpWidget(appWidget(OfflineMode.local, theme: altTheme));
    await tester.pumpAndSettle();

    // Seat 2 is still AI — the pre-fix code reset it to human here.
    expect(find.text('AI difficulty'), findsOneWidget);
    expect(find.text('Local multiplayer'), findsOneWidget);
  });

  testWidgets('setup selections survive navigating away and back', (
    tester,
  ) async {
    await pumpSetup(tester, OfflineMode.vsAi);

    // Change two selections away from the vs-AI defaults: 4 players,
    // seat 2 difficulty Hard. (Seat types alone would not discriminate
    // here — vs-AI defaults already make seats 2+ AI — so the
    // difficulty change is the assertion that catches a reset.)
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    expect(selectedPlayerCount(tester), 4);

    // M2.2: scroll the difficulty dropdown into view first (see the
    // rotation test above). The assertions below are unchanged.
    final difficultyField = find
        .byType(DropdownButtonFormField<AiDifficulty>)
        .first;
    await tester.ensureVisible(difficultyField);
    await tester.pumpAndSettle();
    await tester.tap(difficultyField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hard'));
    await tester.pumpAndSettle();
    expect(find.text('Hard'), findsOneWidget);

    // Pushing another route makes this route non-current and popping
    // makes it current again; both change the ModalRoute dependency
    // the screen reads in didChangeDependencies.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('other screen')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('other screen'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();

    // Both selections retained — the pre-fix code reset the difficulty
    // to Easy (and re-read the mode) on each route change. Seat 4
    // starts below the fold, so scroll the seat list into view first
    // (ListView.builder only builds visible cards).
    expect(selectedPlayerCount(tester), 4);
    expect(find.text('Hard'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Player 4'), findsWidgets);
  });

  // -- M2.2: setup options (H-08, D-28, D-29) ---------------------------

  test('GameSetup defaults keep old call sites compiling', () {
    const setup = GameSetup(playerCount: 2, aiSeats: {1: AiDifficulty.easy});
    expect(setup.nameFor(0), 'Player 1');
    expect(setup.nameFor(1), 'Player 2');
    expect(setup.colourFor(0), PlayerColour.red);
    expect(setup.colourFor(1), PlayerColour.green);
    expect(setup.ruleset, const RulesetConfig());
    const custom = GameSetup(
      playerCount: 2,
      aiSeats: {},
      names: ['Ada', 'Bo'],
      colours: [PlayerColour.blue, PlayerColour.yellow],
      ruleset: RulesetConfig(releaseOnOne: true, exactFinish: false),
    );
    expect(custom.nameFor(0), 'Ada');
    expect(custom.colourFor(0), PlayerColour.blue);
    expect(custom.ruleset.releaseOnOne, isTrue);
    expect(custom.ruleset.exactFinish, isFalse);
  });

  testWidgets('custom names, colours and ruleset reach the match', (
    tester,
  ) async {
    GameSetup? captured;
    await pumpSetup(
      tester,
      OfflineMode.vsAi,
      onGameSetup: (setup) => captured = setup,
    );

    // Name seat 1 '  Ada  ' — trimmed to 'Ada'; seat 2 stays empty.
    await tester.enterText(
      find.byKey(const ValueKey('seat-0-name')),
      '  Ada  ',
    );
    await tester.pump();

    // Colour: give seat 1 blue (free — seat 2 holds green).
    final blueSwatch = find.byKey(const ValueKey('seat-0-colour-blue'));
    await tester.ensureVisible(blueSwatch);
    await tester.pumpAndSettle();
    await tester.tap(blueSwatch);
    await tester.pumpAndSettle();

    // Ruleset: release-on-1 on, exact finish off.
    await toggleRule(tester, 'Release on 1');
    await toggleRule(tester, 'Exact finish');

    await tester.tap(find.text('Start match'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(captured, isNotNull);
    expect(captured!.names, ['Ada', 'Player 2']);
    expect(captured!.colours, [PlayerColour.blue, PlayerColour.green]);
    expect(captured!.ruleset.releaseOnOne, isTrue);
    expect(captured!.ruleset.exactFinish, isFalse);
    // The turn banner plays with the custom name.
    expect(find.textContaining('Ada, roll the dice to start'), findsOneWidget);
  });

  testWidgets('colour picker offers 4, taken colours are rejected', (
    tester,
  ) async {
    GameSetup? captured;
    await pumpSetup(
      tester,
      OfflineMode.local,
      onGameSetup: (setup) => captured = setup,
    );

    // Seat 2 (index 1) holds green; all four swatches are offered.
    for (final colour in PlayerColour.values) {
      expect(
        find.byKey(ValueKey('seat-1-colour-${colour.name}')),
        findsOneWidget,
      );
    }

    // Red is taken by seat 1: the tap is rejected with a visible
    // error naming the holder — no silent ignore, no engine throw.
    final takenRed = find.byKey(const ValueKey('seat-1-colour-red'));
    await tester.ensureVisible(takenRed);
    await tester.pumpAndSettle();
    await tester.tap(takenRed);
    await tester.pump();
    expect(
      find.text('That colour is already taken by Player 1.'),
      findsOneWidget,
    );

    // The selection did not change: the match still starts with the
    // seat-default colours.
    await tester.tap(find.text('Start match'));
    await tester.pump();
    expect(captured, isNotNull);
    expect(captured!.colours, [PlayerColour.red, PlayerColour.green]);
  });

  testWidgets('a colour held by a seat outside the match can be picked', (
    tester,
  ) async {
    GameSetup? captured;
    await pumpSetup(
      tester,
      OfflineMode.local,
      onGameSetup: (setup) => captured = setup,
    );

    // Blue is held by seat 4, which is not in this 2-player match:
    // picking it swaps (seat 4 takes red), it is not rejected.
    final blueSwatch = find.byKey(const ValueKey('seat-0-colour-blue'));
    await tester.ensureVisible(blueSwatch);
    await tester.pumpAndSettle();
    await tester.tap(blueSwatch);
    await tester.pump();
    expect(find.textContaining('already taken'), findsNothing);

    // Growing to 4 players keeps every seat distinct.
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start match'));
    await tester.pump();
    expect(captured, isNotNull);
    expect(captured!.colours[0], PlayerColour.blue);
    expect(captured!.colours.toSet().length, 4);
  });

  testWidgets('name entry trims and defaults empty names to Player N', (
    tester,
  ) async {
    GameSetup? captured;
    await pumpSetup(
      tester,
      OfflineMode.vsAi,
      onGameSetup: (setup) => captured = setup,
    );
    await tester.enterText(
      find.byKey(const ValueKey('seat-0-name')),
      '  Ada  ',
    );
    await tester.pump();
    await tester.tap(find.text('Start match'));
    // Two pumps: the pushed game route only builds on the second
    // frame after the tap.
    await tester.pump();
    await tester.pump();
    expect(captured, isNotNull);
    expect(captured!.names, ['Ada', 'Player 2']);
    expect(find.textContaining('Ada, roll the dice to start'), findsOneWidget);
  });

  testWidgets('name entry blocks the 13th character while typing', (
    tester,
  ) async {
    await pumpSetup(tester, OfflineMode.vsAi);
    await tester.enterText(
      find.byKey(const ValueKey('seat-0-name')),
      'ABCDEFGHIJKLM',
    );
    await tester.pump();
    final field = tester.widget<DiceUpTextField>(
      find.byKey(const ValueKey('seat-0-name')),
    );
    expect(field.controller!.text, 'ABCDEFGHIJKL');
    expect(field.controller!.text.length, 12);
  });

  testWidgets('duplicate names are allowed', (tester) async {
    GameSetup? captured;
    await pumpSetup(
      tester,
      OfflineMode.local,
      onGameSetup: (setup) => captured = setup,
    );
    await tester.enterText(find.byKey(const ValueKey('seat-0-name')), 'Sam');
    await tester.enterText(find.byKey(const ValueKey('seat-1-name')), 'Sam');
    await tester.pump();
    await tester.tap(find.text('Start match'));
    // Two pumps: the pushed game route only builds on the second
    // frame after the tap.
    await tester.pump();
    await tester.pump();
    expect(captured, isNotNull);
    expect(captured!.names, ['Sam', 'Sam']);
    expect(find.textContaining('Sam, roll the dice to start'), findsOneWidget);
  });

  testWidgets('ruleset switches reach the match setup', (tester) async {
    GameSetup? captured;
    await pumpSetup(
      tester,
      OfflineMode.vsAi,
      onGameSetup: (setup) => captured = setup,
    );
    await toggleRule(tester, 'Third-six limit');
    await toggleRule(tester, 'Exact finish');
    await tester.tap(find.text('Start match'));
    await tester.pump();
    expect(captured, isNotNull);
    expect(captured!.ruleset.maxConsecutiveSixes, 0);
    expect(captured!.ruleset.exactFinish, isFalse);
    // Untouched switches keep the stock defaults.
    expect(captured!.ruleset.releaseOnOne, isFalse);
    expect(captured!.ruleset.extraTurnOnSix, isTrue);
  });

  testWidgets('release-on-1 ruleset releases a token on a 1', (tester) async {
    await tester.pumpWidget(
      withTestProviders(
        diceRoller: FixedDiceRoller([1]),
        child: MaterialApp(
          theme: DiceUpTheme.light(),
          home: const GameScreen(
            initialSetup: GameSetup(
              playerCount: 2,
              aiSeats: {},
              ruleset: RulesetConfig(releaseOnOne: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Roll dice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roll dice'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.textContaining('choose a token'), findsOneWidget);
  });

  testWidgets('default ruleset does not release a token on a 1', (
    tester,
  ) async {
    await tester.pumpWidget(
      withTestProviders(
        diceRoller: FixedDiceRoller([1]),
        child: MaterialApp(
          theme: DiceUpTheme.light(),
          home: const GameScreen(
            initialSetup: GameSetup(playerCount: 2, aiSeats: {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Roll dice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roll dice'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.textContaining('No legal move'), findsOneWidget);
  });

  // -- M2.2: last-used prefill --------------------------------------------

  testWidgets('last-used options prefill the form', (tester) async {
    final store = InMemoryStore();
    final deps = fakeDeps(store);
    await deps.settings.setSetting('last_mode', 'vs_ai');
    await deps.settings.setSetting('last_player_count', '3');
    await deps.settings.setSetting(
      'last_difficulties',
      '[null,"medium","hard",null]',
    );
    GameSetup? captured;
    await pumpScopedSetup(
      tester,
      OfflineMode.vsAi,
      deps,
      onGameSetup: (setup) => captured = setup,
    );

    // Player count prefilled; seat difficulties prefilled (seat 2
    // Medium, seat 3 Hard). The seat-3 card starts below the fold,
    // so scroll it into view to read its dropdown value.
    expect(selectedPlayerCount(tester), 3);
    expect(find.text('Medium'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Hard'), findsOneWidget);

    // The prefill reaches the match unchanged.
    await tester.tap(find.text('Start match'));
    await tester.pump();
    expect(captured, isNotNull);
    expect(captured!.playerCount, 3);
    expect(captured!.aiSeats, {1: AiDifficulty.medium, 2: AiDifficulty.hard});
  });

  testWidgets('prefill shows a loading state, never flashed defaults', (
    tester,
  ) async {
    final store = InMemoryStore();
    final inner = InMemorySettingsRepository(store);
    final gated = _GatedSettingsRepository(inner);
    final deps = fakeDeps(store, settingsOverride: gated);
    await inner.setSetting('last_mode', 'vs_ai');
    await inner.setSetting('last_player_count', '3');
    await inner.setSetting('last_difficulties', '[null,"medium","hard",null]');

    await tester.pumpWidget(scopedAppWidget(OfflineMode.vsAi, deps));
    await tester.tap(find.text('go'));
    // Two pumps: the pushed setup route only builds on the second
    // frame after the tap.
    await tester.pump();
    await tester.pump();
    // The load is gated: the form is not shown yet — the loading
    // state is, with no default player count on screen.
    expect(find.text('Loading your last setup…'), findsOneWidget);
    expect(find.text('Players'), findsNothing);

    gated.complete();
    await tester.pumpAndSettle();
    expect(find.text('Loading your last setup…'), findsNothing);
    expect(selectedPlayerCount(tester), 3);
  });

  testWidgets('prefill does not apply when the stored mode differs', (
    tester,
  ) async {
    final store = InMemoryStore();
    final deps = fakeDeps(store);
    await deps.settings.setSetting('last_mode', 'local_multiplayer');
    await deps.settings.setSetting('last_player_count', '4');
    await deps.settings.setSetting(
      'last_difficulties',
      '[null,"hard","hard","hard"]',
    );
    GameSetup? captured;
    await pumpScopedSetup(
      tester,
      OfflineMode.vsAi,
      deps,
      onGameSetup: (setup) => captured = setup,
    );

    // The stored options belong to a local match; this is a vs-AI
    // setup, so the mode defaults apply.
    expect(selectedPlayerCount(tester), 2);
    await tester.tap(find.text('Start match'));
    await tester.pump();
    expect(captured, isNotNull);
    expect(captured!.playerCount, 2);
    expect(captured!.aiSeats, {1: AiDifficulty.easy});
  });

  testWidgets('corrupt last-used values fall back to the defaults', (
    tester,
  ) async {
    final store = InMemoryStore();
    final deps = fakeDeps(store);
    await deps.settings.setSetting('last_mode', 'vs_ai');
    await deps.settings.setSetting('last_player_count', '9');
    await deps.settings.setSetting('last_difficulties', 'not json');
    GameSetup? captured;
    await pumpScopedSetup(
      tester,
      OfflineMode.vsAi,
      deps,
      onGameSetup: (setup) => captured = setup,
    );

    // No crash, no half-applied setup: the mode defaults apply.
    expect(selectedPlayerCount(tester), 2);
    await tester.tap(find.text('Start match'));
    await tester.pump();
    expect(captured, isNotNull);
    expect(captured!.playerCount, 2);
    expect(captured!.aiSeats, {1: AiDifficulty.easy});
  });

  testWidgets('an unknown stored difficulty is ignored wholesale', (
    tester,
  ) async {
    final store = InMemoryStore();
    final deps = fakeDeps(store);
    await deps.settings.setSetting('last_mode', 'vs_ai');
    await deps.settings.setSetting('last_player_count', '3');
    await deps.settings.setSetting(
      'last_difficulties',
      '[null,"impossible",null,null]',
    );
    await pumpScopedSetup(tester, OfflineMode.vsAi, deps);
    expect(selectedPlayerCount(tester), 3);
    expect(find.text('Medium'), findsNothing);
    expect(find.text('Hard'), findsNothing);
  });

  testWidgets('match start persists the chosen last-used options', (
    tester,
  ) async {
    final store = InMemoryStore();
    final deps = fakeDeps(store);
    await pumpScopedSetup(tester, OfflineMode.vsAi, deps);

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    final difficultyField = find
        .byType(DropdownButtonFormField<AiDifficulty>)
        .first;
    await tester.ensureVisible(difficultyField);
    await tester.pumpAndSettle();
    await tester.tap(difficultyField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hard'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start match'));
    await tester.pumpAndSettle();

    // Seat 1 AI-hard, seat 2 AI-easy (mode default), human seats null.
    expect(await deps.settings.getSetting('last_mode'), 'vs_ai');
    expect(await deps.settings.getSetting('last_player_count'), '3');
    expect(
      await deps.settings.getSetting('last_difficulties'),
      '[null,"hard","easy",null]',
    );
  });
}

/// Settings repository that gates reads behind a [Completer], so the
/// setup screen's loading state is observable deterministically: the
/// load cannot finish until [complete] is called. Writes pass
/// straight through.
class _GatedSettingsRepository implements SettingsRepository {
  _GatedSettingsRepository(this._inner);

  final SettingsRepository _inner;
  final Completer<void> _gate = Completer<void>();

  void complete() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<String?> getSetting(String key) async {
    await _gate.future;
    return _inner.getSetting(key);
  }

  @override
  Future<void> setSetting(String key, String value) =>
      _inner.setSetting(key, value);

  @override
  Future<Map<String, String>> getAllSettings() => _inner.getAllSettings();

  @override
  Future<void> resetToDefaults() => _inner.resetToDefaults();
}
