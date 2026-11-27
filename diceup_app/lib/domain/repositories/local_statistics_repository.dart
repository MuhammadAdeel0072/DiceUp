/// Cached aggregate statistics for completed offline matches
/// (SDD §9.1 `local_statistics`, FR-32).
///
/// These are LIFETIME totals, maintained incrementally by
/// `LocalMatchRepository.recordMatch` from the previous cached values
/// plus each newly recorded match — they are independent of the
/// 500-match history cap (NFR-36, D-24/M1.7). They are derivable from
/// `local_matches` ONLY while the retained history is complete
/// (fewer than 500 rows, or the retained count equals
/// `matchesPlayed`): once pruning has removed rows, the retained 500
/// cannot reconstruct lifetime totals, and `recomputeFromHistory`
/// refuses repair rather than overwriting them with the retained
/// window. Exactly one write path mutates them —
/// `LocalMatchRepository.recordMatch` / `clearHistory` — plus the
/// guarded repair in `recomputeFromHistory`.
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
  }) => LocalStatistics(
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

  /// Repair path — but only when the retained history is provably
  /// complete. History is complete iff fewer than 500 matches are
  /// retained (pruning leaves exactly 500, and only `clearHistory` —
  /// which resets the statistics to zero — can drop the count below
  /// 500, so a lower count means no pruning has happened since the
  /// last clear) or the retained count equals the cached
  /// `matchesPlayed` (no rows removed). When complete, derives the
  /// aggregates from the retained history (D-24: `matchesWon` counts
  /// human-seat wins only), stores them as the new cached statistics
  /// and returns them. When incomplete, returns the cached
  /// statistics UNCHANGED — no write, `updatedAt` untouched — because
  /// exact lifetime reconstruction from the retained 500 alone is
  /// impossible: deriving here would silently reduce the lifetime
  /// totals to the retained window.
  ///
  /// Residual limitation: the retained-count-equals-cached-totals
  /// check can be fooled if the cached `matchesPlayed` is corrupted
  /// to exactly equal the retained count while rows were pruned; then
  /// a repair derives the retained-window aggregates and presents
  /// them as lifetime totals. Exact repair after pruning plus cache
  /// corruption would need either the complete match history or a
  /// durably persisted record of the pruned-away aggregates — the
  /// approved schema retains neither, so introducing such a record
  /// would be a schema decision requiring approval, not part of this
  /// contract.
  Future<LocalStatistics> recomputeFromHistory();
}
