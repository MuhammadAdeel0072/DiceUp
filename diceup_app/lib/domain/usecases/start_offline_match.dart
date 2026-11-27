import '../engine/dice_roller.dart';
import '../engine/ludo_game.dart';
import '../engine/player.dart';
import '../engine/ruleset_config.dart';
import 'match_setup.dart';

/// Starts a fresh offline match (M3.1, SDD §3.2).
///
/// Thin orchestration over the engine: resolves the setup into seat
/// configs and constructs the match via [LudoGame.newMatch]. All
/// validation lives in the engine, so an invalid setup surfaces the
/// engine's exact error type — [InvalidMatchConfig] (wrong player
/// count, duplicate colours, no human seat) or
/// [InvalidRulesetConfig] — and no match is created. Nothing is
/// silently defaulted: a missing name reads as "Player N" and a
/// missing colour as the seat-order default ([MatchSetup.nameFor] /
/// [MatchSetup.colourFor]), exactly as the setup screen resolves
/// them, and anything else invalid throws.
///
/// No snapshot is saved at match start: the plan requires snapshots
/// after completed moves (and settled rolls), not at start (M1.6
/// deliberately saves none), so a match abandoned before its first
/// move leaves nothing to resume (D-11/D-12).
///
/// The [DiceRoller] is constructor-injected: production passes none
/// (the engine's random roller) and tests pass a [FixedDiceRoller].
/// The returned [LudoGame] is the live match aggregate; the caller
/// (M3.2 controller) owns it and drives rolls/moves through
/// [RollDice] and [ApplyMove].
class StartOfflineMatch {
  StartOfflineMatch({DiceRoller? diceRoller}) : _roller = diceRoller;

  final DiceRoller? _roller;

  LudoGame call(MatchSetup setup) {
    return LudoGame.newMatch(
      seats: setup.seats,
      ruleset: setup.ruleset,
      diceRoller: _roller,
    );
  }
}
