import 'package:diceup/domain/repositories/settings_repository.dart';

import 'in_memory_store.dart';

/// In-memory [SettingsRepository] for tests.
///
/// Stores plain key/value strings in the shared [InMemoryStore]. The
/// store starts empty — defaults are NOT pre-populated; a missing key
/// reads as null until it is set or [resetToDefaults] writes the
/// defaults in.
class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository(this._store);

  final InMemoryStore _store;

  @override
  Future<String?> getSetting(String key) async {
    _store.throwIfFailing();
    return _store.settings[key];
  }

  @override
  Future<void> setSetting(String key, String value) async {
    _store.throwIfFailing();
    _store.settings[key] = value;
  }

  @override
  Future<Map<String, String>> getAllSettings() async {
    _store.throwIfFailing();
    return Map.of(_store.settings);
  }

  @override
  Future<void> resetToDefaults() async {
    _store.throwIfFailing();
    _store.settings
      ..clear()
      ..addAll(kDefaultSettings);
  }
}
