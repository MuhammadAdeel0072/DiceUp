import 'package:diceup/data/local/diceup_database.dart';
import 'package:diceup/data/local/sqlite_local_match_repository.dart';
import 'package:diceup/data/local/sqlite_local_player_repository.dart';
import 'package:diceup/data/local/sqlite_local_statistics_repository.dart';
import 'package:diceup/data/local/sqlite_settings_repository.dart';
import 'package:diceup/data/local/sqlite_snapshot_repository.dart';
import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/local_player_repository.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../repositories/repository_contract_test.dart';
import 'failing_database.dart';

/// M1.4 SQLite-specific repository tests (SDD §9.1; FR-29–32;
/// NFR-30, NFR-36; D-24).
///
/// These test what the shared contract suite cannot: the storage
/// formats (exact `players_json`, settings JSON, verbatim
/// snapshots), strict parsing of corrupt rows, transaction rollback
/// under injected mid-transaction failure, and the lifetime
/// statistics behaviour at and beyond the 500-match cap — all
/// against the real SQLite repositories on an in-memory ffi
/// database. Unlike the contract run in
/// `sqlite_repository_contract_test.dart`, these tests use a
/// genuinely fresh database: the seeded defaults are left in place,
/// and one group asserts they are visible through the settings
/// repository.
void main() {
  sqfliteFfiInit();

  /// A fresh in-memory database, closed automatically after the test.
  Future<DiceUpDatabase> openInMemoryDatabase() async {
    final database = DiceUpDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await database.open();
    return database;
  }

  /// The five SQLite repositories on [db], plus the raw [Database]
  /// for asserting on stored rows directly.
  ({
    Database db,
    SqliteLocalMatchRepository matches,
    SqliteLocalStatisticsRepository statistics,
    SqliteSettingsRepository settings,
    SqliteSnapshotRepository snapshots,
    SqliteLocalPlayerRepository players,
  })
  openRepositories(Database db) => (
    db: db,
    matches: SqliteLocalMatchRepository(db),
    statistics: SqliteLocalStatisticsRepository(db),
    settings: SqliteSettingsRepository(db),
    snapshots: SqliteSnapshotRepository(db),
    players: SqliteLocalPlayerRepository(db),
  );

  /// Reads the single statistics row as a plain map.
  Future<Map<String, Object?>> readStatisticsRow(Database db) async {
    final rows = await db.query('local_statistics');
    return rows.single;
  }

  /// Overwrites the cached statistics row with [counts] and a fixed
  /// [updatedAt] — a deliberately diverged cache, to prove the
  /// guarded recompute repairs it only when history is complete.
  Future<void> corruptStatistics(
    Database db, {
    required int played,
    required int won,
    required int vsAi,
    required int local,
    String updatedAt = '2026-01-01T00:00:00.000Z',
  }) async {
    await db.update(
      'local_statistics',
      <String, Object?>{
        'matches_played': played,
        'matches_won': won,
        'matches_vs_ai': vsAi,
        'matches_local': local,
        'updated_at': updatedAt,
      },
      where: 'id = ?',
      whereArgs: [1],
    );
  }

  group('serialization round-trips', () {
    test('players_json stores the exact seat format', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      final match = LocalMatch(
        playedAt: DateTime.utc(2026, 11, 21, 12, 0),
        mode: LocalMatchMode.vsAi,
        playerCount: 2,
        players: [
          LocalMatchPlayer(
            name: 'Åsa 🎲',
            colour: PlayerColour.red,
            isAi: false,
          ),
          LocalMatchPlayer(
            name: 'CPU',
            colour: PlayerColour.green,
            isAi: true,
            difficulty: AiDifficulty.hard,
          ),
        ],
        winnerIndex: 0,
        winnerName: 'Åsa 🎲',
        durationSeconds: 123,
        rulesetVersion: '1.0.0',
        createdAt: DateTime.utc(2026, 11, 21, 12, 0),
      );
      final stored = await repos.matches.recordMatch(match);

      final rows = await repos.db.query(
        'local_matches',
        where: 'id = ?',
        whereArgs: [stored.id],
      );
      expect(
        rows.single['players_json'],
        '[{"name":"Åsa 🎲","colour":"red","isAi":false,'
        '"difficulty":null},{"name":"CPU","colour":"green",'
        '"isAi":true,"difficulty":"hard"}]',
      );
      // And the stored row reads back as the same match.
      expect(await repos.matches.getMatch(stored.id!), stored);
      expect(stored.id, 1);
    });

    test('AI difficulty null vs set round-trips', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      final unspecified = await repos.matches.recordMatch(
        testMatch(
          players: [
            LocalMatchPlayer(
              name: 'Player 1',
              colour: PlayerColour.red,
              isAi: false,
            ),
            LocalMatchPlayer(
              name: 'CPU',
              colour: PlayerColour.blue,
              isAi: true,
              // difficulty deliberately null ("unspecified").
            ),
          ],
        ),
      );
      final medium = await repos.matches.recordMatch(
        testMatch(
          players: [
            LocalMatchPlayer(
              name: 'Player 1',
              colour: PlayerColour.red,
              isAi: false,
            ),
            LocalMatchPlayer(
              name: 'CPU',
              colour: PlayerColour.blue,
              isAi: true,
              difficulty: AiDifficulty.medium,
            ),
          ],
        ),
      );
      final rows = await repos.db.query('local_matches', orderBy: 'id ASC');
      expect(rows[0]['players_json'], contains('"difficulty":null'));
      expect(rows[1]['players_json'], contains('"difficulty":"medium"'));
      expect(
        (await repos.matches.getMatch(unspecified.id!))!.players[1].difficulty,
        isNull,
      );
      expect(
        (await repos.matches.getMatch(medium.id!))!.players[1].difficulty,
        AiDifficulty.medium,
      );
    });

    test('settings JSON incl. last_difficulties round-trips', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      const difficultiesJson = '{"0":"easy","1":"medium","2":"hard"}';
      await repos.settings.setSetting('last_difficulties', difficultiesJson);
      expect(
        await repos.settings.getSetting('last_difficulties'),
        difficultiesJson,
      );
      final rows = await repos.db.query(
        'local_settings',
        where: 'key = ?',
        whereArgs: ['last_difficulties'],
      );
      expect(rows.single['value'], difficultiesJson);
    });

    test('snapshot JSON is stored and returned verbatim', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      const snapshotJson =
          '{"version":1,"players":[{"name":"Åsa \\"Ace\\" 🎲",'
          '"tokens":[[0,1,2,3]]}],"nested":{"a":[true,null,'
          '{"b":"c\\\\d"}],"note":"back\\\\slash / unicode \\u00e9"}}';
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: snapshotJson,
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      final rows = await repos.db.query('saved_match_snapshots');
      expect(rows.single['snapshot_json'], snapshotJson);
      final loaded = await repos.snapshots.loadSnapshot(kCurrentMatchKey);
      expect(loaded?.snapshotJson, snapshotJson);
      expect(loaded?.savedAt, DateTime.utc(2026, 11, 21, 12, 0));
    });

    test(
      'seat round-trip preserves unicode, difficulty and lastUsedAt',
      () async {
        final database = await openInMemoryDatabase();
        final repos = openRepositories(database.database);
        final seat = LocalPlayerSeat(
          displayName: 'Åsa 🎲',
          colour: PlayerColour.yellow,
          isAi: true,
          difficulty: AiDifficulty.hard,
          lastUsedAt: DateTime.utc(2026, 11, 20, 9, 30),
        );
        final stored = await repos.players.upsertSeat(seat);
        expect(stored.id, 1);
        final listed = await repos.players.listRecentSeats();
        expect(listed, [seat.copyWith(id: 1)]);
        final rows = await repos.db.query('local_players');
        expect(rows.single['display_name'], 'Åsa 🎲');
        expect(rows.single['colour'], 'yellow');
        expect(rows.single['is_ai'], 1);
        expect(rows.single['difficulty'], 'hard');
        expect(rows.single['last_used_at'], '2026-11-20T09:30:00.000Z');
      },
    );
  });

  group('strict parsing of corrupt rows', () {
    test('unknown mode label throws FormatException', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      await repos.db.insert('local_matches', <String, Object?>{
        'played_at': '2026-11-21T12:00:00.000Z',
        'mode': 'online',
        'player_count': 2,
        'players_json':
            '[{"name":"A","colour":"red","isAi":false,'
            '"difficulty":null},{"name":"B","colour":"green",'
            '"isAi":false,"difficulty":null}]',
        'ruleset_version': '1.0.0',
        'created_at': '2026-11-21T12:00:00.000Z',
      });
      await expectLater(
        () => repos.matches.listMatches(),
        throwsFormatException,
      );
      await expectLater(() => repos.matches.getMatch(1), throwsFormatException);
    });

    test('unknown colour label throws FormatException', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      await repos.db.insert('local_matches', <String, Object?>{
        'played_at': '2026-11-21T12:00:00.000Z',
        'mode': 'vs_ai',
        'player_count': 2,
        'players_json':
            '[{"name":"A","colour":"purple","isAi":false,'
            '"difficulty":null},{"name":"B","colour":"green",'
            '"isAi":false,"difficulty":null}]',
        'ruleset_version': '1.0.0',
        'created_at': '2026-11-21T12:00:00.000Z',
      });
      await expectLater(
        () => repos.matches.listMatches(),
        throwsFormatException,
      );
    });

    test('unknown difficulty label throws FormatException', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      await repos.db.insert('local_matches', <String, Object?>{
        'played_at': '2026-11-21T12:00:00.000Z',
        'mode': 'vs_ai',
        'player_count': 2,
        'players_json':
            '[{"name":"A","colour":"red","isAi":false,'
            '"difficulty":null},{"name":"B","colour":"green",'
            '"isAi":true,"difficulty":"impossible"}]',
        'ruleset_version': '1.0.0',
        'created_at': '2026-11-21T12:00:00.000Z',
      });
      await expectLater(
        () => repos.matches.listMatches(),
        throwsFormatException,
      );
    });

    test('malformed players_json throws FormatException', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      await repos.db.insert('local_matches', <String, Object?>{
        'played_at': '2026-11-21T12:00:00.000Z',
        'mode': 'vs_ai',
        'player_count': 2,
        'players_json': 'not json at all',
        'ruleset_version': '1.0.0',
        'created_at': '2026-11-21T12:00:00.000Z',
      });
      await expectLater(
        () => repos.matches.listMatches(),
        throwsFormatException,
      );
    });

    test('unknown seat colour throws FormatException', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      await repos.db.insert('local_players', <String, Object?>{
        'display_name': 'Ghost',
        'colour': 'purple',
        'is_ai': 0,
      });
      await expectLater(
        () => repos.players.listRecentSeats(),
        throwsFormatException,
      );
    });

    test('recompute throws FormatException on corrupt history', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      await repos.db.insert('local_matches', <String, Object?>{
        'played_at': '2026-11-21T12:00:00.000Z',
        'mode': 'vs_ai',
        'player_count': 2,
        'players_json':
            '[{"name":"A","colour":"red","isAi":false,'
            '"difficulty":null},{"name":"B","colour":"green",'
            '"isAi":true,"difficulty":"nope"}]',
        'winner_index': 0,
        'winner_name': 'A',
        'ruleset_version': '1.0.0',
        'created_at': '2026-11-21T12:00:00.000Z',
      });
      await expectLater(
        () => repos.statistics.recomputeFromHistory(),
        throwsFormatException,
      );
    });
  });

  group('missing-record behaviour', () {
    test('plain misses return null / false / no-op, never throw', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      expect(await repos.matches.getMatch(999), isNull);
      expect(await repos.matches.getMatch(1), isNull);
      expect(await repos.snapshots.loadSnapshot(kCurrentMatchKey), isNull);
      expect(await repos.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      await repos.snapshots.deleteSnapshot(kCurrentMatchKey);
      expect(await repos.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      expect(await repos.settings.getSetting('no_such_key'), isNull);
      // Seeded keys are NOT misses on a fresh database (M1.3).
      expect(await repos.settings.getSetting('last_mode'), isNull);
    });
  });

  group('seeded defaults are visible on a fresh database', () {
    test('settings repository returns the seeded defaults', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      expect(await repos.settings.getSetting('sound_enabled'), '1');
      expect(await repos.settings.getSetting('vibration_enabled'), '1');
      expect(await repos.settings.getSetting('sound_volume'), '100');
      expect(await repos.settings.getAllSettings(), kDefaultSettings);
      // The statistics seed is zeros.
      final stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 0);
      expect(stats.matchesWon, 0);
      expect(stats.matchesVsAi, 0);
      expect(stats.matchesLocal, 0);
    });
  });

  group('recordMatch ignores the id on the argument', () {
    test('a match recorded with id 999 gets a fresh id', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      final first = await repos.matches.recordMatch(
        testMatch().copyWith(id: 999),
      );
      expect(first.id, 1);
      final second = await repos.matches.recordMatch(
        testMatch().copyWith(id: 999),
      );
      expect(second.id, 2);
    });
  });

  group('transaction rollback (NFR-30)', () {
    /// Records one baseline match and saves an in-progress snapshot
    /// through repositories built on the failing wrapper (disarmed),
    /// then arms the plan to fail the [failingWrite]th write of the
    /// next `recordMatch` and proves nothing changed.
    Future<void> expectRecordMatchRollback(int failingWrite) async {
      final database = await openInMemoryDatabase();
      final plan = FailurePlan();
      final failingDb = FailingDatabase(database.database, plan);
      final repos = openRepositories(failingDb);
      // Baseline state (wrapper disarmed): one recorded match, then
      // one in-progress snapshot saved AFTER it — recordMatch
      // deletes the in-progress snapshot, so the snapshot must be
      // saved after the baseline match, not before it.
      await repos.matches.recordMatch(testMatch());
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: '{"in":"progress"}',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      final baselineStats = await readStatisticsRow(database.database);
      expect(baselineStats['matches_played'], 1);
      expect(baselineStats['matches_won'], 1);
      expect(baselineStats['matches_vs_ai'], 1);

      // recordMatch performs exactly four writes, in order:
      // 1. insert the match row
      // 2. update local_statistics
      // 3. prune (rawDelete)
      // 4. delete the in-progress snapshot
      plan.arm(failingWrite);
      await expectLater(
        () => repos.matches.recordMatch(testMatch()),
        throwsA(isA<SimulatedRepositoryFailure>()),
      );
      plan.disarm();

      // Nothing from the failed recordMatch survived: no new row,
      // statistics byte-identical, snapshot intact.
      expect(await repos.matches.countMatches(), 1);
      expect(await repos.matches.getMatch(2), isNull);
      expect(await readStatisticsRow(database.database), baselineStats);
      expect(
        (await repos.snapshots.loadSnapshot(kCurrentMatchKey))?.snapshotJson,
        '{"in":"progress"}',
      );
    }

    test('recordMatch rolls back when the insert fails', () async {
      await expectRecordMatchRollback(1);
    });

    test('recordMatch rolls back when the statistics update fails', () async {
      await expectRecordMatchRollback(2);
    });

    test('recordMatch rolls back when the prune fails', () async {
      await expectRecordMatchRollback(3);
    });

    test('recordMatch rolls back when the snapshot delete fails', () async {
      await expectRecordMatchRollback(4);
    });

    test('clearHistory rolls back when the statistics reset fails', () async {
      final database = await openInMemoryDatabase();
      final plan = FailurePlan();
      final failingDb = FailingDatabase(database.database, plan);
      final repos = openRepositories(failingDb);
      await repos.matches.recordMatch(testMatch());
      await repos.matches.recordMatch(
        testMatch(mode: LocalMatchMode.localMultiplayer),
      );

      // clearHistory performs two writes: delete the matches, then
      // reset the statistics. Fail the second.
      plan.arm(2);
      await expectLater(
        () => repos.matches.clearHistory(),
        throwsA(isA<SimulatedRepositoryFailure>()),
      );
      plan.disarm();

      expect(await repos.matches.countMatches(), 2);
      final stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 2);
      expect(stats.matchesVsAi, 1);
      expect(stats.matchesLocal, 1);
    });

    test('resetToDefaults rolls back when a default insert fails', () async {
      final database = await openInMemoryDatabase();
      final plan = FailurePlan();
      final failingDb = FailingDatabase(database.database, plan);
      final repos = openRepositories(failingDb);
      await repos.settings.setSetting('sound_enabled', '0');
      await repos.settings.setSetting('last_mode', 'vs_ai');

      // resetToDefaults performs four writes: delete all settings,
      // then insert the three defaults. Fail the third.
      plan.arm(3);
      await expectLater(
        () => repos.settings.resetToDefaults(),
        throwsA(isA<SimulatedRepositoryFailure>()),
      );
      plan.disarm();

      expect(await repos.settings.getAllSettings(), {
        'sound_enabled': '0',
        'vibration_enabled': '1',
        'sound_volume': '100',
        'last_mode': 'vs_ai',
      });
    });
  });

  group('lifetime statistics beyond the 500-match cap', () {
    test('501 / 502 / 700: totals stay exact, rows stay capped', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
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

      for (var i = 200; i < 501; i++) {
        await repos.matches.recordMatch(
          testMatch(
            playedAt: base.add(Duration(minutes: i)),
            winnerIndex: 1, // the AI seat wins.
          ),
        );
      }
      expect(await repos.matches.countMatches(), kMaxLocalMatches);
      stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 501);
      expect(stats.matchesWon, 200);
      expect(stats.matchesVsAi, 301);

      // The 502nd record: a derivation from the retained list would
      // freeze the lifetime total at 501 here.
      await repos.matches.recordMatch(
        testMatch(
          playedAt: base.add(const Duration(minutes: 501)),
          winnerIndex: 1,
        ),
      );
      stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 502);
      expect(stats.matchesWon, 200);

      for (var i = 502; i < 700; i++) {
        await repos.matches.recordMatch(
          testMatch(playedAt: base.add(Duration(minutes: i)), winnerIndex: 1),
        );
      }
      expect(await repos.matches.countMatches(), kMaxLocalMatches);
      expect(await repos.matches.getMatch(1), isNull);
      expect((await repos.matches.listMatches()).first.id, 700);
      stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 700);
      // Only the 200 human wins count — the 500 AI wins never did.
      expect(stats.matchesWon, 200);
      expect(stats.matchesVsAi, 500);
      expect(stats.matchesLocal, 200);
    });

    test('recompute cannot overwrite lifetime totals after pruning', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
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

      // A repair derived from the retained 500 would claim 500
      // played and 250 won — the guard refuses, and the cached
      // lifetime totals (including updatedAt) come back unchanged.
      final recomputed = await repos.statistics.recomputeFromHistory();
      expect(recomputed, cached);
      expect((await repos.statistics.getStatistics()).matchesPlayed, 700);
    });

    test('a diverged cache is NOT repaired after pruning', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      final base = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < 700; i++) {
        await repos.matches.recordMatch(
          testMatch(playedAt: base.add(Duration(minutes: i)), winnerIndex: 1),
        );
      }
      expect((await repos.statistics.getStatistics()).matchesPlayed, 700);
      // Corrupt the cache to wrong values with a fixed updatedAt.
      await corruptStatistics(
        database.database,
        played: 99,
        won: 99,
        vsAi: 99,
        local: 99,
      );
      final recomputed = await repos.statistics.recomputeFromHistory();
      // The guard refuses repair: the diverged 99s come back
      // unchanged, with updatedAt untouched — no write happened.
      expect(recomputed.matchesPlayed, 99);
      expect(recomputed.matchesWon, 99);
      expect(recomputed.matchesVsAi, 99);
      expect(recomputed.matchesLocal, 99);
      expect(recomputed.updatedAt, DateTime.parse('2026-01-01T00:00:00.000Z'));
      final stillCached = await repos.statistics.getStatistics();
      expect(stillCached, recomputed);
    });

    test(
      'recompute repairs a diverged cache when history is complete',
      () async {
        final database = await openInMemoryDatabase();
        final repos = openRepositories(database.database);
        await repos.matches.recordMatch(testMatch(winnerIndex: 0));
        await repos.matches.recordMatch(testMatch(winnerIndex: 1));
        await repos.matches.recordMatch(
          testMatch(mode: LocalMatchMode.localMultiplayer, winnerIndex: 0),
        );
        await corruptStatistics(
          database.database,
          played: 99,
          won: 50,
          vsAi: 50,
          local: 50,
        );
        final recomputed = await repos.statistics.recomputeFromHistory();
        expect(recomputed.matchesPlayed, 3);
        expect(recomputed.matchesWon, 2);
        expect(recomputed.matchesVsAi, 2);
        expect(recomputed.matchesLocal, 1);
        expect((await repos.statistics.getStatistics()).matchesPlayed, 3);
      },
    );

    test('recompute refuses repair at exactly 500 matches when the '
        'cache is diverged', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      final base = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < kMaxLocalMatches; i++) {
        await repos.matches.recordMatch(
          testMatch(playedAt: base.add(Duration(minutes: i))),
        );
      }
      await corruptStatistics(
        database.database,
        played: 99,
        won: 99,
        vsAi: 99,
        local: 99,
      );
      // Complete via the retained-count-equals-cached-totals check
      // only if the cache still said 500 — it says 99, and the
      // count is 500, so neither guard branch holds... except the
      // count is NOT below 500. This history is therefore treated
      // as incomplete and the diverged cache is NOT repaired: at
      // exactly 500 retained rows the guard cannot tell pruned from
      // unpruned history once the cache itself is corrupt.
      final recomputed = await repos.statistics.recomputeFromHistory();
      expect(recomputed.matchesPlayed, 99);
    });
  });

  group('clearHistory', () {
    test('resets statistics to zero and leaves snapshots untouched', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      await repos.matches.recordMatch(testMatch());
      await repos.matches.recordMatch(
        testMatch(mode: LocalMatchMode.localMultiplayer),
      );
      // The snapshot is saved AFTER the matches: recordMatch
      // deletes the in-progress snapshot, so saving it first would
      // prove nothing about clearHistory.
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: '{"in":"progress"}',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      await repos.matches.clearHistory();
      expect(await repos.matches.countMatches(), 0);
      final stats = await repos.statistics.getStatistics();
      expect(stats.matchesPlayed, 0);
      expect(stats.matchesWon, 0);
      expect(stats.matchesVsAi, 0);
      expect(stats.matchesLocal, 0);
      // The in-progress snapshot survived the clear.
      expect(
        (await repos.snapshots.loadSnapshot(kCurrentMatchKey))?.snapshotJson,
        '{"in":"progress"}',
      );
    });
  });

  group('player seats', () {
    test('upsertSeat with an id inserts under that id', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      final stored = await repos.players.upsertSeat(testSeat(id: 42));
      expect(stored.id, 42);
      expect(stored.displayName, 'Player 1');
      final listed = await repos.players.listRecentSeats();
      expect(listed.map((s) => s.id), [42]);
      // Updating the same id replaces the row instead of adding one.
      final updated = await repos.players.upsertSeat(
        testSeat(id: 42, displayName: 'Renamed'),
      );
      expect(updated.id, 42);
      expect(updated.displayName, 'Renamed');
      expect((await repos.players.listRecentSeats()).length, 1);
    });

    test('lastUsedAt is stored exactly as given, never stamped', () async {
      final database = await openInMemoryDatabase();
      final repos = openRepositories(database.database);
      final fixed = DateTime.utc(2026, 11, 20, 9, 30);
      final stored = await repos.players.upsertSeat(
        testSeat(lastUsedAt: fixed),
      );
      expect(stored.lastUsedAt, fixed);
      final rows = await repos.db.query('local_players');
      expect(rows.single['last_used_at'], '2026-11-20T09:30:00.000Z');
      final neverUsed = await repos.players.upsertSeat(
        testSeat(displayName: 'Never', colour: PlayerColour.green),
      );
      expect(neverUsed.lastUsedAt, isNull);
      final rowsAfter = await repos.db.query(
        'local_players',
        where: 'id = ?',
        whereArgs: [neverUsed.id],
      );
      expect(rowsAfter.single['last_used_at'], isNull);
    });
  });
}
