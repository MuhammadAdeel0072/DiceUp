import 'package:diceup/domain/repositories/local_player_repository.dart';
import 'package:sqflite/sqflite.dart';

import 'sqlite_serialization.dart';

/// SQLite [LocalPlayerRepository] (M1.4, SDD §9.1 `local_players`).
///
/// Takes the open [Database]. A seat with a null id is inserted
/// under a fresh AUTOINCREMENT id; a seat with an id is stored under
/// that id (insert or replace). `lastUsedAt` is stored exactly as
/// given — never stamped with the clock.
class SqliteLocalPlayerRepository implements LocalPlayerRepository {
  SqliteLocalPlayerRepository(this._db);

  final Database _db;

  @override
  Future<LocalPlayerSeat> upsertSeat(LocalPlayerSeat seat) async {
    if (seat.id == null) {
      final id = await _db.insert('local_players', seatToRow(seat));
      return seat.copyWith(id: id);
    }
    // Insert-or-replace under the given id. REPLACE deletes the old
    // row and inserts the new one; with no foreign keys on this
    // table that is exactly an upsert, and the id is preserved.
    await _db.insert(
      'local_players',
      seatToRow(seat),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return seat;
  }

  @override
  Future<List<LocalPlayerSeat>> listRecentSeats() async {
    // `last_used_at IS NULL` sorts first (0 = has a timestamp, 1 =
    // null), so seats with no `lastUsedAt` sort last; ties break by
    // id descending. (SQLite sorts NULLs first under plain DESC,
    // which would put never-used seats at the top.)
    final rows = await _db.query(
      'local_players',
      orderBy: 'last_used_at IS NULL ASC, last_used_at DESC, id DESC',
    );
    return rows.map(seatFromRow).toList();
  }
}
