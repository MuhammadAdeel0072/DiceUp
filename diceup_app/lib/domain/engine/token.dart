import 'board.dart';
import 'player_colour.dart';

/// One playing piece. Immutable: every transition produces a new
/// [Token] via [copyWith] (SDD §6.1 — immutable snapshots).
///
/// [stepsTaken] is the token's progress along its own 56-step path:
/// 0 = in the yard, 1 = on its start cell, 51 = last outer-track cell,
/// 52..55 = home path, 56 = home.
class Token {
  const Token({
    required this.playerIndex,
    required this.index,
    required this.colour,
    this.stepsTaken = 0,
  });

  /// Index of the owning player in the match (0..3).
  final int playerIndex;

  /// Index of this token among its owner's four tokens (0..3).
  final int index;

  final PlayerColour colour;

  final int stepsTaken;

  bool get isInYard => stepsTaken == 0;
  bool get isHome => stepsTaken == Board.stepsToHome;
  bool get isInHomePath =>
      stepsTaken > Board.lastTrackStep && stepsTaken < Board.stepsToHome;
  bool get isOnTrack =>
      stepsTaken >= 1 && stepsTaken <= Board.lastTrackStep;

  /// Logical board cell for this token.
  Cell get cell => const Board().cellAt(colour, stepsTaken);

  /// Whether this token may move by [roll] under the given rules
  /// (BR-04 release, BR-10 exact finish). The caller (the engine)
  /// additionally checks turn ownership and phase.
  bool canMove(int roll, {required Set<int> releaseRolls, required bool exactFinish}) {
    if (isInYard) return releaseRolls.contains(roll);
    if (exactFinish) return stepsTaken + roll <= Board.stepsToHome;
    return !isHome; // Non-exact variant: any roll moves it home.
  }

  Token copyWith({int? stepsTaken}) => Token(
        playerIndex: playerIndex,
        index: index,
        colour: colour,
        stepsTaken: stepsTaken ?? this.stepsTaken,
      );

  /// A token sent back to its yard (BR-08 capture).
  Token get sentToYard => copyWith(stepsTaken: 0);

  Map<String, Object> toJson() => {'stepsTaken': stepsTaken};

  factory Token.fromJson({
    required int playerIndex,
    required int index,
    required PlayerColour colour,
    required Map<String, Object?> json,
  }) {
    return Token(
      playerIndex: playerIndex,
      index: index,
      colour: colour,
      stepsTaken: json['stepsTaken'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Token &&
      playerIndex == other.playerIndex &&
      index == other.index &&
      colour == other.colour &&
      stepsTaken == other.stepsTaken;

  @override
  int get hashCode => Object.hash(playerIndex, index, colour, stepsTaken);

  @override
  String toString() =>
      'Token(p$playerIndex:$index ${colour.label} steps=$stepsTaken)';
}
