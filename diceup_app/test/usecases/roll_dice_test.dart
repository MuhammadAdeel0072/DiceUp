import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/usecases/roll_dice.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/test_helpers.dart';

void main() {
  group('RollDice', () {
    test('roll returns the engine value and the post-roll state', () {
      final game = freshGame(const [6]);
      final roll = RollDice();

      final result = roll(game);

      expect(result.value, 6);
      expect(result.state.lastRoll, 6);
      expect(result.state.phase, TurnPhase.awaitingMove);
      expect(game.legalMoves(), isNotEmpty);
    });

    test('a roll with no legal move passes the turn (BR-13)', () {
      final game = freshGame(const [2]);
      final roll = RollDice();

      final result = roll(game);

      expect(result.value, 2);
      expect(result.state.currentPlayerIndex, 1);
      expect(result.state.phase, TurnPhase.awaitingRoll);
      expect(result.state.lastRollHadNoLegalMove, isTrue);
    });

    test('an in-flight roll animation rejects a second roll', () {
      final game = freshGame(const [6]);
      final roll = RollDice();
      final before = game.state;

      expect(() => roll(game, isRolling: true), throwsStateError);
      expect(game.state, same(before));
      expect(game.state.lastRoll, 0);
    });

    test('a roll while a move is pending is rejected', () {
      final game = freshGame(const [6]);
      final roll = RollDice();
      roll(game);

      expect(() => roll(game), throwsStateError);
      expect(game.state.phase, TurnPhase.awaitingMove);
    });

    test('a roll on a finished match is rejected', () {
      final finished = LudoGame.fromState(
        stateWith(
          tokenSteps: const [
            [56, 56, 56, 56],
            [0, 0, 0, 0],
          ],
        ).copyWith(phase: TurnPhase.finished, winnerIndex: 0),
      );

      expect(() => RollDice()(finished), throwsStateError);
      expect(finished.isFinished, isTrue);
    });
  });
}
