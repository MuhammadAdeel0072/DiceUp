import 'dart:io';

import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/local/app_startup.dart';
import 'package:diceup/data/local/snapshot_recovery.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/presentation/app_dependencies_scope.dart';
import 'package:diceup/presentation/feedback/feedback_service.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/screens/game_screen.dart';
import 'package:diceup/presentation/screens/settings_screen.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'repositories/fakes/fakes.dart';

/// M1.7 tests (part 1): persisted settings and haptics (D-32).
/// Widget tests use the in-memory fakes; the restart test uses real
/// ffi SQLite on a temp file (plain `test()`, so no `runAsync`
/// wrapping is needed).
void main() {
  sqfliteFfiInit();

  AppDependencies fakeDeps(InMemoryStore store) => AppDependencies(
        matches: InMemoryLocalMatchRepository(store),
        statistics: InMemoryLocalStatisticsRepository(store),
        settings: InMemorySettingsRepository(store),
        players: InMemoryLocalPlayerRepository(store),
        snapshots: InMemorySnapshotRepository(store),
      );

  StartupResult fakeStartup(AppDependencies deps) => StartupResult(
        dependencies: deps,
        settings: Map<String, String>.of(kDefaultSettings),
        snapshotOutcome: const NoSnapshot(),
        databaseRecovered: false,
      );

  Widget scopedApp(AppDependencies deps, Widget home) {
    return AppDependenciesScope(
      startup: fakeStartup(deps),
      child: MaterialApp(home: home),
    );
  }

  SwitchListTile vibrationTile() => find
      .byWidgetPredicate(
        (widget) =>
            widget is SwitchListTile &&
            (widget.title as Text?)?.data == 'Vibration',
      )
      .evaluate()
      .single
      .widget as SwitchListTile;

  SwitchListTile soundTile() => find
      .byWidgetPredicate(
        (widget) =>
            widget is SwitchListTile &&
            (widget.title as Text?)?.data == 'Sound',
      )
      .evaluate()
      .single
      .widget as SwitchListTile;

  Future<void> tapFirstToken(WidgetTester tester) async {
    final board = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is LudoBoardPainter,
    );
    await tester.ensureVisible(board);
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(board);
    await tester.tapAt(origin + const Offset(64, 64));
    await tester.pump();
  }

  // -- Settings -----------------------------------------------------------

  group('settings screen', () {
    testWidgets('loads seeded values without flashing defaults first',
        (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await deps.settings.setSetting('vibration_enabled', '0');
      await deps.settings.setSetting('sound_volume', '42');

      await tester.pumpWidget(scopedApp(deps, const SettingsScreen()));
      // Still loading after the first frame: no defaults shown yet.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.pumpAndSettle();

      expect(vibrationTile().value, isFalse);
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        42,
      );
      // Sound is Coming Soon: disabled, with the honest note.
      expect(soundTile().onChanged, isNull);
      expect(
        find.text('Coming soon — sound does not play anything yet.'),
        findsOneWidget,
      );
    });

    testWidgets('toggling vibration persists (fresh repository re-read)',
        (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await tester.pumpWidget(scopedApp(deps, const SettingsScreen()));
      await tester.pumpAndSettle();
      expect(vibrationTile().value, isTrue);

      await tester.tap(find.byWidgetPredicate(
        (widget) =>
            widget is SwitchListTile &&
            (widget.title as Text?)?.data == 'Vibration',
      ));
      await tester.pumpAndSettle();

      expect(vibrationTile().value, isFalse);
      final fresh = InMemorySettingsRepository(store);
      expect(
        await fresh.getSetting('vibration_enabled'),
        '0',
      );
    });

    testWidgets('volume slider persists the dragged value', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await deps.settings.setSetting('sound_volume', '42');
      await tester.pumpWidget(scopedApp(deps, const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Slider), const Offset(200, 0));
      await tester.pumpAndSettle();

      final value =
          tester.widget<Slider>(find.byType(Slider)).value.round();
      expect(value, isNot(42));
      expect(
        await InMemorySettingsRepository(store)
            .getSetting('sound_volume'),
        '$value',
      );
    });

    testWidgets('reset to defaults restores D-25 defaults and clears '
        'last_*', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await deps.settings.setSetting('vibration_enabled', '0');
      await deps.settings.setSetting('sound_volume', '7');
      await deps.settings.setSetting('last_mode', 'vs_ai');
      await deps.settings.setSetting('last_player_count', '4');
      await tester.pumpWidget(scopedApp(deps, const SettingsScreen()));
      await tester.pumpAndSettle();
      expect(vibrationTile().value, isFalse);

      await tester.tap(find.text('Reset to defaults'));
      await tester.pumpAndSettle();
      expect(find.text('Reset settings?'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      final stored = await InMemorySettingsRepository(store)
          .getAllSettings();
      expect(stored['sound_enabled'], '1');
      expect(stored['vibration_enabled'], '1');
      expect(stored['sound_volume'], '100');
      expect(stored.containsKey('last_mode'), isFalse);
      expect(stored.containsKey('last_player_count'), isFalse);
      expect(vibrationTile().value, isTrue);
    });

    testWidgets('unavailable database shows the unavailable state',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SettingsScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Settings unavailable'), findsOneWidget);
    });

    test('settings survive restart (reopen the database, values intact)',
        () async {
      final dir = await Directory.systemTemp.createTemp('diceup_m17_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final path = '${dir.path}/diceup.db';
      final first = await initializeApp(
        factory: databaseFactoryFfi,
        path: path,
      );
      await first.dependencies!.settings
          .setSetting('vibration_enabled', '0');
      await first.dependencies!.settings.setSetting('sound_volume', '33');
      await first.dependencies!.database!.close();

      final second = await initializeApp(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(
        () async => second.dependencies?.database?.close(),
      );
      expect(second.settings['vibration_enabled'], '0');
      expect(second.settings['sound_volume'], '33');
      expect(second.settings['sound_enabled'], '1');
    });
  });

  // -- Haptics ------------------------------------------------------------

  group('haptics (D-32)', () {
    testWidgets('vibration enabled: a move triggers feedback exactly '
        'once', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final feedback = _FakeFeedbackService();
      await tester.pumpWidget(
        scopedApp(
          deps,
          GameScreen(
            initialSetup: const GameSetup(playerCount: 2, aiSeats: {}),
            diceRoller: FixedDiceRoller([6], cycle: true),
            feedbackService: feedback,
            vibrationEnabled: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tapFirstToken(tester);

      expect(feedback.calls, 1);
    });

    testWidgets('vibration disabled: a move triggers nothing',
        (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      final feedback = _FakeFeedbackService();
      await tester.pumpWidget(
        scopedApp(
          deps,
          GameScreen(
            initialSetup: const GameSetup(playerCount: 2, aiSeats: {}),
            diceRoller: FixedDiceRoller([6], cycle: true),
            feedbackService: feedback,
            vibrationEnabled: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tapFirstToken(tester);

      expect(feedback.calls, 0);
    });

    test('HapticFeedbackService calls HapticFeedback.lightImpact',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding
            .instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await const HapticFeedbackService().vibrateMove();

      // Flutter 3.50 sends lightImpact as 'HapticFeedback.vibrate'
      // with the type as its argument (see
      // packages/flutter/lib/src/services/haptic_feedback.dart).
      expect(calls, hasLength(1));
      expect(calls.single.method, 'HapticFeedback.vibrate');
      expect(calls.single.arguments, 'HapticFeedbackType.lightImpact');
    });
  });
}

/// A recording [FeedbackService] for haptics tests.
class _FakeFeedbackService implements FeedbackService {
  int calls = 0;

  @override
  Future<void> vibrateMove() async {
    calls++;
  }
}
