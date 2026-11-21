import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/local/app_startup.dart';
import 'package:diceup/data/local/snapshot_recovery.dart';
import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/main.dart';
import 'package:diceup/presentation/app_dependencies_scope.dart';
import 'package:diceup/presentation/screens/statistics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'repositories/fakes/fakes.dart';

/// M1.7 tests (part 2): the statistics screen (FR-32).
/// Widget tests use the in-memory fakes.
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

  /// The value shown beside [label] in a statistics row: the
  /// label's ancestor [Row] holds exactly one value text.
  void expectStat(String label, String value) {
    final row = find.ancestor(
      of: find.text(label),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: row, matching: find.text(value)),
      findsOneWidget,
      reason: 'expected $label to show $value',
    );
  }

  /// One completed local match. Seat 0 is always human (red);
  /// seat 1 is AI when [seat1IsAi] (vs-AI mode) else human (green).
  LocalMatch sampleMatch({
    required DateTime playedAt,
    required int winnerIndex,
    bool seat1IsAi = false,
  }) =>
      LocalMatch(
        playedAt: playedAt,
        mode: seat1IsAi
            ? LocalMatchMode.vsAi
            : LocalMatchMode.localMultiplayer,
        playerCount: 2,
        players: [
          LocalMatchPlayer(
            name: 'Player 1',
            colour: PlayerColour.red,
            isAi: false,
          ),
          LocalMatchPlayer(
            name: 'Player 2',
            colour: PlayerColour.green,
            isAi: seat1IsAi,
            difficulty: seat1IsAi ? AiDifficulty.easy : null,
          ),
        ],
        winnerIndex: winnerIndex,
        winnerName: 'Player ${winnerIndex + 1}',
        durationSeconds: 95,
        rulesetVersion: '1.0.0',
        createdAt: playedAt,
      );

  group('statistics screen', () {
    testWidgets('shows persisted lifetime statistics', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await deps.matches.recordMatch(
        sampleMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 0),
          winnerIndex: 0,
          seat1IsAi: true,
        ),
      );
      await deps.matches.recordMatch(
        sampleMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 30),
          winnerIndex: 1,
          seat1IsAi: true,
        ),
      );

      await tester.pumpWidget(scopedApp(deps, const StatisticsScreen()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();

      expectStat('Matches played', '2');
      expectStat('Human wins', '1');
      expectStat('Matches vs AI', '2');
      expectStat('Local matches', '0');
    });

    testWidgets('AI victories do not inflate human wins or the '
        'per-player breakdown', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await deps.matches.recordMatch(
        sampleMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 0),
          winnerIndex: 0,
        ),
      );
      await deps.matches.recordMatch(
        sampleMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 10),
          winnerIndex: 1,
          seat1IsAi: true,
        ),
      );
      await deps.matches.recordMatch(
        sampleMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 20),
          winnerIndex: 1,
          seat1IsAi: true,
        ),
      );

      await tester.pumpWidget(scopedApp(deps, const StatisticsScreen()));
      await tester.pumpAndSettle();

      expectStat('Matches played', '3');
      expectStat('Human wins', '1');
      expectStat('Matches vs AI', '2');
      expectStat('Local matches', '1');
      // The AI winner's seat never appears in the human breakdown.
      expect(find.text('Seat 1 · Red'), findsOneWidget);
      expect(find.text('Seat 2 · Green'), findsNothing);
    });

    testWidgets('per-player breakdown from retained history, labelled '
        'as the latest 500', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await deps.matches.recordMatch(
        sampleMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 0),
          winnerIndex: 0,
        ),
      );
      await deps.matches.recordMatch(
        sampleMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 10),
          winnerIndex: 0,
        ),
      );
      await deps.matches.recordMatch(
        sampleMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 20),
          winnerIndex: 1,
        ),
      );

      await tester.pumpWidget(scopedApp(deps, const StatisticsScreen()));
      await tester.pumpAndSettle();

      expect(
        find.text('Per-player wins from your latest 500 matches.'),
        findsOneWidget,
      );
      expectStat('Seat 1 · Red', '2');
      expectStat('Seat 2 · Green', '1');
    });

    testWidgets('lifetime totals remain correct after pruning '
        '(700 recorded, 500 retained)', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      for (var i = 0; i < 700; i++) {
        await deps.matches.recordMatch(
          sampleMatch(
            playedAt: DateTime.utc(2026, 11, 21, 12, 0),
            winnerIndex: 0,
          ),
        );
      }
      expect(await deps.matches.countMatches(), 500);

      await tester.pumpWidget(scopedApp(deps, const StatisticsScreen()));
      await tester.pumpAndSettle();

      // Lifetime totals come from the cached row, not the retained 500.
      expectStat('Matches played', '700');
      expectStat('Human wins', '700');
      expect(
        find.text('Per-player wins from your latest 500 matches.'),
        findsOneWidget,
      );
      // The breakdown counts the retained window only.
      expectStat('Seat 1 · Red', '500');
    });

    testWidgets('empty state shows zeros with an honest note, not an '
        'error', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await tester.pumpWidget(scopedApp(deps, const StatisticsScreen()));
      await tester.pumpAndSettle();

      expectStat('Matches played', '0');
      expectStat('Human wins', '0');
      expectStat('Matches vs AI', '0');
      expectStat('Local matches', '0');
      expect(find.textContaining('No matches yet'), findsOneWidget);
      expect(find.text('Wins by seat'), findsNothing);
    });

    testWidgets('load failure shows an error with retry', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      store.failNextCall();

      await tester.pumpWidget(scopedApp(deps, const StatisticsScreen()));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load statistics"), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expectStat('Matches played', '0');
    });

    testWidgets('unavailable database shows the unavailable state',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: StatisticsScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Statistics unavailable'), findsOneWidget);
    });

    testWidgets('navigation Home → Statistics → back', (tester) async {
      final store = InMemoryStore();
      final deps = fakeDeps(store);
      await tester.pumpWidget(DiceUpApp(startup: fakeStartup(deps)));
      await tester.pumpAndSettle();
      expect(find.text('Ready to play?'), findsOneWidget);

      await tester.tap(find.text('Statistics'));
      await tester.pumpAndSettle();
      expect(find.text('Matches played'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Ready to play?'), findsOneWidget);
    });
  });
}
