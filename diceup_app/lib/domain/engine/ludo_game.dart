import 'board.dart';
import 'dice_roller.dart';
import 'game_state.dart';
import 'move.dart';
import 'player.dart';
import 'ruleset_config.dart';
import 'token.dart';

/// The offline Ludo match aggregate (SDD §6, SRS FR-15..FR-32).
///
/// Pure Dart: no Flutter, storage or network dependency (SRS NFR-26).
/// Every transition is atomic — it either applies fully to a new
/// immutable [GameState] or throws before changing anything (FR-21).
///
/// Turn flow (SDD §6.4):
/// `awaitingRoll --rollDice()--> awaitingMove --applyMove()-->`
/// `awaitingRoll` (same player on an extra turn, otherwise next player).
/// A roll that offers no legal move resolves inside [rollDice]: the
/// turn passes, except a six still grants its extra roll (BR-13).
class LudoGame {
  LudoGame._(
    this._state, {
    required this.board,
    required this.ruleset,
    required this._diceRoller,
  });

  /// Starts a new match (SDD §6.3).
  ///
  /// Validates: 2–4 seats, distinct colours, at least one human seat
  /// (BR-01, FR-14) and a valid ruleset. Throws [InvalidMatchConfig]
  /// or [InvalidRulesetConfig]; no match is created on failure.
  factory LudoGame.newMatch({
    required List<SeatConfig> seats,
    RulesetConfig ruleset = const RulesetConfig(),
    DiceRoller? diceRoller,
    Board board = const Board(),
  }) {
    ruleset.validate();
    if (seats.length < 2 || seats.length > 4) {
      throw const InvalidMatchConfig(
        'A match needs 2–4 players (FR-13).',
      );
    }
    final colours = seats.map((s) => s.colour).toSet();
    if (colours.length != seats.length) {
      throw const InvalidMatchConfig(
        'Each player needs a distinct colour (BR-01).',
      );
    }
    if (seats.every((s) => s.type != PlayerType.human)) {
      throw const InvalidMatchConfig(
        'A match needs at least one human seat (FR-14).',
      );
    }
    final players = List<Player>.generate(
      seats.length,
      (i) => Player(
        index: i,
        name: seats[i].name,
        colour: seats[i].colour,
        type: seats[i].type,
      ),
    );
    final state = GameState.initial(
      players: players,
      rulesetVersion: ruleset.version,
    );
    return LudoGame._(
      state,
      board: board,
      ruleset: ruleset,
      diceRoller: diceRoller ?? RandomDiceRoller(),
    );
  }

  /// Builds a game around an existing [state] — used by snapshot
  /// restore and by tests / rule-vector harnesses that need an exact
  /// board position (SDD §6.9). The state's ruleset version must
  /// match [ruleset].
  factory LudoGame.fromState(
    GameState state, {
    RulesetConfig ruleset = const RulesetConfig(),
    DiceRoller? diceRoller,
    Board board = const Board(),
  }) {
    ruleset.validate();
    if (state.rulesetVersion != ruleset.version) {
      throw ArgumentError(
        'Snapshot ruleset ${state.rulesetVersion} does not match '
        'ruleset ${ruleset.version}.',
      );
    }
    return LudoGame._(
      state,
      board: board,
      ruleset: ruleset,
      diceRoller: diceRoller ?? RandomDiceRoller(),
    );
  }

  final Board board;
  final RulesetConfig ruleset;
  final DiceRoller _diceRoller;

  GameState _state;

  /// The current immutable snapshot. Observers (UI, AI, resume)
  /// must treat it as read-only.
  GameState get state => _state;

  List<Player> get players => _state.players;
  Player get currentPlayer => _state.currentPlayer;
  int get currentPlayerIndex => _state.currentPlayerIndex;
  bool get isFinished => _state.isFinished;
  int? get winnerIndex => _state.winnerIndex;
  Player? get winner =>
      winnerIndex == null ? null : _state.players[winnerIndex!];

