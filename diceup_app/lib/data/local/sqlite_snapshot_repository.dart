import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:sqflite/sqflite.dart';

import 'sqlite_serialization.dart';

/// SQLite [SnapshotRepository] (M1.4, SDD §9.1
/// `saved_match_snapshots`).
///
/// Takes the open [Database]. The snapshot JSON is opaque: stored
/// and returned verbatim, never parsed.
class SqliteSnapshotRepository implements SnapshotRepository {
  SqliteSnapshotRepository(this._db);

  final Database _db;

  @override
  Future<void> saveSnapshot(SavedSnapshot snapshot) async {
    await _db.rawInsert(
      'INSERT INTO saved_match_snapshots '
      '(match_key, snapshot_json, saved_at) VALUES (?, ?, ?) '
      'ON CONFLICT(match_key) DO UPDATE SET '
      'snapshot_json = excluded.snapshot_json, '
      'saved_at = excluded.saved_at',
      [
        snapshot.matchKey,
        snapshot.snapshotJson,
        toUtcIso(snapshot.savedAt),
      ],
    );
  }

  @override
  Future<SavedSnapshot?> loadSnapshot(String matchKey) async {
    final rows = await _db.query(
      'saved_match_snapshots',
      where: 'match_key = ?',
      whereArgs: [matchKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return snapshotFromRow(rows.single);
  }

  @override
  Future<void> deleteSnapshot(String matchKey) async {
    // A no-op when nothing is stored under the key — never throws
    // for a missing key.
    await _db.delete(
      'saved_match_snapshots',
      where: 'match_key = ?',
      whereArgs: [matchKey],
    );
  }

  @override
  Future<bool> hasSnapshot(String matchKey) async {
    final rows = await _db.query(
      'saved_match_snapshots',
      columns: ['id'],
      where: 'match_key = ?',
      whereArgs: [matchKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}
