import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite schema and open lifecycle for the local DiceUp database
/// (SDD §9.1; FR-29–32; NFR-30, NFR-35, NFR-36).
///
/// The database holds exactly the five SDD §9.1 tables — no sixth
/// table, no extra column — and no foreign keys: the local tables are
/// deliberately independent so a corrupt row in one cannot cascade
/// into the others. All writes are transactional (NFR-30); the
/// repositories in M1.4 perform each multi-step operation inside one
/// transaction, and `onCreate` below runs inside sqflite's creation
/// transaction, so the schema and its seed rows commit together or
/// not at all.
///
/// The database holds no passwords, no tokens and no rules (CON-02,
/// CI-06). Whole-database corruption is handled in M1.5 by
/// `openDatabaseWithRecovery` in `database_recovery.dart` (recreate
/// on unreadable database, NFR-35); this class only opens a healthy
/// database, or creates a fresh one — call [open] directly when the
/// caller wants a plain open that throws on corruption instead of
/// recovering.
///
/// ## Single instance
///
/// Construct [DiceUpDatabase] with the [DatabaseFactory] for the
/// platform ([databaseFactory] on mobile, `databaseFactoryFfi` from
/// `sqflite_common_ffi` in tests/desktop) and call [open] once.
/// [open] is idempotent: a second call returns the same open
/// [Database] instead of opening the database again, and [close]
/// releases it so a later [open] can reopen the same file. (sqflite
/// also single-instances per path by default; this class does not
/// opt out of that.)
///
/// The app entry point is [openDiceUpDatabase] in
/// `database_factory.dart`, which resolves the platform database
/// path; tests construct [DiceUpDatabase] directly with an
/// in-memory or temp-file path.
class DiceUpDatabase {
  /// Creates the database handle. Does not touch disk until [open].
  DiceUpDatabase({required this.factory, required this.path});

  /// Schema version. Version 1 is the first version: fresh installs
  /// only, no migrations.
  static const int version = 1;

  /// Database file name inside the platform databases directory.
  static const String fileName = 'diceup.db';

  /// `CREATE TABLE` statements for the five SDD §9.1 tables, in
  /// dependency-free order (no foreign keys, so any order works).
  static const List<String> createTableStatements = [
    // One row per completed offline match (FR-30, FR-31).
    '''
CREATE TABLE local_matches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  played_at TEXT NOT NULL,
  mode TEXT NOT NULL,
  player_count INTEGER NOT NULL CHECK (player_count >= 2 AND player_count <= 4),
  players_json TEXT NOT NULL,
  winner_index INTEGER NULL,
  winner_name TEXT NULL,
  duration_seconds INTEGER NULL,
  ruleset_version TEXT NOT NULL,
  created_at TEXT NOT NULL
)''',
    // Single-row aggregates, cached for instant display (FR-32).
    // Lifetime totals, maintained incrementally by recordMatch —
    // never derived from the (capped) match list on the write path
    // (D-24/M1.7, b0f7ab0 correction).
    '''
CREATE TABLE local_statistics (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  matches_played INTEGER NOT NULL DEFAULT 0,
  matches_won INTEGER NOT NULL DEFAULT 0,
  matches_vs_ai INTEGER NOT NULL DEFAULT 0,
  matches_local INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
)''',
    // Sound, vibration, last-used match options (FR-08, FR-32).
    '''
CREATE TABLE local_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''',
    // Local/guest seat identities (FR-14).
    '''
CREATE TABLE local_players (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  display_name TEXT NOT NULL,
  colour TEXT NOT NULL,
  is_ai INTEGER NOT NULL DEFAULT 0,
  difficulty TEXT NULL,
  last_used_at TEXT NULL
)''',
    // At most one in-progress offline match for resume (FR-29).
    '''
CREATE TABLE saved_match_snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  match_key TEXT NOT NULL UNIQUE,
  snapshot_json TEXT NOT NULL,
  saved_at TEXT NOT NULL
)''',
  ];

