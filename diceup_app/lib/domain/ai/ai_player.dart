import 'dart:math';

import '../engine/board.dart';
import '../engine/game_state.dart';
import '../engine/move.dart';
import '../engine/player.dart';
import '../engine/token.dart';

/// AI difficulty (SRS FR-36..FR-38, SDD §7.2).
enum AiDifficulty { easy, medium, hard }

/// An automated opponent (SRS FR-33..FR-41, SDD Ch. 7).
///
/// Rule-based only — no machine learning (SDD §7). An [AiPlayer] is a
/// [Player] subclass that receives exactly what a human sees — the
/// current [GameState] snapshot and the engine's legal-move list
/// (FR-35) — and returns one [Move] from that list. It never sees
/// future dice, cannot alter dice probabilities and cannot bypass any
/// engine rule (FR-39): the engine re-validates the returned move
/// before applying it.
///
/// Pacing (600–1,200 ms before rolling/moving, FR-40) is owned by the
/// UI controller, not by this class.
class AiPlayer extends Player {
  AiPlayer({
    required super.index,
    required super.name,
    required super.colour,
    this.difficulty = AiDifficulty.medium,
    Random? random,
    super.tokens,
  })  : _random = random ?? Random(),
        super(type: PlayerType.ai);

  final AiDifficulty difficulty;
  final Random _random;

  /// Serialises the AI seat, including its difficulty (M1.1): without
  /// this the difficulty would not survive a snapshot round-trip.
  @override
  Map<String, Object> toJson() => {
        ...super.toJson(),
        'difficulty': difficulty.name,
      };

  /// Preserves the AI identity across engine transitions: the base
  /// [Player.copyWith] would downgrade an [AiPlayer] to a plain
  /// [Player] and lose the difficulty after the first move (M1.1).
  @override
  AiPlayer copyWith({
    List<Token>? tokens,
    AiDifficulty? difficulty,
    Random? random,
  }) =>
      AiPlayer(
        index: index,
        name: name,
        colour: colour,
        difficulty: difficulty ?? this.difficulty,
        random: random ?? _random,
        tokens: tokens ?? this.tokens,
      );

  /// Chooses one move from [legalMoves] (never anything else).
  /// Throws [ArgumentError] if the list is empty — the engine, not
  /// the AI, decides that a turn with no legal move passes (BR-13).
  Move chooseMove(List<Move> legalMoves, GameState state, Board board) {
    if (legalMoves.isEmpty) {
      throw ArgumentError('AiPlayer has no legal move to choose from.');
    }
    switch (difficulty) {
      case AiDifficulty.easy:
        // FR-36: uniform random choice among legal moves.
        return legalMoves[_random.nextInt(legalMoves.length)];
      case AiDifficulty.medium:
        return _chooseMedium(legalMoves, state, board);
      case AiDifficulty.hard:
        return _chooseHard(legalMoves, state, board);
    }
  }

  // -- Medium: fixed priority cascade (FR-37, SDD §7.3) ---------------
  // finish > capture > release > move off danger > advance furthest.
  Move _chooseMedium(List<Move> legal, GameState state, Board board) {
    Move? firstWhere(bool Function(Move) test) {
      for (final move in legal) {
        if (test(move)) return move;
      }
      return null;
    }

    return firstWhere((m) => _newSteps(m, state) == Board.stepsToHome) ??
        firstWhere((m) => _capturedCount(m, state, board) > 0) ??
        firstWhere((m) => _tokenOf(m, state).isInYard) ??
        firstWhere((m) => _movesOffDanger(m, state, board)) ??
        _furthest(legal, state);
  }

  Move _furthest(List<Move> legal, GameState state) {
    var best = legal.first;
    var bestSteps = _newSteps(best, state);
    for (final move in legal.skip(1)) {
      final steps = _newSteps(move, state);
      if (steps > bestSteps) {
        best = move;
        bestSteps = steps;
      }
    }
    return best;
  }

  // -- Hard: weighted scoring, one linear pass (FR-38, SDD §7.3) -------
  Move _chooseHard(List<Move> legal, GameState state, Board board) {
    var best = legal.first;
    var bestScore = scoreMove(best, state, board);
    for (final move in legal.skip(1)) {
      final score = scoreMove(move, state, board);
      if (score > bestScore) {
        best = move;
        bestScore = score;
      }
    }
    return best;
  }

