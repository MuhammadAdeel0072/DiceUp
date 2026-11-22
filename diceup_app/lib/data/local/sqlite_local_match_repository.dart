import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:sqflite/sqflite.dart';

import 'diceup_database.dart';
import 'sqlite_serialization.dart';

/// SQLite [LocalMatchRepository] (M1.4, SDD §9.1 `local_matches`).
///
/// Takes the open [Database] (the `DiceUpDatabase.database` handle
/// in the app; an in-memory ffi database in tests). Every multi-step
/// operation runs in a single transaction (NFR-30): if any step
/// fails, sqflite rolls the whole transaction back and rethrows, so
/// a failed `recordMatch` leaves no row, no statistics change, no
/// prune and no snapshot deletion behind.
class SqliteLocalMatchRepository implements LocalMatchRepository {
  SqliteLocalMatchRepository(this._db);

  final Database _db;

  @override
  Future<LocalMatch> recordMatch(LocalMatch match) async {
    final now = toUtcIso(DateTime.now());
    final wonIncrement = match.winnerIsHuman ? 1 : 0;
    final vsAiIncrement = match.mode == LocalMatchMode.vsAi ? 1 : 0;
    final localIncrement = match.mode == LocalMatchMode.vsAi ? 0 : 1;
    final id = await _db.transaction<int>((txn) async {
      // 1. Insert the match row. Any id on the argument is ignored:
      // the map carries no id, so AUTOINCREMENT assigns a fresh one.
      final insertedId = await txn.insert('local_matches', matchToRow(match));
      // 2. Maintain the lifetime statistics INCREMENTALLY from the
      // previous cached values (D-24, b0f7ab0 correction) — never
      // derive them from the retained match list, which is capped
      // at 500 rows and cannot reconstruct lifetime totals once
      // pruning has removed rows.
      await txn.rawUpdate(
        'UPDATE local_statistics SET '
        'matches_played = matches_played + 1, '
        'matches_won = matches_won + ?, '
        'matches_vs_ai = matches_vs_ai + ?, '
        'matches_local = matches_local + ?, '
        'updated_at = ? WHERE id = 1',
        [wonIncrement, vsAiIncrement, localIncrement, now],
      );
      // 3. Prune history beyond [kMaxLocalMatches] (NFR-36). The
      // prune never touches `local_statistics`.
      await txn.rawDelete(DiceUpDatabase.pruneLocalMatchesSql);
      // 4. Delete the in-progress snapshot (SDD §6.6: a finished
      // match can never resurrect). Only the `current` key — any
      // other snapshot is untouched.
      await txn.delete(
        'saved_match_snapshots',
        where: 'match_key = ?',
        whereArgs: [kCurrentMatchKey],
      );
      return insertedId;
    });
    return match.copyWith(id: id);
  }

  @override
  Future<List<LocalMatch>> listMatches() async {
    final rows = await _db.query(
      'local_matches',
      orderBy: 'played_at DESC, id DESC',
    );
    return rows.map(matchFromRow).toList();
  }

  @override
  Future<LocalMatch?> getMatch(int id) async {
    final rows = await _db.query(
      'local_matches',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return matchFromRow(rows.single);
  }

  @override
  Future<void> clearHistory() async {
    final now = toUtcIso(DateTime.now());
    await _db.transaction((txn) async {
      await txn.delete('local_matches');
      await txn.rawUpdate(
        'UPDATE local_statistics SET '
        'matches_played = 0, '
        'matches_won = 0, '
        'matches_vs_ai = 0, '
        'matches_local = 0, '
        'updated_at = ? WHERE id = 1',
        [now],
      );
      // Snapshots are deliberately untouched: clearing history does
      // not abandon an in-progress match.
    });
  }

  @override
  Future<int> countMatches() async {
    final count = Sqflite.firstIntValue(
      await _db.rawQuery('SELECT COUNT(*) FROM local_matches'),
    );
    return count ?? 0;
  }
}