  /// Rolls the dice for the active player (FR-15, BR-02, BR-03).
  ///
  /// Only the active player may roll, and only while a roll is
  /// pending; otherwise throws [StateError] with state unchanged.
  /// Returns the value (1..6). After the call, inspect [state]:
  /// * `phase == awaitingMove` — choose one of [legalMoves];
  /// * `phase == awaitingRoll` and the player changed — the roll
  ///   offered no legal move (BR-13) or was a third six (BR-07);
  /// * `phase == awaitingRoll` and the player is unchanged — a six
  ///   with no legal move granted an extra roll (BR-13).
  int rollDice() {
    if (_state.isFinished) {
      throw StateError('Cannot roll: the match is finished.');
    }
    if (_state.phase != TurnPhase.awaitingRoll) {
      throw StateError('Cannot roll: a roll is already outstanding.');
    }
    final value = _diceRoller.roll();
    if (value < 1 || value > 6) {
      throw StateError('DiceRoller returned an invalid value: $value.');
    }

    final consecutive =
        value == 6 ? _state.consecutiveSixes + 1 : 0;
    final isThirdSix = value == 6 &&
        ruleset.maxConsecutiveSixes > 0 &&
        consecutive >= ruleset.maxConsecutiveSixes;

    if (isThirdSix) {
      // BR-07: the third consecutive six is shown but not played.
      _state = _advancedTurn(
        lastRoll: value,
        lastRollWasThirdSix: true,
      );
      return value;
    }

    var next = _state.copyWith(
      phase: TurnPhase.awaitingMove,
      lastRoll: value,
      consecutiveSixes: consecutive,
      lastRollWasThirdSix: false,
      lastRollHadNoLegalMove: false,
    );
    _state = next;

    if (legalMoves().isEmpty) {
      // BR-13: no legal move — the turn passes, except a six still
      // grants its extra roll.
      if (value == 6) {
        _state = next.copyWith(
          phase: TurnPhase.awaitingRoll,
          lastRollHadNoLegalMove: true,
        );
      } else {
        _state = _advancedTurn(
          from: next,
          lastRoll: value,
          lastRollHadNoLegalMove: true,
        );
      }
    }
    return value;
  }

  /// Legal moves for the outstanding roll (FR-16, SDD §6.5).
  /// Empty unless the phase is [TurnPhase.awaitingMove].
  List<Move> legalMoves() {
    if (_state.phase != TurnPhase.awaitingMove) return const [];
    return legalMovesFor(_state, _state.lastRoll, ruleset, board);
  }

  /// Pure legal-move computation, shared by the engine and the
  /// AI (FR-35) and usable standalone in rule-vector tests.
  static List<Move> legalMovesFor(
    GameState state,
    int roll,
    RulesetConfig ruleset,
    Board board,
  ) {
    final player = state.currentPlayer;
    final moves = <Move>[];
    for (final token in player.tokens) {
      final canMove = token.canMove(
        roll,
        releaseRolls: ruleset.releaseRolls,
        exactFinish: ruleset.exactFinish,
      );
      if (canMove) {
        moves.add(Move(playerIndex: player.index, tokenIndex: token.index));
      }
    }
    return moves;
  }