  /// Scores one legal move (SDD §7.3, Algorithm 2).
  ///
  /// finish +100 · capture +60 each · release +25 · land safe +15 ·
  /// progress +0.5/step · lands in danger −40 · leaves a teammate
  /// exposed −10 · plus a tiny random jitter (0..1) to break ties.
  /// A single pass over at most 4 moves: far inside the 500 ms
  /// budget (SRS NFR-04). No lookahead beyond one move.
  double scoreMove(Move move, GameState state, Board board) {
    final token = _tokenOf(move, state);
    final newSteps = _newSteps(move, state);
    var score = 0.0;

    if (newSteps == Board.stepsToHome) score += 100;
    score += 60 * _capturedCount(move, state, board);
    if (token.isInYard) score += 25;
    if (board.isSafe(board.cellAt(token.colour, newSteps))) score += 15;
    score += newSteps * 0.5;
    if (_landsInDanger(move, state, board)) score -= 40;
    if (_leavesTeammateExposed(move, state, board)) score -= 10;
    return score + _random.nextDouble();
  }

  // -- Shared helpers ---------------------------------------------------

  Token _tokenOf(Move move, GameState state) =>
      state.players[move.playerIndex].tokens[move.tokenIndex];

  int _newSteps(Move move, GameState state) {
    final token = _tokenOf(move, state);
    // A release lands on the start cell (step 1); see LudoGame.
    return token.isInYard ? 1 : token.stepsTaken + state.lastRoll;
  }

  /// Opponent tokens this move would capture (BR-08): landing on a
  /// non-safe track cell occupied by opponents.
  int _capturedCount(Move move, GameState state, Board board) {
    final token = _tokenOf(move, state);
    final landing = board.cellAt(token.colour, _newSteps(move, state));
    if (landing.kind != CellKind.track || board.isSafe(landing)) return 0;
    var count = 0;
    for (final player in state.players) {
      if (player.index == move.playerIndex) continue;
      for (final other in player.tokens) {
        if (other.isOnTrack && other.cell == landing) count++;
      }
    }
    return count;
  }

  /// Would the token land where an opponent could capture it next
  /// turn — a non-safe track cell with an opponent token 1..6 steps
  /// behind it (SDD §7.3)?
  bool _landsInDanger(Move move, GameState state, Board board) {
    final token = _tokenOf(move, state);
    final landing = board.cellAt(token.colour, _newSteps(move, state));
    if (landing.kind != CellKind.track || board.isSafe(landing)) {
      return false;
    }
    return _opponentWithinSix(landing.index, move.playerIndex, state);
  }

  /// Does the move leave a teammate alone and exposed? That is: the
  /// moving token currently shares a non-safe track cell with a
  /// teammate, and an opponent sits 1..6 steps behind that cell.
  bool _leavesTeammateExposed(Move move, GameState state, Board board) {
    final token = _tokenOf(move, state);
    if (!token.isOnTrack) return false;
    final cell = token.cell;
    if (board.isSafe(cell)) return false;
    final owner = state.players[move.playerIndex];
    final sharesCell = owner.tokens.any(
      (t) => t.index != token.index && t.isOnTrack && t.cell == cell,
    );
    if (!sharesCell) return false;
    return _opponentWithinSix(cell.index, move.playerIndex, state);
  }

  /// Does the move take a token that is currently in danger to
  /// safety (a safe cell, the home path or home)?
  bool _movesOffDanger(Move move, GameState state, Board board) {
    final token = _tokenOf(move, state);
    if (!token.isOnTrack || board.isSafe(token.cell)) return false;
    if (!_opponentWithinSix(token.cell.index, move.playerIndex, state)) {
      return false;
    }
    final landing = board.cellAt(token.colour, _newSteps(move, state));
    return board.isSafe(landing);
  }

  /// Is any opponent token on the track 1..6 steps behind [trackIndex]
  /// (i.e. able to land on it with one roll)?
  bool _opponentWithinSix(
    int trackIndex,
    int playerIndex,
    GameState state,
  ) {
    for (final player in state.players) {
      if (player.index == playerIndex) continue;
      for (final other in player.tokens) {
        if (!other.isOnTrack) continue;
        final distance =
            (trackIndex - other.cell.index + Board.trackSize) %
                Board.trackSize;
        if (distance >= 1 && distance <= 6) return true;
      }
    }
    return false;
  }
}
