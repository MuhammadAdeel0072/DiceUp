import 'package:diceup/domain/repositories/local_statistics_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fakes.dart';
import 'repository_contract_test.dart'
    show RepositorySet, testMatch, testSeat;

/// Fake-specific behaviour that cannot be expressed through the
/// abstract interfaces alone: failure injection, deliberately
/// diverged statistics, the shared store, and the deterministic
/// clock. The shared contract suite lives in
/// `repository_contract_test.dart` and is re-run against SQLite in
/// M1.4; the tests here stay fake-only.
void main() {
  late InMemoryStore store;
  late RepositorySet repos;

  setUp(() {
    store = InMemoryStore();
    repos = RepositorySet(
      matches: InMemoryLocalMatchRepository(store),
      statistics: InMemoryLocalStatisticsRepository(store),
      settings: InMemorySettingsRepository(store),
      snapshots: InMemorySnapshotRepository(store),
      players: InMemoryLocalPlayerRepository(store),
    );
  });

  group('failure injection', () {
    test('the next call throws the injected failure', () async {
      store.failNextCall();
      await expectLater(
        () => repos.matches.recordMatch(testMatch()),
        throwsA(isA<InMemoryRepositoryFailure>()),
      );
    });

    test('the failure is one-shot: the call after succeeds', () async {
      store.failNextCall();
      await expectLater(
        () => repos.matches.recordMatch(testMatch()),
        throwsA(isA<InMemoryRepositoryFailure>()),
      );
      final recorded = await repos.matches.recordMatch(testMatch());
      expect(recorded.id, 1);
      expect(await repos.matches.countMatches(), 1);
    });

    test('a custom error surfaces as-is', () async {
      store.failNextCall(StateError('boom'));
      await expectLater(
        () => repos.settings.getSetting('sound_enabled'),
        throwsStateError,
      );
      expect(await repos.settings.getSetting('sound_enabled'), isNull);
    });

    test('the flag is shared: it fails any fake on the store',
        () async {
      store.failNextCall();
      await expectLater(
        () => repos.snapshots.loadSnapshot(kCurrentMatchKey),
        throwsA(isA<InMemoryRepositoryFailure>()),
      );
      expect(
        await repos.snapshots.hasSnapshot(kCurrentMatchKey),
        isFalse,
      );
    });

    test('a failed recordMatch leaves no partial state', () async {
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: '{"in":"progress"}',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      store.failNextCall();
      await expectLater(
        () => repos.matches.recordMatch(testMatch()),
        throwsA(isA<InMemoryRepositoryFailure>()),
      );
      // Nothing was inserted, statistics are untouched, and the
      // in-progress snapshot is still there — the four steps never
      // ran, so none of them partially applied.
      expect(await repos.matches.countMatches(), 0);
      final stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 0);
      expect(
        await repos.snapshots.hasSnapshot(kCurrentMatchKey),
        isTrue,
      );
    });
  });

  group('diverged statistics', () {
    test('recomputeFromHistory repairs deliberately diverged statistics',
        () async {
      await repos.matches.recordMatch(testMatch(winnerIndex: 0));
      await repos.matches.recordMatch(testMatch(winnerIndex: 1));
      // Diverge the cached row directly, as storage corruption would.
      store.statistics = LocalStatistics(
        matchesPlayed: 99,
        matchesWon: 99,
        matchesVsAi: 99,
        matchesLocal: 99,
        updatedAt: DateTime.utc(2020, 1, 1),
      );
      expect((await repos.statistics.getStatistics()).matchesPlayed, 99);
      final repaired = await repos.statistics.recomputeFromHistory();
      expect(repaired.matchesPlayed, 2);
      expect(repaired.matchesWon, 1);
      expect(repaired.matchesVsAi, 2);
      expect(repaired.matchesLocal, 0);
      expect(
        (await repos.statistics.getStatistics()).matchesPlayed,
        2,
      );
    });
  });

  group('shared store', () {
    test('match and statistics fakes see the same store', () async {
      await repos.matches.recordMatch(testMatch());
      expect(store.matches.length, 1);
      expect(store.statistics.matchesPlayed, 1);
      await repos.matches.clearHistory();
      expect(store.matches, isEmpty);
      expect(store.statistics.matchesPlayed, 0);
    });

    test('seats and snapshots live in the same store', () async {
      await repos.players.upsertSeat(testSeat());
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: '{}',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      expect(store.seats.length, 1);
      expect(store.snapshots.length, 1);
    });
  });

  group('deterministic clock', () {
    test('statistics updatedAt follows the injected clock', () async {
      final fixed = DateTime.utc(2026, 1, 1, 9, 30);
      final clockedStore = InMemoryStore(clock: () => fixed);
      final clockedMatches = InMemoryLocalMatchRepository(clockedStore);
      final clockedStats = InMemoryLocalStatisticsRepository(clockedStore);
      await clockedMatches.recordMatch(testMatch());
      final stats = await clockedStats.getStatistics();
      expect(stats.updatedAt, fixed);
    });
  });
}
