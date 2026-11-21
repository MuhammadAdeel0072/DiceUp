/// Default settings (SDD §9.1 `local_settings`, M1.3 schema).
///
/// Only the keys with a fixed default are listed here. The last-used
/// match options (`last_mode`, `last_player_count`,
/// `last_difficulties`) have no fixed default — they are absent until
/// the user plays a match. `sound_volume` defaults to '100' (D-25).
const Map<String, String> kDefaultSettings = {
  'sound_enabled': '1',
  'vibration_enabled': '1',
  'sound_volume': '100',
};

/// Local settings (SDD §4.3, §9.1 `local_settings`; FR-08, FR-32).
///
/// A plain key/value string store. Values are opaque strings — the
/// repository never parses them (a corrupt value is the caller's
/// problem, handled by falling back to the default, never by throwing
/// here). All methods are async: the SQLite implementation (M1.4) is
/// async, so the contract is async from the start.
abstract class SettingsRepository {
  /// The value stored under [key], or null when nothing is stored
  /// under it. Defaults are NOT returned automatically: a null means
  /// "unset", and the caller falls back to [kDefaultSettings] (or its
  /// own default) for keys that have one.
  Future<String?> getSetting(String key);

  /// Stores [value] under [key], replacing any previous value.
  Future<void> setSetting(String key, String value);

  /// All stored settings as a new map. Mutating the returned map
  /// does not affect the store.
  Future<Map<String, String>> getAllSettings();

  /// Removes all stored settings and writes [kDefaultSettings] in
  /// their place. Keys without a fixed default (the `last_*`
  /// last-used options) are absent afterwards, until set again.
  Future<void> resetToDefaults();
}