  /// Applies one move atomically (FR-17, SDD §6.5, Algorithm 1).
  ///
  /// Throws [StateError] if no move is pending and [ArgumentError]
  /// if [move] is not in [legalMoves] — in both cases the state is
  /// unchanged (FR-21). On success returns a [MoveResult]
  /// describing exactly what happened (captures, extra turn, winner).
  MoveResult applyMove(Move move) {
    if (_state.isFinished) {
      throw StateError('Cannot move: the match is finished.');
    }
    if (_state.phase != TurnPhase.awaitingMove) {
      throw StateError('Cannot move: roll the dice first.');
    }
    if (move.playerIndex != _state.currentPlayerIndex) {
      throw ArgumentError('Cannot move: it is not that player\'s turn.');
    }
    final legal = legalMoves();
    if (!legal.contains(move)) {
      throw ArgumentError('Illegal move: $move is not a legal move.');
    }

    final player = _state.currentPlayer;
    final token = player.tokens[move.tokenIndex];
    final fromSteps = token.stepsTaken;
    // A release spends the roll entering the board: the token lands
    // on its start cell (step 1), it does not advance by the roll
    // (BR-04). Any other move advances by exactly the roll (BR-05).
    var toSteps =
        token.isInYard ? 1 : fromSteps + _state.lastRoll;
    if (!ruleset.exactFinish && toSteps > Board.stepsToHome) {
      toSteps = Board.stepsToHome; // Non-exact variant: overshoot lands home.
    }

    // BR-08: capture opponent tokens on the landing cell, unless it
    // is a safe cell (BR-09). Passing over tokens never captures.
    final captured = <TokenRef>[];
    final landing = board.cellAt(token.colour, toSteps);
    final isCaptureCell =
        landing.kind == CellKind.track && !board.isSafe(landing);
    // Mutable working copies; new immutable Players are built below.
    final tokenLists =
        _state.players.map((p) => List<Token>.of(p.tokens)).toList();
    if (isCaptureCell) {
      for (var pi = 0; pi < tokenLists.length; pi++) {
        if (pi == player.index) continue;
        for (var i = 0; i < tokenLists[pi].length; i++) {
          final other = tokenLists[pi][i];
          if (other.isOnTrack && other.cell == landing) {
            tokenLists[pi][i] = other.sentToYard;
            captured.add(TokenRef(pi, i));
          }
        }
      }
    }

    tokenLists[player.index][move.tokenIndex] =
        token.copyWith(stepsTaken: toSteps);
    final updatedPlayers = List<Player>.generate(
      _state.players.length,
      (i) => _state.players[i].copyWith(tokens: tokenLists[i]),
    );

    final enteredHomePath =
        fromSteps <= Board.lastTrackStep &&
            toSteps > Board.lastTrackStep &&
            toSteps < Board.stepsToHome;
    final reachedHome = toSteps == Board.stepsToHome;
    final won = updatedPlayers[player.index].hasWon;

    final extraTurn = !won &&
        ((ruleset.extraTurnOnSix && _state.lastRoll == 6) ||
            (ruleset.extraTurnOnCapture && captured.isNotEmpty) ||
            (ruleset.extraTurnOnHome && reachedHome));

    final result = MoveResult(
      move: move,
      fromSteps: fromSteps,
      toSteps: toSteps,
      captured: captured,
      enteredHomePath: enteredHomePath,
      reachedHome: reachedHome,
      extraTurn: extraTurn,
      winnerIndex: won ? player.index : null,
    );

    if (won) {
      // BR-11: first player with all four tokens home wins;
      // the match ends (default; see report note on ranking play).
      _state = _state.copyWith(
        players: updatedPlayers,
        phase: TurnPhase.finished,
        winnerIndex: player.index,
        moveCount: _state.moveCount + 1,
        lastRoll: 0,
      );
      return result;
    }
    if (extraTurn) {
      _state = _state.copyWith(
        players: updatedPlayers,
        phase: TurnPhase.awaitingRoll,
        lastRoll: 0,
        moveCount: _state.moveCount + 1,
      );
      return result;
    }
    _state = _advancedTurn(
      from: _state.copyWith(
        players: updatedPlayers,
        moveCount: _state.moveCount + 1,
      ),
      lastRoll: 0,
    );
    return result;
  }

  /// Passes the turn to the next player clockwise (FR-19).
  /// Only valid between turns (phase [TurnPhase.awaitingRoll]).
  void nextTurn() {
    if (_state.isFinished) {
      throw StateError('Cannot pass the turn: the match is finished.');
    }
    if (_state.phase != TurnPhase.awaitingRoll) {
      throw StateError(
        'Cannot pass the turn while a roll or move is pending.',
      );
    }
    _state = _advancedTurn(lastRoll: 0);
  }

  /// Serialises the current snapshot to JSON (SRS FR-29 resume).
  Map<String, Object?> snapshot() => _state.toJson();

  /// Restores a game from a [snapshot] produced by [snapshot].
  /// The snapshot's ruleset version must match [ruleset].
  static LudoGame restore(
    Map<String, Object?> snapshot, {
    RulesetConfig ruleset = const RulesetConfig(),
    DiceRoller? diceRoller,
    Board board = const Board(),
  }) {
    return LudoGame.fromState(
      GameState.fromJson(snapshot),
      ruleset: ruleset,
      diceRoller: diceRoller,
      board: board,
    );
  }

  /// Advances to the next player clockwise, clearing turn state.
  GameState _advancedTurn({
    GameState? from,
    required int lastRoll,
    bool lastRollWasThirdSix = false,
    bool lastRollHadNoLegalMove = false,
  }) {
    final base = from ?? _state;
    final nextPlayer =
        (base.currentPlayerIndex + 1) % base.players.length;
    return base.copyWith(
      currentPlayerIndex: nextPlayer,
      phase: TurnPhase.awaitingRoll,
      lastRoll: lastRoll,
      consecutiveSixes: 0,
      lastRollWasThirdSix: lastRollWasThirdSix,
      lastRollHadNoLegalMove: lastRollHadNoLegalMove,
    );
  }
}
