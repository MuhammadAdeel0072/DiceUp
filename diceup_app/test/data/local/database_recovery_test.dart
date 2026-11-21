import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:diceup/data/local/database_factory.dart';
import 'package:diceup/data/local/database_recovery.dart';
import 'package:diceup/data/local/diceup_database.dart';
import 'package:diceup/data/local/snapshot_recovery.dart';
import 'package:diceup/data/local/sqlite_local_match_repository.dart';
import 'package:diceup/data/local/sqlite_local_statistics_repository.dart';
import 'package:diceup/data/local/sqlite_settings_repository.dart';
import 'package:diceup/data/local/sqlite_snapshot_repository.dart';
import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'failing_database.dart';

/// M1.5 corrupt-database recovery (NFR-35) + corrupt-snapshot
/// rejection (D-22) tests.
///
/// Controlled failure injection throughout: no test corrupts a
/// developer's real database. Genuine corruption is built with real
/// files — garbage bytes for an unreadable file, a dropped core
/// table for a file that opens but fails the verification read — and
/// a throwing factory for a recreation that itself fails. Ordinary
/// failures reuse the M1.4 [FailingDatabase] pattern (plus a
/// read-failing subclass below) to prove they never trigger
/// recovery.
void main() {
  sqfliteFfiInit();

  /// A fresh temp directory, deleted after the test.
  Future<Directory> tempDir() async {
    final dir = await Directory.systemTemp.createTemp('diceup_m15_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    return dir;
  }

  /// A [DiceUpDatabase] handle on a temp file, closed after the test.
  DiceUpDatabase tempHandle(String path, {DatabaseFactory? factory}) {
    final database = DiceUpDatabase(
      factory: factory ?? databaseFactoryFfi,
      path: path,
    );
    addTearDown(database.close);
    return database;
  }

  /// One completed 2-player match (human win), for seeding and for
  /// proving the repositories work on a recreated database.
  LocalMatch sampleMatch() => LocalMatch(
        playedAt: DateTime.utc(2026, 11, 21, 12, 0),
        mode: LocalMatchMode.vsAi,
        playerCount: 2,
        players: [
          LocalMatchPlayer(
            name: 'Red',
            colour: PlayerColour.red,
            isAi: false,
          ),
          LocalMatchPlayer(
            name: 'CPU',
            colour: PlayerColour.green,
            isAi: true,
            difficulty: AiDifficulty.easy,
          ),
        ],
        winnerIndex: 0,
        winnerName: 'Red',
        durationSeconds: 123,
        rulesetVersion: '1.0.0',
        createdAt: DateTime.utc(2026, 11, 21, 12, 0),
      );

  /// The five repositories on [db], for asserting on the database
  /// behind an open result.
  ({
    SqliteLocalMatchRepository matches,
    SqliteLocalStatisticsRepository statistics,
    SqliteSettingsRepository settings,
    SqliteSnapshotRepository snapshots,
  })
  openRepositories(Database db) => (
        matches: SqliteLocalMatchRepository(db),
        statistics: SqliteLocalStatisticsRepository(db),
        settings: SqliteSettingsRepository(db),
        snapshots: SqliteSnapshotRepository(db),
      );

  /// A valid in-progress snapshot JSON: a real 2-player match
  /// serialised by the engine, so it passes strict validation.
  String validSnapshotJson() {
    final game = LudoGame.newMatch(
      seats: const [
        SeatConfig(name: 'Red', colour: PlayerColour.red),
        SeatConfig(name: 'Green', colour: PlayerColour.green),
      ],
    );
    return jsonEncode(game.snapshot());
  }

  /// The valid snapshot JSON with [formatVersion] changed, so the
  /// document parses as JSON but fails strict `GameState`
  /// validation.
  String invalidSnapshotJson() {
    final decoded = jsonDecode(validSnapshotJson()) as Map<String, Object?>;
    decoded['formatVersion'] = 99;
    return jsonEncode(decoded);
  }

  group('openDatabaseWithRecovery — genuine corruption', () {
    test('garbage file: recovers, fresh schema v1, usable database',
        () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      // Garbage bytes: not a SQLite file at all, so the open throws.
      await File(path).writeAsBytes(
        List<int>.generate(64, (i) => (i * 7 + 3) % 256),
      );

      final result = await openDatabaseWithRecovery(tempHandle(path));

      expect(result.recovered, isTrue);
      final repos = openRepositories(result.database);
      // Fresh schema: the five tables exist (the verification read
      // already proved it) and the repositories work on it.
      final recorded = await repos.matches.recordMatch(sampleMatch());
      expect(recorded.id, isNotNull);
      expect(await repos.matches.countMatches(), 1);
      expect(await repos.settings.getSetting('sound_enabled'), '1');
      await result.handle.close();
    });

    test('dropped statistics table: open succeeds but verification '
        'fails, so recovery happens', () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      // A healthy database whose core table is then destroyed: the
      // file opens, but the statistics-row read cannot succeed.
      final healthy = tempHandle(path);
      await healthy.open();
      await healthy.database.execute('DROP TABLE local_statistics');
      await healthy.close();

      final result = await openDatabaseWithRecovery(tempHandle(path));

      expect(result.recovered, isTrue);
      final tables = await result.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = tables.map((row) => row['name'] as String).toSet();
      expect(
        names,
        containsAll([
          'local_matches',
          'local_statistics',
          'local_settings',
          'local_players',
          'saved_match_snapshots',
        ]),
      );
      await result.handle.close();
    });

    test('defaults after recovery: D-25 defaults present, last_* '
        'absent, statistics zeros', () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      await File(path).writeAsBytes(
        List<int>.generate(64, (i) => (i * 7 + 3) % 256),
      );

      final result = await openDatabaseWithRecovery(tempHandle(path));
      expect(result.recovered, isTrue);
      final repos = openRepositories(result.database);

      expect(await repos.settings.getAllSettings(), kDefaultSettings);
      expect(await repos.settings.getSetting('last_mode'), isNull);
      expect(await repos.settings.getSetting('last_player_count'), isNull);
      expect(await repos.settings.getSetting('last_difficulties'), isNull);
      final statistics = await repos.statistics.getStatistics();
      expect(statistics.matchesPlayed, 0);
      expect(statistics.matchesWon, 0);
      expect(statistics.matchesVsAi, 0);
      expect(statistics.matchesLocal, 0);
      expect(await repos.matches.countMatches(), 0);
      expect(
        await repos.snapshots.hasSnapshot(kCurrentMatchKey),
        isFalse,
      );
      await result.handle.close();
    });

    test('healthy database: opens normally, recovered is false, '
        'existing data untouched', () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      final first = tempHandle(path);
      await first.open();
      final seeded = openRepositories(first.database);
      await seeded.matches.recordMatch(sampleMatch());
      await seeded.settings.setSetting('sound_volume', '42');
      await first.close();

      // The factory helper is the entry point M1.6 will call.
      final result = await openDiceUpDatabaseWithRecovery(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(result.handle.close);

      expect(result.recovered, isFalse);
      final repos = openRepositories(result.database);
      expect(await repos.matches.countMatches(), 1);
      expect(await repos.settings.getSetting('sound_volume'), '42');
      final statistics = await repos.statistics.getStatistics();
      expect(statistics.matchesPlayed, 1);
      expect(statistics.matchesVsAi, 1);
    });

    test('recovery is reported exactly once per recovery event',
        () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      await File(path).writeAsBytes(
        List<int>.generate(64, (i) => (i * 7 + 3) % 256),
      );

      final recovered = await openDatabaseWithRecovery(tempHandle(path));
      expect(recovered.recovered, isTrue);
      await recovered.handle.close();

      // The recreated database is healthy: a second open reports
      // no recovery, and a repeat call on the open handle does too.
      final again = await openDatabaseWithRecovery(tempHandle(path));
      expect(again.recovered, isFalse);
      expect(
        (await openDatabaseWithRecovery(again.handle)).recovered,
        isFalse,
      );
      await again.handle.close();
    });

    test('recreation failure surfaces: factory throws on every open',
        () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      final database = tempHandle(
        path,
        factory: ThrowingDatabaseFactory(),
      );

      // No infinite loop and no silent success: the open failure
      // surfaces (the test itself would time out if recovery looped).
      await expectLater(
        openDatabaseWithRecovery(database),
        throwsA(isA<StateError>()),
      );
      expect(database.isOpen, isFalse);
    });

    test('recreation failure surfaces on an in-memory database too',
        () async {
      final database = DiceUpDatabase(
        factory: ThrowingDatabaseFactory(),
        path: inMemoryDatabasePath,
      );
      addTearDown(database.close);

      await expectLater(
        openDatabaseWithRecovery(database),
        throwsA(isA<StateError>()),
      );
      expect(database.isOpen, isFalse);
    });
  });

  group('openDatabaseWithRecovery — no reset on ordinary failures', () {
    test('a single failed query does NOT trigger recovery', () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      final database = tempHandle(path);
      await database.open();
      final inner = database.database;
      await SqliteLocalMatchRepository(inner).recordMatch(sampleMatch());
      // The repositories see a database whose reads throw; the
      // recovery path is never involved — no reopen happens here.
      final failing = FailingReadDatabase(inner, FailurePlan());
      final matches = SqliteLocalMatchRepository(failing);
      failing.failReads = true;
      await expectLater(
        matches.listMatches(),
        throwsA(isA<SimulatedRepositoryFailure>()),
      );
      failing.failReads = false;
      await database.close();

      // The file and its data survive the failed query: reopening
      // reports no recovery and the match is still there.
      expect(await File(path).exists(), isTrue);
      final reopened = await openDatabaseWithRecovery(tempHandle(path));
      expect(reopened.recovered, isFalse);
      expect(
        await SqliteLocalMatchRepository(
          reopened.database,
        ).countMatches(),
        1,
      );
      await reopened.handle.close();
    });

    test('a mid-match failure does NOT trigger recovery and leaves '
        'earlier data intact', () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      final database = tempHandle(path);
      await database.open();
      final inner = database.database;
      final plan = FailurePlan();
      final failing = FailingDatabase(inner, plan);
      final matches = SqliteLocalMatchRepository(failing);
      // One match records fine before the failure.
      await matches.recordMatch(sampleMatch());
      expect(await matches.countMatches(), 1);
      // The next recordMatch fails mid-transaction (2nd write: the
      // statistics update inside the same transaction).
      plan.arm(2);
      await expectLater(
        matches.recordMatch(sampleMatch()),
        throwsA(isA<SimulatedRepositoryFailure>()),
      );
      plan.disarm();
      // The failed match left nothing behind; the first match and
      // its statistics survive untouched.
      expect(await matches.countMatches(), 1);
      final statistics =
          await SqliteLocalStatisticsRepository(inner).getStatistics();
      expect(statistics.matchesPlayed, 1);
      await database.close();

      final reopened = await openDatabaseWithRecovery(tempHandle(path));
      expect(reopened.recovered, isFalse);
      expect(
        await SqliteLocalMatchRepository(
          reopened.database,
        ).countMatches(),
        1,
      );
      await reopened.handle.close();
    });
  });

  group('loadSnapshotForResume — corrupt snapshot (D-22)', () {
    test('valid snapshot: returned verbatim, row untouched', () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      final database = tempHandle(path);
      await database.open();
      final snapshots = SqliteSnapshotRepository(database.database);
      final json = validSnapshotJson();
      await snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: json,
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );

      final outcome = await loadSnapshotForResume(snapshots);

      expect(outcome, isA<ValidSnapshot>());
      expect((outcome as ValidSnapshot).snapshot.snapshotJson, json);
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isTrue);
      await database.close();
    });

    test('malformed JSON snapshot: row deleted, notice surfaced, '
        'other data untouched', () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      final database = tempHandle(path);
      await database.open();
      final repos = openRepositories(database.database);
      await repos.matches.recordMatch(sampleMatch());
      await repos.settings.setSetting('sound_volume', '42');
      await repos.snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: '{not valid json',
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );

      final outcome = await loadSnapshotForResume(repos.snapshots);

      // The load result distinguishes this case from "no snapshot":
      // a corrupt snapshot was found and discarded.
      expect(outcome, isA<CorruptSnapshotDiscarded>());
      expect(await repos.snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      expect(
        await repos.snapshots.loadSnapshot(kCurrentMatchKey),
        isNull,
      );
      // Everything else survives: only the bad snapshot row is gone.
      expect(await repos.matches.countMatches(), 1);
      expect(await repos.settings.getSetting('sound_volume'), '42');
      // The notice is defined once, and is NOT the database-recovery
      // message.
      expect(
        kCorruptSnapshotMessage,
        "Your saved match couldn't be read, so it was discarded. "
        'You can start a new match.',
      );
      expect(kCorruptSnapshotMessage, isNot(kDatabaseRecoveryMessage));
      await database.close();
    });

    test('valid JSON failing strict validation: row deleted, never '
        'restored', () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      final database = tempHandle(path);
      await database.open();
      final snapshots = SqliteSnapshotRepository(database.database);
      await snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: invalidSnapshotJson(),
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );

      final outcome = await loadSnapshotForResume(snapshots);

      expect(outcome, isA<CorruptSnapshotDiscarded>());
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      await database.close();
    });

    test('no snapshot: reported as absent, nothing deleted', () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      final database = tempHandle(path);
      await database.open();
      final snapshots = SqliteSnapshotRepository(database.database);

      expect(await loadSnapshotForResume(snapshots), isA<NoSnapshot>());

      await database.close();
    });

    test('a failed snapshot read propagates and does NOT delete the '
        'row', () async {
      final dir = await tempDir();
      final path = p.join(dir.path, 'diceup.db');
      final database = tempHandle(path);
      await database.open();
      final snapshots = SqliteSnapshotRepository(database.database);
      await snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: validSnapshotJson(),
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      final failing = FailingReadDatabase(database.database, FailurePlan());
      failing.failReads = true;

      // A read failure is a database error, not a corrupt snapshot:
      // it propagates instead of deleting the (valid) row.
      await expectLater(
        loadSnapshotForResume(SqliteSnapshotRepository(failing)),
        throwsA(isA<SimulatedRepositoryFailure>()),
      );
      failing.failReads = false;
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isTrue);
      await database.close();
    });
  });
}

