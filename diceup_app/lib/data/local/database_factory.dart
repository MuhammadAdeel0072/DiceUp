import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'database_recovery.dart';
import 'diceup_database.dart';

/// Opens the app's SQLite database at its platform location and
/// returns the shared [DiceUpDatabase] handle (SDD §9.1).
///
/// The app calls this with no arguments: [factory] defaults to
/// sqflite's platform [databaseFactory] and the file lives in the
/// platform databases directory under [DiceUpDatabase.fileName].
/// Tests pass `databaseFactoryFfi` (from `sqflite_common_ffi`) plus
/// an explicit [path] (in-memory or temp file) so no platform
/// directory resolution is needed on the Linux test VM.
///
/// The returned handle is already open; close it with
/// [DiceUpDatabase.close] when the app shuts down.
Future<DiceUpDatabase> openDiceUpDatabase({
  DatabaseFactory? factory,
  String? path,
}) async {
  final dbFactory = factory ?? databaseFactory;
  final dbPath =
      path ?? p.join(await getDatabasesPath(), DiceUpDatabase.fileName);
  final database = DiceUpDatabase(factory: dbFactory, path: dbPath);
  await database.open();
  return database;
}

/// Opens the app's SQLite database at its platform location with
/// corruption recovery (M1.5, NFR-35) and returns the open handle
/// plus whether recovery ran.
///
/// This is the entry point the startup flow (M1.6) calls: when
/// [DatabaseOpenResult.recovered] is true, the previous database
/// was unreadable and was recreated empty, and M1.6 shows
/// [kDatabaseRecoveryMessage] once. When it is false, the database
/// opened normally and no message is shown.
Future<DatabaseOpenResult> openDiceUpDatabaseWithRecovery({
  DatabaseFactory? factory,
  String? path,
}) async {
  final dbFactory = factory ?? databaseFactory;
  final dbPath =
      path ?? p.join(await getDatabasesPath(), DiceUpDatabase.fileName);
  final database = DiceUpDatabase(factory: dbFactory, path: dbPath);
  return openDatabaseWithRecovery(database);
}
