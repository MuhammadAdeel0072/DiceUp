import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/local_player_repository.dart';
import 'package:diceup/domain/repositories/local_statistics_repository.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fakes.dart';

/// The five repositories under test, built together from one backing
/// store (M1.2 fakes) or one database (M1.4 SQLite).
class RepositorySet {
  RepositorySet({
    required this.matches,
    required this.statistics,
    required this.settings,
    required this.snapshots,
    required this.players,
  });

  final LocalMatchRepository matches;
  final LocalStatisticsRepository statistics;
  final SettingsRepository settings;
  final SnapshotRepository snapshots;
  final LocalPlayerRepository players;
}

/// Builds a [LocalMatch] for tests: 2 seats (a human and an easy AI),
/// fixed timestamps so tests stay deterministic.
LocalMatch testMatch({
  DateTime? playedAt,
  LocalMatchMode mode = LocalMatchMode.vsAi,
  int? winnerIndex = 0,
  List<LocalMatchPlayer>? players,
  int? durationSeconds,
}) {
  final seats = players ??
      [
        LocalMatchPlayer(
          name: 'Player 1',
          colour: PlayerColour.red,
          isAi: false,
        ),
        LocalMatchPlayer(
          name: 'CPU',
          colour: PlayerColour.green,
          isAi: true,
          difficulty: AiDifficulty.easy,
        ),
      ];
  return LocalMatch(
    playedAt: playedAt ?? DateTime.utc(2026, 11, 21, 12, 0),
    mode: mode,
    playerCount: seats.length,
    players: seats,
    winnerIndex: winnerIndex,
    winnerName: winnerIndex == null ? null : seats[winnerIndex].name,
    durationSeconds: durationSeconds,
    rulesetVersion: '1.0.0',
    createdAt: DateTime.utc(2026, 11, 21, 12, 0),
  );
}

/// Builds a [LocalPlayerSeat] for tests.
LocalPlayerSeat testSeat({
  int? id,
  String displayName = 'Player 1',
  PlayerColour colour = PlayerColour.red,
  bool isAi = false,
  AiDifficulty? difficulty,
  DateTime? lastUsedAt,
}) =>
    LocalPlayerSeat(
      id: id,
      displayName: displayName,
      colour: colour,
      isAi: isAi,
      difficulty: difficulty,
      lastUsedAt: lastUsedAt,
    );

