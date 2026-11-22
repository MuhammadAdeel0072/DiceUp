/// Match key for the single in-progress offline match (SDD §9.1
/// `saved_match_snapshots.match_key`). At most one in-progress match
/// is ever saved for resume (FR-29); it is stored under this key and
/// deleted on completion or abandonment, so a stale snapshot can
/// never resurrect a finished match.
const String kCurrentMatchKey = 'current';

/// One saved in-progress match snapshot (SDD §9.1
/// `saved_match_snapshots`).
///
/// The snapshot JSON is OPAQUE to the repository: it is a serialised
/// `GameState` string, stored and returned verbatim. No rule parsing
/// happens in the data layer — a snapshot that fails strict parsing
/// is corrupt and the caller deletes it (M1.6).
class SavedSnapshot {
  SavedSnapshot({
    required this.matchKey,
    required this.snapshotJson,
    required this.savedAt,
  }) {
    if (matchKey.isEmpty) {
      throw ArgumentError('A snapshot match key must not be empty.');
    }
    if (snapshotJson.isEmpty) {
      throw ArgumentError('A snapshot JSON must not be empty.');
    }
  }

  /// Key the snapshot is stored under (unique). The in-progress
  /// match uses [kCurrentMatchKey].
  final String matchKey;

  /// Serialised `GameState` JSON, stored verbatim.
  final String snapshotJson;

  /// When the snapshot was saved.
  final DateTime savedAt;

  SavedSnapshot copyWith({
    String? matchKey,
    String? snapshotJson,
    DateTime? savedAt,
  }) => SavedSnapshot(
    matchKey: matchKey ?? this.matchKey,
    snapshotJson: snapshotJson ?? this.snapshotJson,
    savedAt: savedAt ?? this.savedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is SavedSnapshot &&
      other.matchKey == matchKey &&
      other.snapshotJson == snapshotJson &&
      other.savedAt == savedAt;

  @override
  int get hashCode => Object.hash(matchKey, snapshotJson, savedAt);
}

/// In-progress match snapshots for resume (SDD §4.3, §9.1
/// `saved_match_snapshots`; FR-29).
///
/// All methods are async: the SQLite implementation (M1.4) is async,
/// so the contract is async from the start.
abstract class SnapshotRepository {
  /// Saves [snapshot], replacing any snapshot stored under the same
  /// match key (upsert — at most one row per key).
  Future<void> saveSnapshot(SavedSnapshot snapshot);

  /// The snapshot stored under [matchKey], or null when none is
  /// stored under it.
  Future<SavedSnapshot?> loadSnapshot(String matchKey);

  /// Deletes the snapshot stored under [matchKey]. A no-op when none
  /// is stored under it — never throws for a missing key.
  Future<void> deleteSnapshot(String matchKey);

  /// True when a snapshot is stored under [matchKey].
  Future<bool> hasSnapshot(String matchKey);
}
