/// Cached aggregate statistics for completed offline matches
/// (SDD §9.1 `local_statistics`, FR-32).
///
/// The aggregates are derivable from `local_matches` but cached in a
/// single row (`id = 1`) for instant display. Exactly one write path
/// mutates them — `LocalMatchRepository.recordMatch` /
/// `clearHistory` — so the cache cannot drift from the history except
/// through storage corruption, which `recomputeFromHistory` repairs.
class LocalStatistics {
  LocalStatistics({
    required this.matchesPlayed,
    required this.matchesWon,
    required this.matchesVsAi,
    required this.matchesLocal,
    required this.updatedAt,
  }) {
    if (matchesPlayed < 0 ||
        matchesWon < 0 ||
        matchesVsAi < 0 ||
        matchesLocal < 0) {
      throw ArgumentError('Statistics counts cannot be negative.');
    }
  }

  /// Total completed offline matches recorded.
  final int matchesPlayed;

  /// Matches won by a human seat (D-24: an AI win does NOT increment
  /// this — the human total counts human wins only).
  final int matchesWon;

  /// Completed matches played against the AI.
  final int matchesVsAi;

  /// Completed local-multiplayer matches.
  final int matchesLocal;

  /// When the cached row was last updated.
  final DateTime updatedAt;

  LocalStatistics copyWith({
    int? matchesPlayed,
    int? matchesWon,
    int? matchesVsAi,
    int? matchesLocal,
    DateTime? updatedAt,
  }) =>
      LocalStatistics(
        matchesPlayed: matchesPlayed ?? this.matchesPlayed,
        matchesWon: matchesWon ?? this.matchesWon,
        matchesVsAi: matchesVsAi ?? this.matchesVsAi,
        matchesLocal: matchesLocal ?? this.matchesLocal,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is LocalStatistics &&
      other.matchesPlayed == matchesPlayed &&
      other.matchesWon == matchesWon &&
      other.matchesVsAi == matchesVsAi &&
      other.matchesLocal == matchesLocal &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        matchesPlayed,
        matchesWon,
        matchesVsAi,
        matchesLocal,
        updatedAt,
      );
}

/// Cached offline-match statistics (SDD §4.3, §9.1 `local_statistics`).
///
/// All methods are async: the SQLite implementation (M1.4) is async,
/// so the contract is async from the start.
abstract class LocalStatisticsRepository {
  /// The cached aggregates. All counts are zero when no match has
  /// been recorded — never null.
  Future<LocalStatistics> getStatistics();

  /// Repair path: derives the aggregates from the recorded match
  /// history and stores them as the new cached statistics, then
  /// returns them. After this call, [getStatistics] returns the
  /// recomputed values. The derivation is exactly the same as the one
  /// `LocalMatchRepository.recordMatch` applies on every insert
  /// (D-24: `matchesWon` counts human-seat wins only).
  Future<LocalStatistics> recomputeFromHistory();
}
