import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:sqflite/sqflite.dart';

import 'sqlite_serialization.dart';

/// SQLite [SettingsRepository] (M1.4, SDD §9.1 `local_settings`).
///
/// A plain key/value string store over the open [Database]. Values
/// are opaque strings — never parsed here. Defaults are NOT
/// auto-returned: [getSetting] returns null when nothing is stored
/// under the key, and the caller falls back to [kDefaultSettings].
/// (The database seeds the three fixed defaults at creation, so on
/// a fresh install those keys ARE stored — see the M1.3 tests.)
class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._db);

  final Database _db;

  @override
  Future<String?> getSetting(String key) async {
    final rows = await _db.query(
      'local_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.single['value'] as String;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    final now = toUtcIso(DateTime.now());
    await _db.rawInsert(
      'INSERT INTO local_settings (key, value, updated_at) '
      'VALUES (?, ?, ?) '
      'ON CONFLICT(key) DO UPDATE SET '
      'value = excluded.value, updated_at = excluded.updated_at',
      [key, value, now],
    );
  }

  @override
  Future<Map<String, String>> getAllSettings() async {
    final rows = await _db.query('local_settings');
    return {
      for (final row in rows)
        row['key'] as String: row['value'] as String,
    };
  }

  @override
  Future<void> resetToDefaults() async {
    final now = toUtcIso(DateTime.now());
    await _db.transaction((txn) async {
      await txn.delete('local_settings');
      for (final entry in kDefaultSettings.entries) {
        await txn.insert('local_settings', <String, Object?>{
          'key': entry.key,
          'value': entry.value,
          'updated_at': now,
        });
      }
      // Keys without a fixed default (the `last_*` last-used
      // options) stay absent until set again.
    });
  }
}
