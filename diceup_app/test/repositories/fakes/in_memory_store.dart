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

  /// Derives the aggregates from the RETAINED matches — valid only
  /// while the retained history is complete (see [isHistoryComplete]).
  /// Once pruning (NFR-36) has removed rows, the retained 500 cannot
  /// reconstruct lifetime totals, so this derivation must never be
  /// used to maintain the cached row on the write path: it is the
  /// single source of truth for the derivation, used by
  /// `recomputeFromHistory` when history is provably complete, and
  /// for the empty initial state. (D-24: `matchesWon` counts
  /// human-seat wins only.)
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

  /// Updates the cached aggregates INCREMENTALLY from the previous
  /// cached values plus one newly recorded match — the only way the
  /// write path maintains lifetime totals (D-24, NFR-36). Deriving
  /// from the retained match list would lose the pruned matches:
  /// after the 501st record the retained list holds at most 501
  /// rows, so a derivation would freeze `matchesPlayed` at 501
  /// while the true lifetime total keeps growing.
  ///
  /// `matchesPlayed` + 1 always; `matchesVsAi` or `matchesLocal` + 1
  /// by mode; `matchesWon` + 1 if and only if the winner is a human
  /// seat (an AI win does not increment it). `updatedAt` is stamped
  /// from the store clock.
  void applyMatchToStatistics(LocalMatch match) {
    final current = statistics;
    statistics = LocalStatistics(
      matchesPlayed: current.matchesPlayed + 1,
      matchesWon:
          current.matchesWon + (match.winnerIsHuman ? 1 : 0),
      matchesVsAi: current.matchesVsAi +
          (match.mode == LocalMatchMode.vsAi ? 1 : 0),
      matchesLocal: current.matchesLocal +
          (match.mode == LocalMatchMode.vsAi ? 0 : 1),
      updatedAt: now,
    );
  }

  /// Whether the retained match history is provably complete, i.e.
  /// whether `computeStatistics()` may be used to repair the cached
  /// row. True in exactly two cases:
  ///
  /// (a) fewer than [kMaxLocalMatches] rows are retained: pruning
  /// leaves exactly 500 rows and only `clearHistory` (which resets
  /// the statistics to zero) can drop the count below 500, so a
  /// count below 500 means no pruning has happened since the last
  /// clear — the retained history is the whole history.
  ///
  /// (b) the retained count equals the cached `matchesPlayed`: no
  /// rows have been removed (pruning would leave the retained count
  /// strictly below the lifetime total, except when exactly 500
  /// matches were recorded and none pruned — complete either way).
  ///
  /// Residual limitation: (b) can be fooled if the cached
  /// `matchesPlayed` is corrupted to exactly equal the retained
  /// count while rows were pruned (e.g. true lifetime 700, retained
  /// 500, cache corrupted 700 → 500) — then a repair would derive
  /// the retained-window aggregates and present them as lifetime
  /// totals. (a) has no such hole: it does not depend on the cache.
  /// The guard also assumes the retained match rows themselves are
  /// intact; silent loss of committed match rows is outside the
  /// threat model (M1.5 handles whole-database corruption by
  /// recreating). When in doubt the guard refuses repair rather than
  /// destroying data: an incomplete history returns the cached row
  /// unchanged.
  bool get isHistoryComplete =>
      matches.length < kMaxLocalMatches ||
      matches.length == statistics.matchesPlayed;
}
