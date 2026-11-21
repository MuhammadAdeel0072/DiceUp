import 'package:diceup/data/local/diceup_database.dart';
import 'package:diceup/data/local/sqlite_local_match_repository.dart';
import 'package:diceup/data/local/sqlite_local_player_repository.dart';
import 'package:diceup/data/local/sqlite_local_statistics_repository.dart';
import 'package:diceup/data/local/sqlite_settings_repository.dart';
import 'package:diceup/data/local/sqlite_snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../repositories/repository_contract_test.dart';

/// M1.4: the SAME contract suite as the in-memory fakes, run against
/// the SQLite repositories.
///
/// Each test gets a fresh in-memory ffi database (opened + seeded by
/// `DiceUpDatabase`, closed after the test). The repositories under
/// test share that one database, exactly as the fakes share one
/// [InMemoryStore].
///
/// One fixture difference, and why: the contract suite's settings
/// group assumes an EMPTY settings store (the fakes start empty —
/// `getSetting('sound_enabled')` is null, `getAllSettings()` is
/// empty on a fresh repository). The real database seeds the three
/// fixed defaults at creation (M1.3, D-25), so a genuinely fresh
/// SQLite database does NOT satisfy those two assumptions. The
/// factory therefore clears the seeded settings rows, so this run
/// tests the repository logic against an empty store — the same
/// starting state the fake run has. Seeded-default visibility
/// through the SQLite settings repository is proven separately in
/// `sqlite_repositories_test.dart` ("seeded defaults are visible on
/// a fresh database"), and the M1.3 tests prove the seeding itself.
/// The statistics seed (all zeros) needs no such treatment: it
/// already matches the contract's fresh-state expectations.
void main() {
  sqfliteFfiInit();

  defineRepositoryContractTests(() async {
    final database = DiceUpDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    addTearDown(database.close);
    await database.open();
    // Clear the seeded defaults: see the file doc comment above.
    await database.database.delete('local_settings');
    final db = database.database;
    return RepositorySet(
      matches: SqliteLocalMatchRepository(db),
      statistics: SqliteLocalStatisticsRepository(db),
      settings: SqliteSettingsRepository(db),
      snapshots: SqliteSnapshotRepository(db),
      players: SqliteLocalPlayerRepository(db),
    );
  });
}
