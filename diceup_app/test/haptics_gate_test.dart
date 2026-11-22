import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/local/app_startup.dart';
import 'package:diceup/data/local/snapshot_recovery.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/move.dart';
import 'package:diceup/domain/offline_game_controller.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/domain/usecases/match_setup.dart';
import 'package:diceup/presentation/app_dependencies_scope.dart';
import 'package:diceup/presentation/feedback/feedback_service.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/game_screen.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'repositories/fakes/fakes.dart';

/// M2.11 tests: haptics end to end through the production wiring
/// (remediation plan §4 M2.11, §6 "Haptics (M2.11)").
///
/// M1.7 already built the [FeedbackService] abstraction and proved
/// its two halves separately — the fake records 1 call enabled /
/// 0 disabled, and the real service sends `lightImpact` on the
/// platform channel (`test/settings_haptics_test.dart`). What was
/// never proved is the two halves joined: the vibration toggle
/// driving the *platform channel* through the real service, and
/// the controller's "a failed haptic must not wedge a move"
/// claim. These tests close exactly that gap; nothing here
/// re-proves what the M1.7 tests already prove.
void main() {
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

  /// As in `test/settings_haptics_test.dart`, but with NO feedback
  /// override: the provider default — the real
  /// [HapticFeedbackService] — is the service under test.
  Widget scopedApp(
    AppDependencies deps, {
    DiceRoller? diceRoller,
    bool? vibrationEnabled,
  }) {
    final startup = fakeStartup(deps);
    return ProviderScope(
      overrides: [
        startupResultProvider.overrideWithValue(startup),
        if (diceRoller != null)
          diceRollerProvider.overrideWithValue(diceRoller),
        if (vibrationEnabled != null)
          vibrationEnabledProvider.overrideWithValue(vibrationEnabled),
      ],
      child: AppDependenciesScope(
        startup: startup,
        child: const MaterialApp(
          home: GameScreen(
            initialSetup: GameSetup(playerCount: 2, aiSeats: {}),
          ),
        ),
      ),
    );
  }

  Future<void> tapFirstToken(WidgetTester tester) async {
    final board = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is LudoBoardPainter,
    );
    await tester.ensureVisible(board);
    await tester.pumpAndSettle();
    final origin = tester.getTopLeft(board);
    await tester.tapAt(origin + const Offset(64, 64));
    await tester.pump();
  }

  /// Records every platform-channel call while the mock handler is
  /// installed; returns only the haptic ones, so unrelated channel
  /// traffic (if any) cannot fail the test.
  Future<List<MethodCall>> Function() installHapticRecorder() {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    return () async =>
        calls.where((call) => call.method == 'HapticFeedback.vibrate').toList();
  }

  group('haptics gate, end to end via the platform channel (M2.11)', () {
    testWidgets('vibration on: a move sends exactly one lightImpact', (
      tester,
    ) async {
      final haptics = installHapticRecorder();
      final store = InMemoryStore();
      await tester.pumpWidget(
        scopedApp(
          fakeDeps(store),
          diceRoller: FixedDiceRoller([6], cycle: true),
          vibrationEnabled: true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tapFirstToken(tester);
      await tester.pumpAndSettle();

      final sent = await haptics();
      expect(sent, hasLength(1));
      expect(sent.single.arguments, 'HapticFeedbackType.lightImpact');
    });

    testWidgets('vibration off: a move sends nothing', (tester) async {
      final haptics = installHapticRecorder();
      final store = InMemoryStore();
      await tester.pumpWidget(
        scopedApp(
          fakeDeps(store),
          diceRoller: FixedDiceRoller([6], cycle: true),
          vibrationEnabled: false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Roll dice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Roll dice'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tapFirstToken(tester);
      await tester.pumpAndSettle();

      expect(await haptics(), isEmpty);
    });
  });

  group('haptic failure (M2.11)', () {
    test('a throwing feedback hook never wedges a move', () async {
      final store = InMemoryStore();
      final snapshots = InMemorySnapshotRepository(store);
      final controller = OfflineGameController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
        matches: InMemoryLocalMatchRepository(store),
        settings: InMemorySettingsRepository(store),
        snapshots: snapshots,
        snapshotWriter: SnapshotSaver(snapshots),
        onMoveApplied: () => throw StateError('haptics boom'),
      );
      controller.startMatch(const MatchSetup(playerCount: 2, aiSeats: {}));
      controller.rollDice();
      // Real timers: the 6 x 90 ms tumble settles inside this wait.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(controller.displayedRoll, 6);

      // Must not throw, and the move must still land: a six earns
      // another roll, so the same player stays on.
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(controller.state.moveCount, 1);
      expect(controller.state.currentPlayerIndex, 0);
      expect(controller.status, 'Six! Player 1 rolls again.');
      controller.dispose();
    });
  });
}