/// A [DatabaseFactory] that throws on every open, delegating
/// everything else to the real ffi factory — so a test can prove a
/// recreation that itself fails surfaces instead of looping.
class ThrowingDatabaseFactory implements DatabaseFactory {
  @override
  Future<Database> openDatabase(
    String path, {
    OpenDatabaseOptions? options,
  }) =>
      throw StateError('Simulated database open failure.');

  @override
  Future<void> deleteDatabase(String path) =>
      databaseFactoryFfi.deleteDatabase(path);

  @override
  Future<bool> databaseExists(String path) =>
      databaseFactoryFfi.databaseExists(path);

  @override
  Future<String> getDatabasesPath() =>
      databaseFactoryFfi.getDatabasesPath();

  @override
  Future<void> setDatabasesPath(String path) =>
      databaseFactoryFfi.setDatabasesPath(path);

  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      databaseFactoryFfi.readDatabaseBytes(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      databaseFactoryFfi.writeDatabaseBytes(path, bytes);
}

/// A [FailingDatabase] whose reads also fail while [failReads] is
/// set — the M1.4 pattern extended to reads, so a test can make a
/// single repository query throw without touching the file.
class FailingReadDatabase extends FailingDatabase {
  // The super constructor's parameters are private to
  // failing_database.dart (`_inner`, `_plan`), so they cannot be
  // named as super parameters here.
  // ignore: use_super_parameters
  FailingReadDatabase(Database inner, FailurePlan plan)
      : super(inner, plan);

  bool failReads = false;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    if (failReads) {
      throw const SimulatedRepositoryFailure('Simulated read failure.');
    }
    return super.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    if (failReads) {
      throw const SimulatedRepositoryFailure('Simulated read failure.');
    }
    return super.rawQuery(sql, arguments);
  }
}
