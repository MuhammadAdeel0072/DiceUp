import '../engine/game_state.dart';
import '../engine/ludo_game.dart';

/// The outcome of a settled dice roll: the engine's value and the
/// post-roll state. The caller (M3.2 controller) persists the
/// returned state — a roll changes state (`lastRoll` / phase), so the
/// settled roll is snapshotted, exactly as the game screen does
/// today — and reads [GameState.lastRollWasThirdSix] /
/// [GameState.lastRollHadNoLegalMove] for the status line.
class DiceRollResult {
  const DiceRollResult({required this.value, required this.state});

  /// The engine's value, 1..6 (BR-02).
  final int value;

  /// The match state immediately after the roll.
  final GameState state;
}

/// Rolls the dice for the active player (M3.1, SDD §3.2, FR-15).
///
/// Thin orchestration over [LudoGame.rollDice]: the engine decides
/// the value the moment this is called; any animation only displays
/// it afterwards. Guards, in order:
/// * [isRolling] — the caller's in-flight roll animation (the game
///   screen's `_rolling` flag). The engine cannot see the animation:
///   a roll that offered no legal move already returned the phase to
///   `awaitingRoll`, so without this flag a second tap mid-animation
///   would roll again. Throws [StateError]; the state is unchanged.
/// * the engine's own guards — a finished match, or a phase other
///   than `awaitingRoll` (a move is pending), throws [StateError]
///   with the state unchanged.
///
/// This rolls for whoever the engine says is current — human or AI.
/// Human-vs-AI enablement (the Roll button, the AI scheduler) stays
/// with the caller; there is no "wrong player" here because the
/// engine always rolls for the current seat.
///
/// Synchronous and persistence-free: the caller persists the
/// returned state (M3.2 wires it).
class RollDice {
  DiceRollResult call(LudoGame game, {bool isRolling = false}) {
    if (isRolling) {
      throw StateError('A dice roll is already in progress.');
    }
    final value = game.rollDice();
    return DiceRollResult(value: value, state: game.state);
  }
}
