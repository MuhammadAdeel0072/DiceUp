import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/local_player_repository.dart';
import 'package:diceup/domain/repositories/local_statistics_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';

/// Thrown by the in-memory fakes when failure injection is armed (see
/// [InMemoryStore.failNextCall]). Test support only — it never comes
/// from a real repository implementation.
class InMemoryRepositoryFailure implements Exception {
  const InMemoryRepositoryFailure([
    this.message = 'Simulated repository failure.',
  ]);

  final String message;

  @override
  String toString() => 'InMemoryRepositoryFailure: $message';
}

/// Shared backing store for the in-memory repository fakes.
///
/// The fakes for matches, statistics and snapshots share one store so
/// that multi-step operations behave as single indivisible operations
/// — exactly the transactional semantics the SQLite implementations
/// provide in M1.4 (NFR-30): `recordMatch` inserts the match, updates
/// the cached statistics, prunes history and deletes the in-progress
/// snapshot in one call; `clearHistory` clears matches and resets
/// statistics together; `recomputeFromHistory` reads the same match
/// list the match fake writes. No `await` separates the steps of one
/// operation, so no interleaving is possible.
///
/// The maps hold the domain value objects directly (they are
/// immutable, so sharing references is safe). Ids auto-increment
/// from 1, like AUTOINCREMENT.
///
/// [clock] supplies "now" for the cached statistics' `updatedAt`;
/// tests pass a fixed clock for deterministic timestamps. It defaults
/// to [DateTime.now]. The store never stamps any other timestamp —
/// match `playedAt`/`createdAt`, snapshot `savedAt` and seat
/// `lastUsedAt` all come from the caller.
class InMemoryStore {
  InMemoryStore({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    statistics = computeStatistics();
  }

  final DateTime Function() _clock;

  /// "Now" according to the store's clock.
  DateTime get now => _clock();

  /// Recorded matches by id.
  final Map<int, LocalMatch> matches = {};

  /// Cached aggregates (single row, like `local_statistics` id = 1).
  late LocalStatistics statistics;

  /// Stored settings by key.
  final Map<String, String> settings = {};

  /// Saved snapshots by match key.
  final Map<String, SavedSnapshot> snapshots = {};

  /// Stored seats by id.
  final Map<int, LocalPlayerSeat> seats = {};

  int _nextMatchId = 1;
  int _nextSeatId = 1;

  /// The next match id (AUTOINCREMENT from 1).
  int takeNextMatchId() => _nextMatchId++;

  /// The next seat id (AUTOINCREMENT from 1).
  int takeNextSeatId() => _nextSeatId++;

  Object? _nextFailure;

  /// Arms a one-shot failure: the NEXT repository call on any fake
  /// sharing this store throws [error] (default
  /// [InMemoryRepositoryFailure]), then the flag clears itself, so
  /// the call after that succeeds. Lets M3 use-case tests verify
  /// error propagation without a real database failure.
  void failNextCall([
    Object error = const InMemoryRepositoryFailure(),
  ]) {
    _nextFailure = error;
  }

  /// Throws the armed failure, if any, and disarms it. Every fake
  /// method calls this first.
  void throwIfFailing() {
    final failure = _nextFailure;
    if (failure != null) {
      _nextFailure = null;
      throw failure;
    }
  }

  /// Derives the cached aggregates from the stored matches — the
  /// single source of truth for the derivation, used both by
  /// `recordMatch` (after every insert) and by `recomputeFromHistory`
  /// (D-24: `matchesWon` counts human-seat wins only).
  LocalStatistics computeStatistics() {
    var played = 0;
    var won = 0;
    var vsAi = 0;
    var local = 0;
    for (final match in matches.values) {
      played++;
      if (match.mode == LocalMatchMode.vsAi) {
        vsAi++;
      } else {
        local++;
      }
      if (match.winnerIsHuman) won++;
    }
    return LocalStatistics(
      matchesPlayed: played,
      matchesWon: won,
      matchesVsAi: vsAi,
      matchesLocal: local,
      updatedAt: now,
    );
  }
}
