import 'engine/game_state.dart';

/// The ordered snapshot writer the game controller persists through
/// (M3.2, seam 3).
///
/// The production implementation is the data layer's [SnapshotSaver]
/// (`lib/data/local/app_dependencies.dart`): saves are chained onto
/// one tail future so writes land in submission order, and
/// [invalidate]/[discard] bump a generation so a save queued before
/// a match completes or is discarded can never land after the
/// snapshot row is deleted. The interface lives in the domain layer
/// so the controller can use that queue without importing the data
/// layer (SDD §4.2: the domain has no database imports) — the data
/// layer depends on the domain, never the reverse.
///
/// A controller constructed without a writer falls back to direct
/// [SnapshotRepository] writes for roll saves (and the
/// [ApplyMove] use case's direct path for move saves); that mode is
/// for tests and degraded play without persistence, never for the
/// production screen, which always passes the app's saver.
abstract class SnapshotWriter {
  /// Queues a save of [state] under the single in-progress key.
  /// Returns immediately; the write lands in submission order.
  /// Never throws into the caller.
  void save(GameState state);

  /// Drops every save queued so far (they are skipped when their
  /// turn comes) without touching the stored row. Used when a match
  /// completes: the record deletes the snapshot in its own
  /// transaction, and no stale write may land after that delete.
  void invalidate();

  /// Discards the in-progress match: drops every queued save, waits
  /// for any write already in flight, then deletes the stored row.
  /// Never throws: exiting must never trap the user behind storage.
  Future<void> discard();
}