/// Registers the shared repository contract tests against repositories
/// built by [create] — a fresh set per test.
///
/// M1.4 re-runs this SAME suite against the SQLite implementations by
/// importing this file and calling [defineRepositoryContractTests]
/// with a SQLite-backed factory. The tests here use ONLY the abstract
/// interfaces (plus the value objects' own invariants): anything that
/// needs fake internals — failure injection, deliberately diverged
/// statistics — lives in `in_memory_fakes_test.dart`, not here.
void defineRepositoryContractTests(RepositorySet Function() create) {
  late RepositorySet repos;

  setUp(() {
    repos = create();
  });

  group('value object invariants', () {
    test('a match needs 2–4 players', () {
      expect(
        () => testMatch(
          players: [
            LocalMatchPlayer(
              name: 'Only',
              colour: PlayerColour.red,
              isAi: false,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('a match playerCount must equal its players', () {
      expect(
        () => LocalMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 0),
          mode: LocalMatchMode.vsAi,
          playerCount: 3,
          players: [
            LocalMatchPlayer(
              name: 'A',
              colour: PlayerColour.red,
              isAi: false,
            ),
            LocalMatchPlayer(
              name: 'B',
              colour: PlayerColour.green,
              isAi: false,
            ),
          ],
          rulesetVersion: '1.0.0',
          createdAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
        throwsArgumentError,
      );
    });

    test('a winner index out of range is rejected', () {
      expect(() => testMatch(winnerIndex: 2), throwsArgumentError);
    });

    test('a winner name without a winner index is rejected', () {
      expect(
        () => LocalMatch(
          playedAt: DateTime.utc(2026, 11, 21, 12, 0),
          mode: LocalMatchMode.vsAi,
          playerCount: 2,
          players: [
            LocalMatchPlayer(
              name: 'A',
              colour: PlayerColour.red,
              isAi: false,
            ),
            LocalMatchPlayer(
              name: 'B',
              colour: PlayerColour.green,
              isAi: false,
            ),
          ],
          winnerName: 'A',
          rulesetVersion: '1.0.0',
          createdAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
        throwsArgumentError,
      );
    });

    test('a human seat has no difficulty', () {
      expect(
        () => LocalMatchPlayer(
          name: 'A',
          colour: PlayerColour.red,
          isAi: false,
          difficulty: AiDifficulty.easy,
        ),
        throwsArgumentError,
      );
    });

    test('a seat needs a non-empty display name', () {
      expect(
        () => testSeat(displayName: '   '),
        throwsArgumentError,
      );
    });

    test('a snapshot needs a non-empty key and JSON', () {
      expect(
        () => SavedSnapshot(
          matchKey: '',
          snapshotJson: '{}',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: '',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
        throwsArgumentError,
      );
    });

    test('statistics counts cannot be negative', () {
      expect(
        () => LocalStatistics(
          matchesPlayed: -1,
          matchesWon: 0,
          matchesVsAi: 0,
          matchesLocal: 0,
          updatedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
        throwsArgumentError,
      );
    });

    test('match mode labels round-trip; unknown labels reject', () {
      expect(LocalMatchMode.vsAi.label, 'vs_ai');
      expect(LocalMatchMode.localMultiplayer.label, 'local_multiplayer');
      expect(
        LocalMatchMode.fromLabel('vs_ai'),
        LocalMatchMode.vsAi,
      );
      expect(
        LocalMatchMode.fromLabel('local_multiplayer'),
        LocalMatchMode.localMultiplayer,
      );
      expect(
        () => LocalMatchMode.fromLabel('online'),
        throwsFormatException,
      );
    });
  });

  group('snapshot repository', () {
    test('save then load returns the same snapshot', () async {
      final snapshot = SavedSnapshot(
        matchKey: kCurrentMatchKey,
        snapshotJson: '{"formatVersion":1}',
        savedAt: DateTime.utc(2026, 11, 21, 12, 0),
      );
      await repos.snapshots.saveSnapshot(snapshot);
      expect(await repos.snapshots.loadSnapshot(kCurrentMatchKey),
          snapshot);
      expect(await repos.snapshots.hasSnapshot(kCurrentMatchKey), isTrue);
    });

    test('load returns null and has is false when absent', () async {
      expect(await repos.snapshots.loadSnapshot(kCurrentMatchKey), isNull);
      expect(await repos.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
    });

    test('delete removes the snapshot', () async {
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: '{}',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      await repos.snapshots.deleteSnapshot(kCurrentMatchKey);
      expect(await repos.snapshots.loadSnapshot(kCurrentMatchKey), isNull);
      expect(await repos.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
    });

    test('delete is a no-op when absent', () async {
      await repos.snapshots.deleteSnapshot(kCurrentMatchKey);
      expect(await repos.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
    });

    test('save upserts: the same key replaces the snapshot', () async {
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: '{"v":1}',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: '{"v":2}',
          savedAt: DateTime.utc(2026, 11, 21, 12, 30),
        ),
      );
      final loaded = await repos.snapshots.loadSnapshot(kCurrentMatchKey);
      expect(loaded?.snapshotJson, '{"v":2}');
    });

    test('snapshots under different keys are independent', () async {
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: 'a',
          snapshotJson: '{"k":"a"}',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: 'b',
          snapshotJson: '{"k":"b"}',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      expect(
        (await repos.snapshots.loadSnapshot('a'))?.snapshotJson,
        '{"k":"a"}',
      );
      expect(
        (await repos.snapshots.loadSnapshot('b'))?.snapshotJson,
        '{"k":"b"}',
      );
    });
  });

  group('match repository', () {
    test('record assigns incrementing ids starting at 1', () async {
      final first = await repos.matches.recordMatch(testMatch());
      final second = await repos.matches.recordMatch(testMatch());
      expect(first.id, 1);
      expect(second.id, 2);
    });

    test('getMatch returns the recorded match; unknown id is null',
        () async {
      final recorded = await repos.matches.recordMatch(testMatch());
      expect(await repos.matches.getMatch(recorded.id!), recorded);
      expect(await repos.matches.getMatch(999), isNull);
    });

    test('countMatches counts recorded matches', () async {
      expect(await repos.matches.countMatches(), 0);
      await repos.matches.recordMatch(testMatch());
      await repos.matches.recordMatch(testMatch());
      expect(await repos.matches.countMatches(), 2);
    });

    test('listMatches is reverse-chronological by playedAt', () async {
      final old = await repos.matches.recordMatch(
        testMatch(playedAt: DateTime.utc(2026, 11, 20, 12, 0)),
      );
      final mid = await repos.matches.recordMatch(
        testMatch(playedAt: DateTime.utc(2026, 11, 21, 12, 0)),
      );
      final recent = await repos.matches.recordMatch(
        testMatch(playedAt: DateTime.utc(2026, 11, 22, 12, 0)),
      );
      final listed = await repos.matches.listMatches();
      expect(
        listed.map((m) => m.id),
        [recent.id, mid.id, old.id],
      );
    });

    test('listMatches breaks playedAt ties by id descending', () async {
      final first = await repos.matches.recordMatch(testMatch());
      final second = await repos.matches.recordMatch(testMatch());
      final listed = await repos.matches.listMatches();
      expect(listed.map((m) => m.id), [second.id, first.id]);
    });

    test('reads on an empty repository', () async {
      expect(await repos.matches.listMatches(), isEmpty);
      expect(await repos.matches.countMatches(), 0);
      expect(await repos.matches.getMatch(1), isNull);
    });

    test('recordMatch updates statistics (D-24)', () async {
      // Human win vs AI, AI win vs AI, human win local.
      await repos.matches.recordMatch(testMatch(winnerIndex: 0));
      await repos.matches.recordMatch(testMatch(winnerIndex: 1));
      await repos.matches.recordMatch(
        testMatch(mode: LocalMatchMode.localMultiplayer, winnerIndex: 0),
      );
      final stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 3);
      expect(stats.matchesVsAi, 2);
      expect(stats.matchesLocal, 1);
      // Only the two human wins count — the AI win does not.
      expect(stats.matchesWon, 2);
    });

    test('recordMatch deletes the in-progress snapshot only', () async {
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: '{"in":"progress"}',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: 'other',
          snapshotJson: '{"other":true}',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      await repos.matches.recordMatch(testMatch());
      expect(await repos.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      expect(await repos.snapshots.hasSnapshot('other'), isTrue);
    });

    test('recordMatch prunes history beyond 500 (NFR-36)', () async {
      final base = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < kMaxLocalMatches + 1; i++) {
        await repos.matches.recordMatch(
          testMatch(playedAt: base.add(Duration(minutes: i))),
        );
      }
      expect(await repos.matches.countMatches(), kMaxLocalMatches);
      // The oldest match (id 1, earliest playedAt) is gone.
      expect(await repos.matches.getMatch(1), isNull);
      // The newest match survived.
      expect(
        await repos.matches.getMatch(kMaxLocalMatches + 1),
        isNotNull,
      );
      final listed = await repos.matches.listMatches();
      expect(listed.length, kMaxLocalMatches);
      expect(listed.first.id, kMaxLocalMatches + 1);
    });

    test('recordMatch preserves lifetime statistics beyond 500 (D-24, NFR-36)',
        () async {
      // The first 200 matches are local-mode human wins; the rest are
      // vs-AI matches the AI wins. If statistics were derived from
      // the retained 500, the 200 pruned human wins and local matches
      // would vanish from the totals — and the lifetime total would
      // freeze at 501 once pruning starts.
      final base = DateTime.utc(2026, 1, 1);
      final localHumanWin = [
        LocalMatchPlayer(
          name: 'Player 1',
          colour: PlayerColour.red,
          isAi: false,
        ),
        LocalMatchPlayer(
          name: 'Player 2',
          colour: PlayerColour.green,
          isAi: false,
        ),
      ];
      for (var i = 0; i < 200; i++) {
        await repos.matches.recordMatch(
          testMatch(
            playedAt: base.add(Duration(minutes: i)),
            mode: LocalMatchMode.localMultiplayer,
            winnerIndex: 0,
            players: localHumanWin,
          ),
        );
      }
      var stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 200);
      expect(stats.matchesWon, 200);
      expect(stats.matchesLocal, 200);
      expect(stats.matchesVsAi, 0);

      // Records 201–501: vs-AI matches the AI wins.
      for (var i = 200; i < 501; i++) {
        await repos.matches.recordMatch(
          testMatch(
            playedAt: base.add(Duration(minutes: i)),
            winnerIndex: 1, // the AI seat wins.
          ),
        );
      }
      // 501 records, 500 retained — the lifetime total is 501.
      expect(await repos.matches.countMatches(), kMaxLocalMatches);
      stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 501);
      expect(stats.matchesWon, 200);
      expect(stats.matchesVsAi, 301);
      expect(stats.matchesLocal, 200);

      // One more record: deriving from the retained list would freeze
      // the lifetime total at 501 here.
      await repos.matches.recordMatch(
        testMatch(
          playedAt: base.add(const Duration(minutes: 501)),
          winnerIndex: 1,
        ),
      );
      stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 502);
      expect(stats.matchesWon, 200);

      // Up to 700 records: the count stays capped, the lifetime
      // totals stay exact.
      for (var i = 502; i < 700; i++) {
        await repos.matches.recordMatch(
          testMatch(
            playedAt: base.add(Duration(minutes: i)),
            winnerIndex: 1,
          ),
        );
      }
      expect(await repos.matches.countMatches(), kMaxLocalMatches);
      expect(await repos.matches.getMatch(1), isNull);
      expect((await repos.matches.listMatches()).first.id, 700);
      stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 700);
      expect(stats.matchesWon, 200);
      expect(stats.matchesVsAi, 500);
      expect(stats.matchesLocal, 200);
    });

    test('clearHistory removes matches and resets statistics', () async {
      await repos.matches.recordMatch(testMatch());
      await repos.matches.recordMatch(
        testMatch(mode: LocalMatchMode.localMultiplayer),
      );
      expect(await repos.matches.countMatches(), 2);
      await repos.matches.clearHistory();
      expect(await repos.matches.countMatches(), 0);
      expect(await repos.matches.listMatches(), isEmpty);
      expect(await repos.matches.getMatch(1), isNull);
      final stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 0);
      expect(stats.matchesWon, 0);
      expect(stats.matchesVsAi, 0);
      expect(stats.matchesLocal, 0);
    });
  });

  group('statistics repository', () {
    test('getStatistics is zero when nothing is recorded', () async {
      final stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 0);
      expect(stats.matchesWon, 0);
      expect(stats.matchesVsAi, 0);
      expect(stats.matchesLocal, 0);
    });

    test('recomputeFromHistory reproduces the cached aggregates',
        () async {
      await repos.matches.recordMatch(testMatch(winnerIndex: 0));
      await repos.matches.recordMatch(testMatch(winnerIndex: 1));
      await repos.matches.recordMatch(
        testMatch(mode: LocalMatchMode.localMultiplayer, winnerIndex: 0),
      );
      final cached = await repos.statistics.getStatistics();
      final recomputed = await repos.statistics.recomputeFromHistory();
      expect(recomputed.matchesPlayed, cached.matchesPlayed);
      expect(recomputed.matchesWon, cached.matchesWon);
      expect(recomputed.matchesVsAi, cached.matchesVsAi);
      expect(recomputed.matchesLocal, cached.matchesLocal);
      expect(recomputed.matchesPlayed, 3);
      expect(recomputed.matchesWon, 2);
    });

    test('recomputeFromHistory derives exactly at exactly 500 matches',
        () async {
      final base = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < kMaxLocalMatches; i++) {
        await repos.matches.recordMatch(
          testMatch(playedAt: base.add(Duration(minutes: i))),
        );
      }
      expect(await repos.matches.countMatches(), kMaxLocalMatches);
      final cached = await repos.statistics.getStatistics();
      expect(cached.matchesPlayed, kMaxLocalMatches);
      // Complete via the retained-count-equals-cached-totals check:
      // nothing was pruned yet, so the derivation is exact.
      final recomputed = await repos.statistics.recomputeFromHistory();
      expect(recomputed.matchesPlayed, kMaxLocalMatches);
      expect(recomputed.matchesWon, cached.matchesWon);
      expect(recomputed.matchesVsAi, cached.matchesVsAi);
      expect(recomputed.matchesLocal, cached.matchesLocal);
    });

    test('recomputeFromHistory keeps lifetime totals after pruning',
        () async {
      final base = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < 700; i++) {
        await repos.matches.recordMatch(
          testMatch(
            playedAt: base.add(Duration(minutes: i)),
            winnerIndex: i.isEven ? 0 : 1,
          ),
        );
      }
      final cached = await repos.statistics.getStatistics();
      expect(cached.matchesPlayed, 700);
      expect(cached.matchesWon, 350);
      expect(cached.matchesVsAi, 700);
      // Deriving from the retained 500 would claim 500 played and
      // 250 won — the repair must not do that. The cached lifetime
      // totals are returned unchanged, with no write (so `updatedAt`
      // is untouched too, which the equality check covers).
      final recomputed = await repos.statistics.recomputeFromHistory();
      expect(recomputed, cached);
      expect(
        (await repos.statistics.getStatistics()).matchesPlayed,
        700,
      );
    });

    test('recomputeFromHistory derives zeros after clearHistory',
        () async {
      await repos.matches.recordMatch(testMatch());
      await repos.matches.clearHistory();
      final recomputed = await repos.statistics.recomputeFromHistory();
      expect(recomputed.matchesPlayed, 0);
      expect(recomputed.matchesWon, 0);
      expect(recomputed.matchesVsAi, 0);
      expect(recomputed.matchesLocal, 0);
    });
  });

  group('settings repository', () {
    test('getSetting returns null for an unknown key', () async {
      expect(await repos.settings.getSetting('sound_enabled'), isNull);
    });

    test('set then get round-trips', () async {
      await repos.settings.setSetting('sound_volume', '42');
      expect(await repos.settings.getSetting('sound_volume'), '42');
    });

    test('getAllSettings returns what was set', () async {
      await repos.settings.setSetting('sound_enabled', '0');
      await repos.settings.setSetting('last_mode', 'vs_ai');
      expect(
        await repos.settings.getAllSettings(),
        {'sound_enabled': '0', 'last_mode': 'vs_ai'},
      );
    });

    test('getAllSettings is empty on a fresh repository', () async {
      expect(await repos.settings.getAllSettings(), isEmpty);
    });

    test('getAllSettings returns a copy', () async {
      await repos.settings.setSetting('sound_enabled', '0');
      final first = await repos.settings.getAllSettings();
      first['sound_enabled'] = '1';
      first['injected'] = 'yes';
      expect(
        await repos.settings.getAllSettings(),
        {'sound_enabled': '0'},
      );
    });

    test('resetToDefaults restores the known defaults', () async {
      await repos.settings.setSetting('sound_enabled', '0');
      await repos.settings.setSetting('sound_volume', '42');
      await repos.settings.setSetting('last_mode', 'vs_ai');
      await repos.settings.resetToDefaults();
      expect(await repos.settings.getSetting('sound_enabled'), '1');
      expect(await repos.settings.getSetting('vibration_enabled'), '1');
      expect(await repos.settings.getSetting('sound_volume'), '100');
      // Keys without a fixed default are absent after a reset.
      expect(await repos.settings.getSetting('last_mode'), isNull);
      expect(await repos.settings.getAllSettings(), kDefaultSettings);
    });
  });

  group('player repository', () {
    test('upsertSeat assigns an id on insert', () async {
      final stored = await repos.players.upsertSeat(testSeat());
      expect(stored.id, 1);
      expect(stored.displayName, 'Player 1');
    });

    test('upsertSeat with an id updates the existing seat', () async {
      final stored = await repos.players.upsertSeat(testSeat());
      final updated = await repos.players.upsertSeat(
        stored.copyWith(displayName: 'Renamed'),
      );
      expect(updated.id, stored.id);
      expect(updated.displayName, 'Renamed');
      final listed = await repos.players.listRecentSeats();
      expect(listed.length, 1);
      expect(listed.single.displayName, 'Renamed');
    });

    test('listRecentSeats is most-recently-used first', () async {
      final oldest = await repos.players.upsertSeat(
        testSeat(
          displayName: 'Old',
          lastUsedAt: DateTime.utc(2026, 11, 20, 12, 0),
        ),
      );
      final newest = await repos.players.upsertSeat(
        testSeat(
          displayName: 'New',
          colour: PlayerColour.green,
          lastUsedAt: DateTime.utc(2026, 11, 22, 12, 0),
        ),
      );
      final middle = await repos.players.upsertSeat(
        testSeat(
          displayName: 'Mid',
          colour: PlayerColour.yellow,
          lastUsedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      final listed = await repos.players.listRecentSeats();
      expect(
        listed.map((s) => s.id),
        [newest.id, middle.id, oldest.id],
      );
    });

    test('listRecentSeats puts seats without lastUsedAt last', () async {
      final neverUsed = await repos.players.upsertSeat(testSeat());
      final used = await repos.players.upsertSeat(
        testSeat(
          displayName: 'Used',
          colour: PlayerColour.green,
          lastUsedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      final listed = await repos.players.listRecentSeats();
      expect(listed.map((s) => s.id), [used.id, neverUsed.id]);
    });

    test('listRecentSeats is empty on a fresh repository', () async {
      expect(await repos.players.listRecentSeats(), isEmpty);
    });
  });
}

void main() {
  defineRepositoryContractTests(() {
    final store = InMemoryStore();
    return RepositorySet(
      matches: InMemoryLocalMatchRepository(store),
      statistics: InMemoryLocalStatisticsRepository(store),
      settings: InMemorySettingsRepository(store),
      snapshots: InMemorySnapshotRepository(store),
      players: InMemoryLocalPlayerRepository(store),
    );
  });
}
