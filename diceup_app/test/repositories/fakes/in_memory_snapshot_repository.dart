import 'package:diceup/domain/repositories/snapshot_repository.dart';

import 'in_memory_store.dart';

/// In-memory [SnapshotRepository] for tests.
///
/// Stores snapshots by match key in the shared [InMemoryStore]. The
/// snapshot JSON is held verbatim and never parsed.
class InMemorySnapshotRepository implements SnapshotRepository {
  InMemorySnapshotRepository(this._store);

  final InMemoryStore _store;

  @override
  Future<void> saveSnapshot(SavedSnapshot snapshot) async {
    _store.throwIfFailing();
    _store.snapshots[snapshot.matchKey] = snapshot;
  }

  @override
  Future<SavedSnapshot?> loadSnapshot(String matchKey) async {
    _store.throwIfFailing();
    return _store.snapshots[matchKey];
  }

  @override
  Future<void> deleteSnapshot(String matchKey) async {
    _store.throwIfFailing();
    _store.snapshots.remove(matchKey);
  }

  @override
  Future<bool> hasSnapshot(String matchKey) async {
    _store.throwIfFailing();
    return _store.snapshots.containsKey(matchKey);
  }
}
