import '../ai/ai_player.dart';
import '../engine/player_colour.dart';

/// Maximum number of completed matches kept in local history (NFR-36,
/// SDD §9.1). Recording beyond this prunes the oldest matches, so the
/// history never grows without bound.
const int kMaxLocalMatches = 500;

/// Offline match mode (SDD §9.1 `local_matches.mode`).
enum LocalMatchMode {
  vsAi,
  localMultiplayer;

  /// Storage label used in `local_matches.mode` (SDD §9.1).
  String get label => switch (this) {
        vsAi => 'vs_ai',
        localMultiplayer => 'local_multiplayer',
      };

  /// Parses a storage label back to a mode. Throws [FormatException]
  /// on an unknown label — never silently defaults to a mode.
  static LocalMatchMode fromLabel(String label) => switch (label) {
        'vs_ai' => vsAi,
        'local_multiplayer' => localMultiplayer,
        _ => throw FormatException('Unknown match mode "$label".'),
      };
}

/// One seat of a completed offline match, as stored in history
/// (SDD §9.1 `local_matches.players_json`).
///
/// The list is structured at the domain layer so the per-player
/// breakdown is available without parsing JSON (D-24: a human-seat
/// win is labelled per player; an AI win does not increment the human
/// total). The SQLite layer (M1.4) serialises these seats into
/// `players_json`; the domain layer never traffics in the raw string.
class LocalMatchPlayer {
  LocalMatchPlayer({
    required this.name,
    required this.colour,
    required this.isAi,
    this.difficulty,
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError('A match player must have a non-empty name.');
    }
    if (!isAi && difficulty != null) {
      throw ArgumentError('A human seat has no difficulty.');
    }
  }

  /// Display name of the seat (e.g. 'Player 1', 'CPU').
  final String name;

  final PlayerColour colour;

  /// True for an AI seat, false for a human seat.
  final bool isAi;

  /// AI difficulty; null for human seats. A null difficulty on an AI
  /// seat means "unspecified" and is treated as easy where it is used
  /// (matching `Player.fromJson`, which defaults a missing difficulty
  /// to easy).
  final AiDifficulty? difficulty;

  @override
  bool operator ==(Object other) =>
      other is LocalMatchPlayer &&
      other.name == name &&
      other.colour == colour &&
      other.isAi == isAi &&
      other.difficulty == difficulty;

  @override
  int get hashCode => Object.hash(name, colour, isAi, difficulty);
}

/// One completed offline match (SDD §9.1 `local_matches`, FR-30/FR-31).
///
/// A row exists only for a completed match (D-12: exited matches are
/// NOT recorded). Immutable; [players] is an unmodifiable view.
class LocalMatch {
  LocalMatch({
    this.id,
    required this.playedAt,
    required this.mode,
    required this.playerCount,
    required List<LocalMatchPlayer> players,
    this.winnerIndex,
    this.winnerName,
    this.durationSeconds,
    required this.rulesetVersion,
    required this.createdAt,
  }) : players = List.unmodifiable(players) {
    if (id != null && id! < 1) {
      throw ArgumentError('A match id must be at least 1.');
    }
    if (playerCount < 2 || playerCount > 4) {
      throw ArgumentError(
        'A match must have 2–4 players (got $playerCount).',
      );
    }
    if (players.length != playerCount) {
      throw ArgumentError(
        'A match with playerCount $playerCount must list exactly '
        '$playerCount players (got ${players.length}).',
      );
    }
    if (winnerIndex != null &&
        (winnerIndex! < 0 || winnerIndex! >= playerCount)) {
      throw ArgumentError(
        'Winner index $winnerIndex is out of range for $playerCount '
        'players.',
      );
    }
    if (winnerIndex == null && winnerName != null) {
      throw ArgumentError(
        'A match without a winner cannot have a winner name.',
      );
    }
    if (durationSeconds != null && durationSeconds! < 0) {
      throw ArgumentError('A match duration cannot be negative.');
    }
  }

  /// Row id; null before the match is recorded (assigned on insert,
  /// like AUTOINCREMENT).
  final int? id;

