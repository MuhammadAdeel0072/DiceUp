import 'dart:io';

import 'package:diceup/data/local/database_factory.dart';
import 'package:diceup/data/local/diceup_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// M1.3 database tests (SDD §9.1; FR-29–32; NFR-30, NFR-36).
///
/// These tests exercise the database + factory only, at the raw-SQL
/// level. The repositories land in M1.4 and reuse the schema,
/// [DiceUpDatabase.pruneLocalMatchesSql] and the seeding proven here.
///
/// Tests run against `sqflite_common_ffi` (desktop/test execution):
/// in-memory databases for isolation, temp files where a test must
/// close and reopen the same database. The app itself uses the
/// platform factory via [openDiceUpDatabase].
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

  /// A fresh temp-file database, closed + deleted after the test.
  Future<DiceUpDatabase> openTempFileDatabase() async {
    final dir = await Directory.systemTemp.createTemp('diceup_m13_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final database = DiceUpDatabase(
      factory: databaseFactoryFfi,
      path: p.join(dir.path, 'diceup.db'),
    );
    addTearDown(database.close);
    await database.open();
    return database;
  }

  /// One `local_matches` row. Only [playedAt] varies by default;
  /// callers override the rest.
  Map<String, Object?> matchRow({
    required String playedAt,
    String mode = 'vs_ai',
    int playerCount = 2,
    String playersJson = '[]',
    String rulesetVersion = '1.0.0',
  }) => <String, Object?>{
    'played_at': playedAt,
    'mode': mode,
    'player_count': playerCount,
    'players_json': playersJson,
    'winner_index': null,
    'winner_name': null,
    'duration_seconds': null,
    'ruleset_version': rulesetVersion,
    'created_at': playedAt,
  };

  /// `PRAGMA table_info` rows as (name, type, notnull, pk) tuples,
  /// in declared column order.
  Future<List<(String, String, int, int)>> tableColumns(
    Database db,
    String table,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows
        .map(
          (row) => (
            row['name'] as String,
            row['type'] as String,
            row['notnull'] as int,
            row['pk'] as int,
          ),
        )
        .toList();
  }

  Future<String?> tableSql(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.single['sql'] as String?;
  }

  group('schema (SDD §9.1)', () {
    test('creates exactly the five tables', () async {
      final database = await openInMemoryDatabase();
      final db = database.database;
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = rows.map((row) => row['name'] as String).toSet();
      // AUTOINCREMENT creates the internal sqlite_sequence table;
      // it is SQLite's own bookkeeping, not a sixth app table.
      expect(names, {
        'local_matches',
        'local_statistics',
        'local_settings',
        'local_players',
        'saved_match_snapshots',
        'sqlite_sequence',
      });
    });

    test('local_matches columns match SDD §9.1 exactly', () async {
      final database = await openInMemoryDatabase();
      expect(await tableColumns(database.database, 'local_matches'), [
        ('id', 'INTEGER', 0, 1),
        ('played_at', 'TEXT', 1, 0),
        ('mode', 'TEXT', 1, 0),
        ('player_count', 'INTEGER', 1, 0),
        ('players_json', 'TEXT', 1, 0),
        ('winner_index', 'INTEGER', 0, 0),
        ('winner_name', 'TEXT', 0, 0),
        ('duration_seconds', 'INTEGER', 0, 0),
        ('ruleset_version', 'TEXT', 1, 0),
        ('created_at', 'TEXT', 1, 0),
      ]);
    });

    test('local_statistics columns match SDD §9.1 exactly', () async {
      final database = await openInMemoryDatabase();
      expect(await tableColumns(database.database, 'local_statistics'), [
        ('id', 'INTEGER', 0, 1),
        ('matches_played', 'INTEGER', 1, 0),
        ('matches_won', 'INTEGER', 1, 0),
        ('matches_vs_ai', 'INTEGER', 1, 0),
        ('matches_local', 'INTEGER', 1, 0),
        ('updated_at', 'TEXT', 1, 0),
      ]);
      // The four counters default to 0.
      final rows = await database.database.rawQuery(
        'PRAGMA table_info(local_statistics)',
      );
      for (final row in rows) {
        if (row['name'] != 'id' && row['name'] != 'updated_at') {
          expect(row['dflt_value'], '0', reason: '${row['name']}');
        }
      }
    });

    test('local_settings columns match SDD §9.1 exactly', () async {
      final database = await openInMemoryDatabase();
      expect(await tableColumns(database.database, 'local_settings'), [
        ('key', 'TEXT', 0, 1),
        ('value', 'TEXT', 1, 0),
        ('updated_at', 'TEXT', 1, 0),
      ]);
    });

    test('local_players columns match SDD §9.1 exactly', () async {
      final database = await openInMemoryDatabase();
      expect(await tableColumns(database.database, 'local_players'), [
        ('id', 'INTEGER', 0, 1),
        ('display_name', 'TEXT', 1, 0),
        ('colour', 'TEXT', 1, 0),
        ('is_ai', 'INTEGER', 1, 0),
        ('difficulty', 'TEXT', 0, 0),
        ('last_used_at', 'TEXT', 0, 0),
      ]);
    });

    test('saved_match_snapshots columns match SDD §9.1 exactly', () async {
      final database = await openInMemoryDatabase();
      expect(await tableColumns(database.database, 'saved_match_snapshots'), [
        ('id', 'INTEGER', 0, 1),
        ('match_key', 'TEXT', 1, 0),
        ('snapshot_json', 'TEXT', 1, 0),
        ('saved_at', 'TEXT', 1, 0),
      ]);
    });

    test('CHECK constraints are declared', () async {
      final database = await openInMemoryDatabase();
      final db = database.database;
      expect(
        await tableSql(db, 'local_matches'),
        contains('CHECK (player_count >= 2 AND player_count <= 4)'),
      );
      expect(
        await tableSql(db, 'local_statistics'),
        contains('CHECK (id = 1)'),
      );
      expect(
        await tableSql(db, 'saved_match_snapshots'),
        contains('match_key TEXT NOT NULL UNIQUE'),
      );
    });

    test('played_at DESC index exists on local_matches', () async {
      final database = await openInMemoryDatabase();
      final db = database.database;
      final indexes = await db.rawQuery('PRAGMA index_list(local_matches)');
      expect(
        indexes.map((row) => row['name']),
        contains('idx_local_matches_played_at'),
      );
      final sqlRows = await db.rawQuery(
        "SELECT sql FROM sqlite_master WHERE type = 'index' "
        "AND name = 'idx_local_matches_played_at'",
      );
      expect(sqlRows.single['sql'] as String, contains('played_at DESC'));
    });

    test('database version is 1', () async {
      final database = await openInMemoryDatabase();
      expect(await database.database.getVersion(), 1);
    });

    test('constraint violations are rejected, not silently stored', () async {
      final database = await openInMemoryDatabase();
      final db = database.database;
      // player_count CHECK 2–4.
      await expectLater(
        () => db.insert(
          'local_matches',
          matchRow(playedAt: '2026-11-21T00:00:00.000Z', playerCount: 1),
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        () => db.insert(
          'local_matches',
          matchRow(playedAt: '2026-11-21T00:00:00.000Z', playerCount: 5),
        ),
        throwsA(isA<DatabaseException>()),
      );
      // local_statistics CHECK (id = 1).
      await expectLater(
        () => db.insert('local_statistics', <String, Object?>{
          'id': 2,
          'updated_at': '2026-11-21T00:00:00.000Z',
        }),
        throwsA(isA<DatabaseException>()),
      );
      // saved_match_snapshots match_key UNIQUE.
      const snapshot = <String, Object?>{
        'match_key': 'current',
        'snapshot_json': '{}',
        'saved_at': '2026-11-21T00:00:00.000Z',
      };
      await db.insert('saved_match_snapshots', snapshot);
      await expectLater(
        () => db.insert('saved_match_snapshots', snapshot),
        throwsA(isA<DatabaseException>()),
      );
      // Nothing from the failed inserts leaked in.
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM local_matches'),
        ),
        0,
      );
    });
  });

  group('seeding', () {
    test('statistics row is seeded (id = 1, all zeros)', () async {
      final database = await openInMemoryDatabase();
      final rows = await database.database.query('local_statistics');
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row['id'], 1);
      expect(row['matches_played'], 0);
      expect(row['matches_won'], 0);
      expect(row['matches_vs_ai'], 0);
      expect(row['matches_local'], 0);
      expect(row['updated_at'] as String, isNotEmpty);
    });

    test('default settings are seeded (D-25)', () async {
      final database = await openInMemoryDatabase();
      final rows = await database.database.query(
        'local_settings',
        orderBy: 'key ASC',
      );
      expect(
        {for (final row in rows) row['key'] as String: row['value']},
        {'sound_enabled': '1', 'sound_volume': '100', 'vibration_enabled': '1'},
      );
      for (final row in rows) {
        expect(row['updated_at'] as String, isNotEmpty);
      }
    });

    test('last-used options have no seeded default', () async {
      final database = await openInMemoryDatabase();
      for (final key in [
        'last_mode',
        'last_player_count',
        'last_difficulties',
      ]) {
        final rows = await database.database.query(
          'local_settings',
          where: 'key = ?',
          whereArgs: [key],
        );
        expect(rows, isEmpty, reason: key);
      }
    });
  });

  group('reopen', () {
    test('reopening does not recreate or reseed the database', () async {
      final first = await openTempFileDatabase();
      final path = first.database.path;
      final db = first.database;
      // Mutate every seeded area, then close.
      await db.update(
        'local_statistics',
        {'matches_played': 7, 'matches_won': 3},
        where: 'id = ?',
        whereArgs: [1],
      );
      await db.insert('local_settings', <String, Object?>{
        'key': 'last_mode',
        'value': 'vs_ai',
        'updated_at': '2026-11-21T00:00:00.000Z',
      });
      await db.insert('local_settings', <String, Object?>{
        'key': 'custom_key',
        'value': 'custom_value',
        'updated_at': '2026-11-21T00:00:00.000Z',
      });
      await first.close();

      // Reopen the same file with a fresh handle.
      final second = DiceUpDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(second.close);
      await second.open();
      final reopened = second.database;
      expect(await reopened.getVersion(), 1);

      // Mutations survived; defaults were not re-seeded over them.
      final stats = await reopened.query('local_statistics');
      expect(stats.single['matches_played'], 7);
      expect(stats.single['matches_won'], 3);
      final settings = await reopened.query('local_settings');
      expect(
        {for (final row in settings) row['key'] as String: row['value']},
        {
          'sound_enabled': '1',
          'vibration_enabled': '1',
          'sound_volume': '100',
          'last_mode': 'vs_ai',
          'custom_key': 'custom_value',
        },
      );
    });

    test('rows persist across close and reopen', () async {
      final first = await openTempFileDatabase();
      final path = first.database.path;
      final id = await first.database.insert(
        'local_matches',
        matchRow(
          playedAt: '2026-11-21T12:00:00.000Z',
          mode: 'local_multiplayer',
          playerCount: 4,
          playersJson: '[{"name":"Player 1"}]',
        ),
      );
      await first.close();

      final second = DiceUpDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(second.close);
      await second.open();
      final rows = await second.database.query(
        'local_matches',
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(rows, hasLength(1));
      expect(rows.single['mode'], 'local_multiplayer');
      expect(rows.single['player_count'], 4);
      expect(rows.single['players_json'], '[{"name":"Player 1"}]');
    });

    test('onUpgrade stub fails closed (no migration for v1)', () async {
      final first = await openTempFileDatabase();
      final path = first.database.path;
      await first.close();

      // A future binary opening this v1 file at version 2 must fail
      // loudly instead of running against a stale schema.
      await expectLater(
        () => databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 2,
            onCreate: DiceUpDatabase.onCreate,
            onUpgrade: DiceUpDatabase.onUpgrade,
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );

      // The failed upgrade left the v1 database intact.
      final second = DiceUpDatabase(factory: databaseFactoryFfi, path: path);
      addTearDown(second.close);
      await second.open();
      expect(await second.database.getVersion(), 1);
    });
  });

  group('single instance', () {
    test('open() twice returns the identical Database', () async {
      final database = await openInMemoryDatabase();
      final first = await database.open();
      final second = await database.open();
      expect(identical(first, second), isTrue);
      expect(database.isOpen, isTrue);
    });

    test('database getter throws before open and after close', () async {
      final database = DiceUpDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      expect(() => database.database, throwsStateError);
      await database.open();
      expect(database.database, isA<Database>());
      await database.close();
      expect(database.isOpen, isFalse);
      expect(() => database.database, throwsStateError);
      // Reopening after close works and yields a fresh database.
      await database.open();
      expect(database.isOpen, isTrue);
      await database.close();
    });
  });

  group('transactions (NFR-30)', () {
    test('a transaction that fails partway rolls back fully', () async {
      final database = await openInMemoryDatabase();
      final db = database.database;
      await expectLater(
        () => db.transaction((txn) async {
          await txn.insert(
            'local_matches',
            matchRow(playedAt: '2026-11-21T00:00:01.000Z'),
          );
          await txn.insert(
            'local_matches',
            matchRow(playedAt: '2026-11-21T00:00:02.000Z'),
          );
          throw StateError('simulated mid-transaction failure');
        }),
        throwsStateError,
      );
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM local_matches'),
        ),
        0,
      );
    });

    test('a successful transaction commits all its rows', () async {
      final database = await openInMemoryDatabase();
      final db = database.database;
      await db.transaction((txn) async {
        await txn.insert(
          'local_matches',
          matchRow(playedAt: '2026-11-21T00:00:01.000Z'),
        );
        await txn.insert(
          'local_matches',
          matchRow(playedAt: '2026-11-21T00:00:02.000Z'),
        );
      });
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM local_matches'),
        ),
        2,
      );
    });
  });

  group('serialization round-trip', () {
    test('players_json and snapshot_json survive verbatim', () async {
      final database = await openInMemoryDatabase();
      final db = database.database;
      const playersJson =
          '{"seats":[{"name":"Åsa \\"Ace\\" 🎲","colour":"red","isAi":false},'
          '{"name":"Bob\\nSecond line","colour":"blue","isAi":true}],'
          '"note":"back\\\\slash / unicode \\u00e9"}';
      const snapshotJson =
          '{"version":1,"players":[{"tokens":[[0,1,2,3]]}],'
          '"nested":{"a":[true,null,{"b":"c"}]}}';
      final matchId = await db.insert(
        'local_matches',
        matchRow(
          playedAt: '2026-11-21T00:00:00.000Z',
          playersJson: playersJson,
        ),
      );
      await db.insert('saved_match_snapshots', <String, Object?>{
        'match_key': 'current',
        'snapshot_json': snapshotJson,
        'saved_at': '2026-11-21T00:00:00.000Z',
      });

      final matches = await db.query(
        'local_matches',
        where: 'id = ?',
        whereArgs: [matchId],
      );
      expect(matches.single['players_json'], playersJson);
      final snapshots = await db.query('saved_match_snapshots');
      expect(snapshots.single['snapshot_json'], snapshotJson);
    });
  });

  group('500-match pruning (NFR-36)', () {
    test(
      'prune keeps the newest 500 and leaves statistics untouched',
      () async {
        final database = await openInMemoryDatabase();
        final db = database.database;
        // 501 matches, one per second, oldest first.
        final batch = db.batch();
        for (var i = 0; i <= 500; i++) {
          final playedAt = DateTime.utc(
            2026,
            1,
            1,
          ).add(Duration(seconds: i)).toIso8601String();
          batch.insert('local_matches', matchRow(playedAt: playedAt));
        }
        await batch.commit(noResult: true);
        // Lifetime totals maintained incrementally (as recordMatch
        // does in M1.4) — the prune must not touch this row.
        await db.update(
          'local_statistics',
          <String, Object?>{
            'matches_played': 501,
            'matches_won': 300,
            'matches_vs_ai': 200,
            'matches_local': 301,
            'updated_at': '2026-11-21T00:00:00.000Z',
          },
          where: 'id = ?',
          whereArgs: [1],
        );

        final deleted = await db.rawDelete(DiceUpDatabase.pruneLocalMatchesSql);
        expect(deleted, 1);
        expect(
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM local_matches'),
          ),
          500,
        );
        // The oldest match (i = 0) is gone; the next-oldest (i = 1)
        // is the earliest survivor.
        final oldest = DateTime.utc(2026, 1, 1).toIso8601String();
        expect(
          Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM local_matches WHERE played_at = ?',
              [oldest],
            ),
          ),
          0,
        );
        final earliestRow = await db.rawQuery(
          'SELECT played_at FROM local_matches ORDER BY played_at ASC '
          'LIMIT 1',
        );
        expect(
          earliestRow.single['played_at'],
          DateTime.utc(
            2026,
            1,
            1,
          ).add(const Duration(seconds: 1)).toIso8601String(),
        );

        // Statistics row is byte-identical to before the prune.
        final stats = await db.query('local_statistics');
        expect(stats.single, {
          'id': 1,
          'matches_played': 501,
          'matches_won': 300,
          'matches_vs_ai': 200,
          'matches_local': 301,
          'updated_at': '2026-11-21T00:00:00.000Z',
        });
      },
    );

    test(
      'prune tie-break: identical played_at keeps the highest ids',
      () async {
        final database = await openInMemoryDatabase();
        final db = database.database;
        const playedAt = '2026-06-01T12:00:00.000Z';
        final batch = db.batch();
        for (var i = 0; i <= 500; i++) {
          batch.insert('local_matches', matchRow(playedAt: playedAt));
        }
        await batch.commit(noResult: true);

        await db.rawDelete(DiceUpDatabase.pruneLocalMatchesSql);
        expect(
          Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM local_matches'),
          ),
          500,
        );
        // Lowest id (first inserted) pruned; highest id retained.
        final minId = Sqflite.firstIntValue(
          await db.rawQuery('SELECT MIN(id) FROM local_matches'),
        );
        expect(minId, 2);
        final maxId = Sqflite.firstIntValue(
          await db.rawQuery('SELECT MAX(id) FROM local_matches'),
        );
        expect(maxId, 501);
      },
    );
  });

  group('openDiceUpDatabase factory helper', () {
    test('opens a seeded v1 database with an injected factory', () async {
      final dir = await Directory.systemTemp.createTemp('diceup_m13_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final database = await openDiceUpDatabase(
        factory: databaseFactoryFfi,
        path: p.join(dir.path, 'diceup.db'),
      );
      addTearDown(database.close);
      expect(database.isOpen, isTrue);
      expect(await database.database.getVersion(), 1);
      final stats = await database.database.query('local_statistics');
      expect(stats.single['matches_played'], 0);
      final settings = await database.database.query('local_settings');
      expect(settings, hasLength(3));
    });
  });
}
