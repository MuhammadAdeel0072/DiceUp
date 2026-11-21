import 'package:diceup/domain/repositories/local_statistics_repository.dart';

import 'in_memory_store.dart';

/// In-memory [LocalStatisticsRepository] for tests.
///
/// Reads the cached aggregates from the shared [InMemoryStore] — the
/// same store the match fake updates on every `recordMatch`.
/// `recomputeFromHistory` repairs the cache only when the retained
/// history is provably complete (see [InMemoryStore.isHistoryComplete]);
/// after pruning, the cached lifetime totals are returned unchanged,
/// because the retained 500 matches cannot reconstruct them.
class InMemoryLocalStatisticsRepository
    implements LocalStatisticsRepository {
  InMemoryLocalStatisticsRepository(this._store);

  final InMemoryStore _store;

  @override
  Future<LocalStatistics> getStatistics() async {
    _store.throwIfFailing();
    return _store.statistics;
  }

  @override
  Future<LocalStatistics> recomputeFromHistory() async {
    _store.throwIfFailing();
    if (!_store.isHistoryComplete) {
      // Incomplete history: the retained matches cannot reconstruct
      // lifetime totals, so the cached row is returned unchanged —
      // no write, `updatedAt` untouched. Deriving here would silently
      // reduce the lifetime totals to the retained window.
      return _store.statistics;
    }
    _store.statistics = _store.computeStatistics();
    return _store.statistics;
  }
}
