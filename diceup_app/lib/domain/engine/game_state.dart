import 'player.dart';

/// Turn state machine (SDD §6.4).
enum TurnPhase {
  /// Waiting for the active player to roll.
  awaitingRoll,

  /// A roll is outstanding; waiting for the active player (or AI) to
  /// choose one of the legal moves.
  awaitingMove,

  /// A player has won (BR-11); no further actions are possible.
  finished,
}

/// An immutable snapshot of a whole match (SDD §6.1).
///
/// Every transition takes a [GameState] and returns a new one; the UI,
/// the AI and the resume store all observe snapshots and never mutate
/// live state. A snapshot serialises to JSON, which is how resume
/// (SRS FR-29) and the shared rule test vectors (SDD §6.9) work.
class GameState {
  const GameState({
    required this.players,
    required this.currentPlayerIndex,
    required this.rulesetVersion,
    this.phase = TurnPhase.awaitingRoll,
    this.lastRoll = 0,
    this.consecutiveSixes = 0,
    this.winnerIndex,
    this.moveCount = 0,
    this.lastRollWasThirdSix = false,
    this.lastRollHadNoLegalMove = false,
  });

  /// Players in clockwise seat order.
  final List<Player> players;

  /// Index into [players] of the player whose turn it is.
  final int currentPlayerIndex;

  /// Version of the frozen ruleset (BR-14).
  final String rulesetVersion;

  final TurnPhase phase;

  /// Most recent dice value (0 = no roll yet in this turn).
  final int lastRoll;

  /// Sixes rolled in the current turn sequence (BR-07).
  final int consecutiveSixes;

  /// Index of the winner once the match is finished (BR-11).
  final int? winnerIndex;

  /// Number of moves applied since the match started.
  final int moveCount;

  /// The last roll was a third consecutive six: it was shown but not
  /// played, and the turn passed (BR-07).
  final bool lastRollWasThirdSix;

  /// The last roll offered no legal move (BR-13).
  final bool lastRollHadNoLegalMove;

  Player get currentPlayer => players[currentPlayerIndex];
  bool get isFinished => phase == TurnPhase.finished;

  GameState copyWith({
    List<Player>? players,
    int? currentPlayerIndex,
    TurnPhase? phase,
    int? lastRoll,
    int? consecutiveSixes,
    int? winnerIndex,
    int? moveCount,
    bool? lastRollWasThirdSix,
    bool? lastRollHadNoLegalMove,
  }) {
    return GameState(
      players: players ?? this.players,
      currentPlayerIndex: currentPlayerIndex ?? this.currentPlayerIndex,
      rulesetVersion: rulesetVersion,
      phase: phase ?? this.phase,
      lastRoll: lastRoll ?? this.lastRoll,
      consecutiveSixes: consecutiveSixes ?? this.consecutiveSixes,
      winnerIndex: winnerIndex ?? this.winnerIndex,
      moveCount: moveCount ?? this.moveCount,
      lastRollWasThirdSix: lastRollWasThirdSix ?? this.lastRollWasThirdSix,
      lastRollHadNoLegalMove:
          lastRollHadNoLegalMove ?? this.lastRollHadNoLegalMove,
    );
  }

  /// Initial state for a fresh match: all tokens in their yards.
  factory GameState.initial({
    required List<Player> players,
    required String rulesetVersion,
  }) {
    return GameState(
      players: List.unmodifiable(players),
      currentPlayerIndex: 0,
      rulesetVersion: rulesetVersion,
    );
  }

  Map<String, Object?> toJson() => {
        'formatVersion': 1,
        'rulesetVersion': rulesetVersion,
        'currentPlayerIndex': currentPlayerIndex,
        'phase': phase.name,
        'lastRoll': lastRoll,
        'consecutiveSixes': consecutiveSixes,
        'winnerIndex': winnerIndex,
        'moveCount': moveCount,
        'lastRollWasThirdSix': lastRollWasThirdSix,
        'lastRollHadNoLegalMove': lastRollHadNoLegalMove,
        'players': players.map((p) => p.toJson()).toList(),
      };

  factory GameState.fromJson(Map<String, Object?> json) {
    final rawPlayers = (json['players'] as List?) ?? [];
    final players = List<Player>.generate(
      rawPlayers.length,
      (i) => Player.fromJson(i, rawPlayers[i] as Map<String, Object?>),
    );
    final phase = TurnPhase.values.firstWhere(
      (p) => p.name == json['phase'],
      orElse: () => TurnPhase.awaitingRoll,
    );
    return GameState(
      players: players,
      currentPlayerIndex: json['currentPlayerIndex'] as int? ?? 0,
      rulesetVersion: json['rulesetVersion'] as String? ?? '1.0.0',
      phase: phase,
      lastRoll: json['lastRoll'] as int? ?? 0,
      consecutiveSixes: json['consecutiveSixes'] as int? ?? 0,
      winnerIndex: json['winnerIndex'] as int?,
      moveCount: json['moveCount'] as int? ?? 0,
      lastRollWasThirdSix: json['lastRollWasThirdSix'] as bool? ?? false,
      lastRollHadNoLegalMove:
          json['lastRollHadNoLegalMove'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'GameState(player=$currentPlayerIndex phase=$phase '
      'roll=$lastRoll sixes=$consecutiveSixes winner=$winnerIndex)';
}