  /// Index on `local_matches.played_at DESC` for the
  /// reverse-chronological history list (FR-31).
  static const String createPlayedAtIndexStatement =
      'CREATE INDEX idx_local_matches_played_at '
      'ON local_matches (played_at DESC)';

  /// Deletes every match row except the newest [kMaxLocalMatches],
  /// newest first by `played_at DESC, id DESC` (NFR-36). The `id
  /// DESC` tie-break keeps the most recently inserted row when two
  /// matches share a `played_at` timestamp. Run inside the same
  /// transaction as the match insert + statistics update (M1.4).
  ///
  /// The prune never touches `local_statistics`: the cached row is
  /// a lifetime total maintained incrementally, and pruning must
  /// not reset or rewrite it.
  static const String pruneLocalMatchesSql =
      'DELETE FROM local_matches WHERE id NOT IN '
      '(SELECT id FROM local_matches '
      'ORDER BY played_at DESC, id DESC LIMIT $kMaxLocalMatches)';

  /// Creates the schema and seeds the initial rows. Runs inside
  /// sqflite's creation transaction: schema + seeds commit together.
  ///
  /// Seeds the single statistics row (id = 1, all zeros) and the
  /// three fixed default settings ([kDefaultSettings], D-25). The
  /// last-used options (`last_mode`, `last_player_count`,
  /// `last_difficulties`) have no fixed default and are NOT seeded —
  /// they stay absent until the user plays a match.
  static Future<void> onCreate(Database db, int version) async {
    for (final statement in createTableStatements) {
      await db.execute(statement);
    }
    await db.execute(createPlayedAtIndexStatement);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('local_statistics', <String, Object?>{
      'id': 1,
      'matches_played': 0,
      'matches_won': 0,
      'matches_vs_ai': 0,
      'matches_local': 0,
      'updated_at': now,
    });
    for (final entry in kDefaultSettings.entries) {
      await db.insert('local_settings', <String, Object?>{
        'key': entry.key,
        'value': entry.value,
        'updated_at': now,
      });
    }
  }

  /// Upgrade stub: schema version 1 is the first version, so there
  /// is no migration path yet. Fails closed rather than silently
  /// leaving a stale schema behind — a future version adds its
  /// migration case here (and only here).
  static Future<void> onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    throw UnsupportedError(
      'DiceUp database upgrade from v$oldVersion to v$newVersion '
      'has no migration defined.',
    );
  }

  /// The factory that opens the database file: the platform
  /// [databaseFactory] in the app, `databaseFactoryFfi` in tests.
  final DatabaseFactory factory;

  /// Filesystem path of the database file (`inMemoryDatabasePath`
  /// for a throwaway in-memory database in tests).
  final String path;

  Database? _db;
  Future<Database>? _opening;

  /// Whether the database is currently open.
  bool get isOpen => _db != null;

  /// The open database. Throws [StateError] until [open] completes.
  Database get database {
    final db = _db;
    if (db == null) {
      throw StateError('DiceUp database is not open yet — call open() first.');
    }
    return db;
  }

  /// Opens the database (creating + seeding it on first use) and
  /// returns the shared instance. Idempotent: while open, returns
  /// the same [Database]; concurrent calls share one in-flight open.
  Future<Database> open() {
    final existing = _db;
    if (existing != null) return Future.value(existing);
    return _opening ??= _open();
  }

  Future<Database> _open() async {
    try {
      final db = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: version,
          onCreate: onCreate,
          onUpgrade: onUpgrade,
        ),
      );
      _db = db;
      return db;
    } finally {
      _opening = null;
    }
  }

  /// Closes the database. A later [open] reopens the same file;
  /// rows written before the close survive (they are on disk).
  Future<void> close() async {
    final opening = _opening;
    if (opening != null) {
      // A failed open must not make close() throw the open's error;
      // there is simply nothing to close in that case.
      try {
        await opening;
      } catch (_) {
        // Ignore: the open already reported this failure.
      }
    }
    final db = _db;
    _db = null;
    await db?.close();
  }
}
