/// Corrupt-database recovery (M1.5, SDD §9.1 + §14, SRS NFR-35).
///
/// If the local SQLite database is unreadable at startup, the app
/// notifies the user, recreates the database and remains playable
/// instead of crashing. Recovery lives here — not in
/// [DiceUpDatabase], which only opens a healthy database (or creates
/// a fresh one) — so a plain [DiceUpDatabase.open] keeps throwing on
/// corruption and only the startup path opts into recovery.
///
/// ## What counts as corruption
///
/// Exactly two failures, both at open time:
///
/// 1. The database open itself throws — the file is not a database,
///    the file cannot be read, or `onUpgrade` fails closed for an
///    unknown schema version. Any exception from the open counts;
///    the open path cannot distinguish "corrupt" from "unreadable",
///    and either way the app cannot use the file.
/// 2. The post-open verification read fails ([verifyDatabase]): a
///    core table is missing from `sqlite_master`, the single
///    `local_statistics` row (id = 1) is missing, or the read itself
///    throws. The verification proves the database is readable
///    before any repository touches it.
///
/// ## What does NOT count as corruption
///
/// A failed repository query AFTER a successful open + verification
/// is never corruption: repositories keep throwing normally, the
/// database file and its data survive, and no recovery is attempted
/// (see `test/data/local/database_recovery_test.dart`: a single
/// failed query and a mid-match failure leave the database
/// untouched). Recovery runs only inside [openDatabaseWithRecovery],
/// never from a repository, so a transient app-level error can never
/// wipe valid history.
///
/// ## Bounds
///
/// Recovery is a single attempt, never a loop: close any half-open
/// handle, delete the unreadable file, recreate schema v1 (which
/// seeds the statistics row and the D-25 defaults), verify the
/// recreation. If any step of the recreation fails, the error
/// surfaces to the caller — recovery never reports success it did
/// not achieve and never silently swallows a failure.
///
/// The recreated database is empty by design (SDD §14: "history is
/// lost, the game is not"). Nothing is backed up or restored: the
/// local database holds no passwords, no tokens and no rules, and
/// the only data in it is regenerable history, settings and one
/// in-progress snapshot.
library;

import 'dart:developer';

import 'package:sqflite/sqflite.dart';

import 'diceup_database.dart';

/// The exact user-facing message shown once when the local database
/// could not be read and was recreated (SDD §14, NFR-35).
///
/// Defined once here so the startup flow (M1.6) shows exactly this
/// text. It carries no technical detail and no stack trace — the
/// diagnostics for the recovery event go to the developer log only
/// (see [openDatabaseWithRecovery]).
const String kDatabaseRecoveryMessage =
    "Your local history couldn't be read, so it was reset. "
    'You can keep playing.';

/// The result of opening the database with recovery.
///
/// [recovered] is true only when the previous database file was
/// unreadable and this open deleted + recreated it; a second open
/// of the healthy recreated database reports `recovered: false`, so
/// the startup flow (M1.6) can show [kDatabaseRecoveryMessage]
/// exactly once per recovery event.
class DatabaseOpenResult {
  const DatabaseOpenResult({
    required this.handle,
    required this.recovered,
  });

  /// The open database handle. Close it with
  /// [DiceUpDatabase.close] when the app shuts down.
  final DiceUpDatabase handle;

  /// True when this open recovered from an unreadable database.
  final bool recovered;

  /// The open, verified [Database] behind [handle].
  Database get database => handle.database;
}

/// Verifies that [db] is a readable DiceUp database: all five
/// SDD §9.1 tables exist and the single `local_statistics` row
/// (id = 1) is present.
///
/// Throws [StateError] when the shape is wrong (a missing table or
/// the missing statistics row) and lets the underlying sqflite
/// exception propagate when the read itself fails. Either way the
/// caller treats the failure as corruption (see the criteria above).
///
/// Deliberately narrow: it proves readability, nothing more. A
/// missing default-settings row is NOT corruption — the settings
/// repository falls back to the D-25 defaults for unset keys — and
/// no `PRAGMA integrity_check` runs here: a database that still
/// reads is usable, and wiping it for a failing page check would
/// destroy history the app could still serve.
Future<void> verifyDatabase(Database db) async {
  final tableRows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  final names = <String>{
    for (final row in tableRows) row['name'] as String,
  };
  const requiredTables = <String>{
    'local_matches',
    'local_statistics',
    'local_settings',
    'local_players',
    'saved_match_snapshots',
  };
  final missing = requiredTables.difference(names);
  if (missing.isNotEmpty) {
    throw StateError(
      'DiceUp database failed verification: missing tables '
      '${missing.join(', ')}.',
    );
  }
  final statisticsRows = await db.query(
    'local_statistics',
    columns: ['id'],
    where: 'id = ?',
    whereArgs: [1],
    limit: 1,
  );
  if (statisticsRows.isEmpty) {
    throw StateError(
      'DiceUp database failed verification: the local_statistics '
      'row (id = 1) is missing.',
    );
  }
}

/// Opens [database] with corruption recovery (NFR-35).
///
/// On a healthy database this is a plain open + verification and
/// returns `recovered: false`. When the open or the verification
/// fails, it makes exactly one recovery attempt — close any
/// half-open handle, delete the unreadable file, recreate schema v1
/// and verify the recreation — and returns `recovered: true` with a
/// fresh, usable database (statistics row id = 1 at zero, D-25
/// defaults seeded, no matches, no snapshot).
///
/// If the recreation itself fails, the failure surfaces as an
/// error: no infinite loop, no silent success, and no half-open
/// handle is left behind (a recreated handle that fails
/// verification is closed before the error propagates).
///
/// The recovery event is logged (error type only — the log never
/// carries snapshot JSON, player names or any other user data) so a
/// corrupt database is diagnosable without exposing private data.
Future<DatabaseOpenResult> openDatabaseWithRecovery(
  DiceUpDatabase database,
) async {
  if (database.isOpen) {
    return DatabaseOpenResult(handle: database, recovered: false);
  }
  try {
    await database.open();
    await verifyDatabase(database.database);
    return DatabaseOpenResult(handle: database, recovered: false);
  } catch (error) {
    // The open or the verification read failed: the database is
    // unreadable by the criteria above. Log the failure (type +
    // message only — sqflite's messages carry the file path and the
    // verification SQL, never user data) and recover below.
    log(
      'DiceUp database unreadable at startup ($error); recreating it.',
      name: 'DiceUpDatabaseRecovery',
    );
  }
  // Exactly one recovery attempt. Closing first releases any
  // half-open handle from the failed open/verification; close() is
  // a no-op when the open threw before assigning a handle.
  try {
    await database.close();
  } catch (_) {
    // Best effort: the reopen below surfaces any real problem.
  }
  // An in-memory database has no file to delete — reopening it
  // already yields a fresh empty database.
  if (database.path != inMemoryDatabasePath) {
    // A delete failure surfaces: without the delete there is no
    // recreation, so the caller must hear about it rather than get
    // a stale corrupt file reopened as if it were fresh.
    await database.factory.deleteDatabase(database.path);
  }
  try {
    await database.open();
    await verifyDatabase(database.database);
  } catch (error) {
    // Do not hand the caller a half-recreated handle: a recreated
    // database that fails verification is still unreadable.
    try {
      await database.close();
    } catch (_) {
      // Best effort: the original error is the one that matters.
    }
    rethrow;
  }
  log(
    'DiceUp database recreated after corruption; local history '
    'was reset.',
    name: 'DiceUpDatabaseRecovery',
  );
  return DatabaseOpenResult(handle: database, recovered: true);
}
