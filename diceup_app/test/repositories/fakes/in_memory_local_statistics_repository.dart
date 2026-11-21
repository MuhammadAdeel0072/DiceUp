import 'package:diceup/domain/repositories/local_statistics_repository.dart';

import 'in_memory_store.dart';

/// In-memory [LocalStatisticsRepository] for tests.
///
/// Reads the cached aggregates from the shared [InMemoryStore] — the
/// same store the match fake updates on every `recordMatch`, so the
/// cache and the history can never disagree except when a test
/// diverges them deliberately (to exercise `recomputeFromHistory`).
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
    _store.statistics = _store.computeStatistics();
    return _store.statistics;
  }
}
