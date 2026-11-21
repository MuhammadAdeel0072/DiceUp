import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';

import 'in_memory_store.dart';

/// In-memory [LocalMatchRepository] for tests.
///
/// Backed by the shared [InMemoryStore], so `recordMatch` performs
/// its four steps (insert, statistics update, cap prune, in-progress
/// snapshot delete) indivisibly, and `clearHistory` resets matches
/// and statistics together — the transactional semantics the SQLite
/// implementation provides in M1.4.
class InMemoryLocalMatchRepository implements LocalMatchRepository {
  InMemoryLocalMatchRepository(this._store);

  final InMemoryStore _store;

  @override
  Future<LocalMatch> recordMatch(LocalMatch match) async {
    _store.throwIfFailing();
    final stored = match.copyWith(id: _store.takeNextMatchId());
    _store.matches[stored.id!] = stored;
    _store.statistics = _store.computeStatistics();
    _prune();
    _store.snapshots.remove(kCurrentMatchKey);
    return stored;
  }

  void _prune() {
    if (_store.matches.length <= kMaxLocalMatches) return;
    for (final match in _orderedMatches().skip(kMaxLocalMatches)) {
      _store.matches.remove(match.id);
    }
  }

  List<LocalMatch> _orderedMatches() {
    final list = _store.matches.values.toList();
    list.sort((a, b) {
      final byPlayedAt = b.playedAt.compareTo(a.playedAt);
      if (byPlayedAt != 0) return byPlayedAt;
      return b.id!.compareTo(a.id!);
    });
    return list;
  }

  @override
  Future<List<LocalMatch>> listMatches() async {
    _store.throwIfFailing();
    return _orderedMatches();
  }

  @override
  Future<LocalMatch?> getMatch(int id) async {
    _store.throwIfFailing();
    return _store.matches[id];
  }

  @override
  Future<void> clearHistory() async {
    _store.throwIfFailing();
    _store.matches.clear();
    _store.statistics = _store.computeStatistics();
  }

  @override
  Future<int> countMatches() async {
    _store.throwIfFailing();
    return _store.matches.length;
  }
}
