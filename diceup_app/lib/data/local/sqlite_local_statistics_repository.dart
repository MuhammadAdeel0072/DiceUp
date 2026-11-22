import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/local_statistics_repository.dart';
import 'package:sqflite/sqflite.dart';

import 'sqlite_serialization.dart';

/// SQLite [LocalStatisticsRepository] (M1.4, SDD §9.1
/// `local_statistics`).
///
/// Reads the single cached row (id = 1, seeded with zeros by
/// `DiceUpDatabase.onCreate`). Takes the open [Database]; the cached row is maintained incrementally by
/// [SqliteLocalMatchRepository.recordMatch] / `clearHistory` — this
/// repository only reads it, plus the guarded repair below.
class SqliteLocalStatisticsRepository implements LocalStatisticsRepository {
  SqliteLocalStatisticsRepository(this._db);

  final Database _db;

  /// Reads the cached row. Never null: the row is seeded at database
  /// creation. A missing row means the database was tampered with
  /// outside the repositories — that is corruption, not a plain
  /// miss, so it throws [StateError] rather than inventing zeros
  /// (whole-database corruption is handled in M1.5).
  Future<LocalStatistics> _readCached(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'local_statistics',
      where: 'id = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError(
        'local_statistics row id = 1 is missing — the database is '
        'corrupt.',
      );
    }
    return statisticsFromRow(rows.single);
  }

  @override
  Future<LocalStatistics> getStatistics() => _readCached(_db);

  @override
  Future<LocalStatistics> recomputeFromHistory() async {
    return _db.transaction<LocalStatistics>((txn) async {
      final retained =
          Sqflite.firstIntValue(
            await txn.rawQuery('SELECT COUNT(*) FROM local_matches'),
          ) ??
          0;
      final cached = await _readCached(txn);

      // Guarded repair (b0f7ab0 correction — same semantics as the
      // in-memory fakes). History is complete iff fewer than
      // [kMaxLocalMatches] rows are retained (pruning leaves exactly
      // 500, and only `clearHistory` — which resets the statistics
      // to zero — can drop the count below 500) or the retained
      // count equals the cached `matchesPlayed` (no rows removed).
      final isComplete =
          retained < kMaxLocalMatches || retained == cached.matchesPlayed;
      if (!isComplete) {
        // Incomplete history: the retained matches cannot
        // reconstruct lifetime totals, so the cached row is returned
        // UNCHANGED — no write, `updatedAt` untouched. Deriving
        // here would silently reduce the lifetime totals to the
        // retained window.
        return cached;
      }

      // One read of the retained history; the aggregates are
      // derived in Dart so the human-win rule (D-24) can use the
      // decoded winner seat.
      final rows = await txn.query(
        'local_matches',
        columns: ['mode', 'players_json', 'winner_index'],
      );
      var played = 0;
      var won = 0;
      var vsAi = 0;
      var local = 0;
      for (final row in rows) {
        played++;
        final mode = LocalMatchMode.fromLabel(row['mode'] as String);
        if (mode == LocalMatchMode.vsAi) {
          vsAi++;
        } else {
          local++;
        }
        final winnerIndex = row['winner_index'] as int?;
        if (winnerIndex != null) {
          final players = decodePlayersJson(row['players_json'] as String);
          if (winnerIndex < 0 || winnerIndex >= players.length) {
            throw FormatException(
              'Stored winner_index $winnerIndex is out of range for '
              '${players.length} players.',
            );
          }
          if (!players[winnerIndex].isAi) won++;
        }
      }
      final now = toUtcIso(DateTime.now());
      final recomputed = LocalStatistics(
        matchesPlayed: played,
        matchesWon: won,
        matchesVsAi: vsAi,
        matchesLocal: local,
        updatedAt: DateTime.parse(now),
      );
      await txn.update(
        'local_statistics',
        <String, Object?>{
          'matches_played': played,
          'matches_won': won,
          'matches_vs_ai': vsAi,
          'matches_local': local,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [1],
      );
      return recomputed;
    });
  }
}

/// Known limitation (documented in the interface contract as well):
/// the retained-count-equals-cached-totals check can be fooled if
/// the cached `matchesPlayed` is corrupted to exactly equal the
/// retained count while rows were pruned (e.g. true lifetime 700,
/// retained 500, cache corrupted 700 → 500) — then a repair derives
/// the retained-window aggregates and presents them as lifetime
/// totals. Exact repair after pruning plus cache corruption would
/// need either the complete match history or a durably persisted
/// record of the pruned-away aggregates — the approved schema
/// retains neither, so no such record (e.g. a pruned-aggregates
/// table) is introduced here; adding one would be a schema decision
/// requiring approval.
