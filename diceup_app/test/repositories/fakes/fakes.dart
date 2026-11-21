/// In-memory repository fakes for tests (M1.2).
///
/// The fakes share one [InMemoryStore] per repository set, so
/// multi-step operations (recordMatch, clearHistory,
/// recomputeFromHistory) behave as single indivisible operations —
/// the transactional semantics the SQLite implementations provide in
/// M1.4. Test support only; never imported by production code.
library;

export 'in_memory_local_match_repository.dart';
export 'in_memory_local_player_repository.dart';
export 'in_memory_local_statistics_repository.dart';
export 'in_memory_settings_repository.dart';
export 'in_memory_snapshot_repository.dart';
export 'in_memory_store.dart';