  /// When the match was played (ISO-8601 in storage).
  final DateTime playedAt;

  final LocalMatchMode mode;

  /// Number of seats (2–4); always equal to [players].length.
  final int playerCount;

  /// The seats in seat order.
  final List<LocalMatchPlayer> players;

  /// Index of the winning seat, or null when the match has no winner
  /// recorded.
  final int? winnerIndex;

  /// Display name of the winner, or null when [winnerIndex] is null.
  final String? winnerName;

  /// Match duration in seconds, or null when unknown. Computed from
  /// `startedAt` by the wiring (M1.6), not by the engine.
  final int? durationSeconds;

  /// Version of the ruleset the match was played under (BR-14).
  final String rulesetVersion;

  /// When the row was created (ISO-8601 in storage).
  final DateTime createdAt;

  /// The winning seat, or null when [winnerIndex] is null.
  LocalMatchPlayer? get winner =>
      winnerIndex == null ? null : players[winnerIndex!];

  /// True when the winner is a human seat (D-24: only a human win
  /// increments `matches_won`).
  bool get winnerIsHuman => winner?.isAi == false;

  LocalMatch copyWith({
    int? id,
    DateTime? playedAt,
    LocalMatchMode? mode,
    int? playerCount,
    List<LocalMatchPlayer>? players,
    int? winnerIndex,
    String? winnerName,
    int? durationSeconds,
    String? rulesetVersion,
    DateTime? createdAt,
  }) =>
      LocalMatch(
        id: id ?? this.id,
        playedAt: playedAt ?? this.playedAt,
        mode: mode ?? this.mode,
        playerCount: playerCount ?? this.playerCount,
        players: players ?? this.players,
        winnerIndex: winnerIndex ?? this.winnerIndex,
        winnerName: winnerName ?? this.winnerName,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        rulesetVersion: rulesetVersion ?? this.rulesetVersion,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  bool operator ==(Object other) {
    if (other is! LocalMatch) return false;
    if (other.id != id ||
        other.playedAt != playedAt ||
        other.mode != mode ||
        other.playerCount != playerCount ||
        other.winnerIndex != winnerIndex ||
        other.winnerName != winnerName ||
        other.durationSeconds != durationSeconds ||
        other.rulesetVersion != rulesetVersion ||
        other.createdAt != createdAt) {
      return false;
    }
    if (other.players.length != players.length) return false;
    for (var i = 0; i < players.length; i++) {
      if (other.players[i] != players[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        playedAt,
        mode,
        playerCount,
        Object.hashAll(players),
        winnerIndex,
        winnerName,
        durationSeconds,
        rulesetVersion,
        createdAt,
      );
}

/// Completed offline matches (SDD §4.3, §9.1 `local_matches`).
///
/// All methods are async: the SQLite implementation (M1.4) is async,
/// so the contract is async from the start. Implementations must
/// never expose SQLite (or any other store) through this interface.
abstract class LocalMatchRepository {
  /// Records a completed match.
  ///
  /// In ONE transaction (NFR-30): inserts the match row, updates the
  /// cached statistics, prunes history beyond [kMaxLocalMatches], and
  /// deletes the in-progress snapshot (SDD §6.6: a finished match can
  /// never resurrect). Any `id` on [match] is ignored — a fresh id is
  /// assigned, like AUTOINCREMENT. Returns the stored match with its
  /// assigned id.
  Future<LocalMatch> recordMatch(LocalMatch match);

  /// All recorded matches, newest first: `played_at` DESC, `id` DESC
  /// tiebreak (two matches played in the same instant keep insertion
  /// order, newest first).
  Future<List<LocalMatch>> listMatches();

  /// The match with [id], or null when no such match is recorded.
  Future<LocalMatch?> getMatch(int id);

  /// Deletes all recorded matches AND resets the cached statistics to
  /// zero, in the same operation (SDD §9.1: `clearHistory` also resets
  /// statistics). In-progress snapshots are untouched.
  Future<void> clearHistory();

  /// Number of recorded matches.
  Future<int> countMatches();
}
