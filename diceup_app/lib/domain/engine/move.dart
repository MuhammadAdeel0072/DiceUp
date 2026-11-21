/// Identifies one token: its owner ([playerIndex]) and its index
/// among that player's tokens ([tokenIndex]).
class TokenRef {
  const TokenRef(this.playerIndex, this.tokenIndex);

  final int playerIndex;
  final int tokenIndex;

  @override
  bool operator ==(Object other) =>
      other is TokenRef &&
      playerIndex == other.playerIndex &&
      tokenIndex == other.tokenIndex;

  @override
  int get hashCode => Object.hash(playerIndex, tokenIndex);

  @override
  String toString() => 'TokenRef(p$playerIndex:$tokenIndex)';
}

/// An intended move: the active player moves one of their tokens.
/// A [Move] carries no dice value — the roll lives in the [GameState]
/// that produced the legal-move list (SDD §6.5).
class Move {
  const Move({required this.playerIndex, required this.tokenIndex});

  final int playerIndex;
  final int tokenIndex;

  TokenRef get tokenRef => TokenRef(playerIndex, tokenIndex);

  @override
  bool operator ==(Object other) =>
      other is Move &&
      playerIndex == other.playerIndex &&
      tokenIndex == other.tokenIndex;

  @override
  int get hashCode => Object.hash(playerIndex, tokenIndex);

  @override
  String toString() => 'Move(p$playerIndex:$tokenIndex)';
}

/// The outcome of applying one [Move] atomically (SDD §6.5, Algorithm 1).
/// The UI animates exactly what this reports — it never re-derives it.
class MoveResult {
  const MoveResult({
    required this.move,
    required this.fromSteps,
    required this.toSteps,
    this.captured = const [],
    this.enteredHomePath = false,
    this.reachedHome = false,
    this.extraTurn = false,
    this.winnerIndex,
  });

  final Move move;

  /// The moved token's steps before / after the move.
  final int fromSteps;
  final int toSteps;

  /// Opponent tokens sent back to their yard by this move (BR-08).
  final List<TokenRef> captured;

  /// The token entered its home path on this move (BR-10).
  final bool enteredHomePath;

  /// The token reached home on this move (BR-10).
  final bool reachedHome;

  /// The same player rolls again (BR-06).
  final bool extraTurn;

  /// Index of the match winner, if this move ended the match (BR-11).
  final int? winnerIndex;

  bool get isWinningMove => winnerIndex != null;

  @override
  String toString() =>
      'MoveResult($move $fromSteps->$toSteps captured=$captured '
      'extraTurn=$extraTurn winner=$winnerIndex)';
}
