import 'dart:math';

import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/ruleset_config.dart';
import 'package:diceup/domain/engine/token.dart';

/// Builds a [GameState] with tokens at exact step counts.
///
/// [tokenSteps] is one list of 4 step counts per player (0 = yard,
/// 56 = home). Players are red, green, yellow, blue in seat order.
/// [current] is the active player; [lastRoll] with [phase] lets a
/// test place the game mid-turn (e.g. awaiting a move after a roll).
GameState stateWith({
  required List<List<int>> tokenSteps,
  int current = 0,
  int lastRoll = 0,
  TurnPhase phase = TurnPhase.awaitingRoll,
  String rulesetVersion = '1.0.0',
}) {
  final colours = PlayerColour.values;
  final players = List<Player>.generate(tokenSteps.length, (pi) {
    final steps = tokenSteps[pi];
    assert(steps.length == 4, 'Each player needs exactly 4 tokens.');
    return Player(
      index: pi,
      name: 'Player ${pi + 1}',
      colour: colours[pi],
      type: PlayerType.human,
      tokens: List<Token>.generate(
        4,
        (ti) => Token(
          playerIndex: pi,
          index: ti,
          colour: colours[pi],
          stepsTaken: steps[ti],
        ),
      ),
    );
  });
  return GameState(
    players: players,
    currentPlayerIndex: current,
    rulesetVersion: rulesetVersion,
    phase: phase,
    lastRoll: lastRoll,
  );
}

/// A [LudoGame] around an exact board position (see [stateWith]).
LudoGame gameWith({
  required List<List<int>> tokenSteps,
  int current = 0,
  int lastRoll = 0,
  TurnPhase phase = TurnPhase.awaitingRoll,
  RulesetConfig ruleset = const RulesetConfig(),
  DiceRoller? diceRoller,
}) {
  return LudoGame.fromState(
    stateWith(
      tokenSteps: tokenSteps,
      current: current,
      lastRoll: lastRoll,
      phase: phase,
    ),
    ruleset: ruleset,
    diceRoller: diceRoller,
  );
}

/// A fresh 2-player match (red human, green human) with fixed dice.
LudoGame freshGame(List<int> dice, {RulesetConfig? ruleset}) {
  return LudoGame.newMatch(
    seats: const [
      SeatConfig(name: 'Red', colour: PlayerColour.red),
      SeatConfig(name: 'Green', colour: PlayerColour.green),
    ],
    ruleset: ruleset ?? const RulesetConfig(),
    diceRoller: FixedDiceRoller(dice),
  );
}

/// An [AiPlayer] built from the player at [playerIndex] in [state].
AiPlayer aiFromState(
  GameState state,
  int playerIndex,
  AiDifficulty difficulty, {
  int seed = 42,
}) {
  final player = state.players[playerIndex];
  return AiPlayer(
    index: player.index,
    name: player.name,
    colour: player.colour,
    difficulty: difficulty,
    random: _SeededRandom(seed),
    tokens: player.tokens,
  );
}

/// Deterministic [Random] wrapper used only by tests.
class _SeededRandom implements Random {
  _SeededRandom(int seed) : _inner = Random(seed);
  final Random _inner;
  @override
  int nextInt(int max) => _inner.nextInt(max);
  @override
  double nextDouble() => _inner.nextDouble();
  @override
  bool nextBool() => _inner.nextBool();
}
