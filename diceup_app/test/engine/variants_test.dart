import 'package:diceup/domain/engine/board.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/engine/move.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/ruleset_config.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

/// A dice roller that always returns the same (possibly invalid) value,
/// so the engine's dice validation can be exercised directly.
class _ConstantDiceRoller implements DiceRoller {
  _ConstantDiceRoller(this.value);
  final int value;
  @override
  int roll() => value;
}

void main() {
  group('dice validation (FR-15, BR-02)', () {
    test('a roller returning 7 is rejected and the state is unchanged', () {
      final game = LudoGame.newMatch(
        seats: const [
          SeatConfig(name: 'Red', colour: PlayerColour.red),
          SeatConfig(name: 'Green', colour: PlayerColour.green),
        ],
        diceRoller: _ConstantDiceRoller(7),
      );
      final before = game.snapshot();
      expect(
        () => game.rollDice(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'DiceRoller returned an invalid value: 7.',
          ),
        ),
      );
      expect(game.snapshot(), before);
    });

    test('a roller returning 0 is rejected the same way', () {
      final game = LudoGame.newMatch(
        seats: const [
          SeatConfig(name: 'Red', colour: PlayerColour.red),
          SeatConfig(name: 'Green', colour: PlayerColour.green),
        ],
        diceRoller: _ConstantDiceRoller(0),
      );
      expect(() => game.rollDice(), throwsStateError);
      expect(game.state.phase, TurnPhase.awaitingRoll);
      expect(game.state.lastRoll, 0);
    });
  });

  group('FixedDiceRoller', () {
    test('an empty sequence is rejected at construction', () {
      expect(() => FixedDiceRoller(const []), throwsArgumentError);
    });

    test('a non-cycling roller throws once exhausted', () {
      final roller = FixedDiceRoller(const [3]);
      expect(roller.roll(), 3);
      expect(() => roller.roll(), throwsStateError);
    });

    test('a cycling roller repeats from the start', () {
      final roller = FixedDiceRoller(const [2, 5], cycle: true);
      expect(
        [roller.roll(), roller.roll(), roller.roll(), roller.roll()],
        [2, 5, 2, 5],
      );
    });
  });

  group('nextTurn (FR-19)', () {
    test('passes the turn clockwise between turns', () {
      final game = freshGame(const [3]);
      game.nextTurn();
      expect(game.currentPlayerIndex, 1);
      expect(game.state.phase, TurnPhase.awaitingRoll);
      expect(game.state.lastRoll, 0);
      // And it wraps: player 2's turn passes back to player 1.
      game.nextTurn();
      expect(game.currentPlayerIndex, 0);
    });

    test('resets the consecutive-sixes count', () {
      final game = freshGame(const [6, 6, 2]);
      game.rollDice(); // 6
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(game.state.consecutiveSixes, 1);
      expect(game.currentPlayerIndex, 0); // extra roll, same player
      game.nextTurn();
      expect(game.currentPlayerIndex, 1);
      expect(game.state.consecutiveSixes, 0);
    });

    test('play continues normally after nextTurn', () {
      final game = freshGame(const [6, 3]);
      game.nextTurn(); // player 2 to move
      expect(game.rollDice(), 6);
      expect(game.state.phase, TurnPhase.awaitingMove);
      expect(game.legalMoves().length, 4);
    });

    test('passing while a roll is outstanding is rejected', () {
      final game = freshGame(const [6]);
      game.rollDice(); // 6: a move is pending
      expect(game.state.phase, TurnPhase.awaitingMove);
      expect(
        () => game.nextTurn(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Cannot pass the turn while a roll or move is pending.',
          ),
        ),
      );
      expect(game.currentPlayerIndex, 0);
    });

    test('passing after the match is finished is rejected', () {
      final game = gameWith(
        tokenSteps: const [
          [56, 56, 56, 54],
          [0, 0, 0, 0],
        ],
        lastRoll: 2,
        phase: TurnPhase.awaitingMove,
      );
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 3));
      expect(game.isFinished, isTrue);
      expect(
        () => game.nextTurn(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Cannot pass the turn: the match is finished.',
          ),
        ),
      );
    });
  });

  group('non-exact finish variant (BR-10)', () {
    test('an overshooting roll still lands the token home', () {
      const variant = RulesetConfig(exactFinish: false);
      final game = gameWith(
        tokenSteps: const [
          [54, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        lastRoll: 6,
        phase: TurnPhase.awaitingMove,
        ruleset: variant,
      );
      expect(
        game.legalMoves(),
        contains(const Move(playerIndex: 0, tokenIndex: 0)),
      );
      final result = game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(result.toSteps, Board.stepsToHome);
      expect(result.reachedHome, isTrue);
      expect(result.enteredHomePath, isFalse); // it was already past 51
      expect(game.players[0].tokens[0].isHome, isTrue);
    });

    test('an overshoot from the home path lands home too', () {
      const variant = RulesetConfig(exactFinish: false);
      final game = gameWith(
        tokenSteps: const [
          [55, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        lastRoll: 6,
        phase: TurnPhase.awaitingMove,
        ruleset: variant,
      );
      final result = game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(result.toSteps, Board.stepsToHome);
      expect(result.reachedHome, isTrue);
    });
  });

  group('extra-turn switches (BR-06)', () {
    test('a six does not grant an extra roll when extraTurnOnSix is off', () {
      final game = freshGame(const [
        6,
        3,
      ], ruleset: const RulesetConfig(extraTurnOnSix: false));
      game.rollDice(); // 6
      final result = game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(result.extraTurn, isFalse);
      expect(game.currentPlayerIndex, 1); // turn passes
      expect(game.state.phase, TurnPhase.awaitingRoll);
    });

    test('a capture does not grant an extra roll when extraTurnOnCapture '
        'is off', () {
      // Same capture position as rules_test: red 12 + 3 lands on
      // green's token on track 14.
      final game = gameWith(
        tokenSteps: const [
          [12, 0, 0, 0],
          [2, 0, 0, 0],
        ],
        lastRoll: 3,
        phase: TurnPhase.awaitingMove,
        ruleset: const RulesetConfig(extraTurnOnCapture: false),
      );
      final result = game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(result.captured, [const TokenRef(1, 0)]);
      expect(result.extraTurn, isFalse);
      expect(game.currentPlayerIndex, 1);
    });

    test('reaching home does not grant an extra roll when extraTurnOnHome '
        'is off', () {
      final game = gameWith(
        tokenSteps: const [
          [56, 56, 0, 54],
          [0, 0, 0, 0],
        ],
        lastRoll: 2,
        phase: TurnPhase.awaitingMove,
        ruleset: const RulesetConfig(extraTurnOnHome: false),
      );
      final result = game.applyMove(const Move(playerIndex: 0, tokenIndex: 3));
      expect(result.reachedHome, isTrue);
      expect(game.isFinished, isFalse);
      expect(result.extraTurn, isFalse);
      expect(game.currentPlayerIndex, 1);
    });
  });

  group('release variants (BR-04)', () {
    test('release on 1 and on 6 together offer the yard on either roll', () {
      const variant = RulesetConfig(releaseOnOne: true);
      final onOne = freshGame(const [1], ruleset: variant);
      onOne.rollDice();
      expect(onOne.legalMoves().length, 4);
      final onSix = freshGame(const [6], ruleset: variant);
      onSix.rollDice();
      expect(onSix.legalMoves().length, 4);
    });

    test('with release on 1 only, a 6 offers no move but keeps the roll', () {
      const variant = RulesetConfig(releaseOnSix: false, releaseOnOne: true);
      final game = freshGame(const [6, 2], ruleset: variant);
      game.rollDice(); // 6: no yard token may leave
      expect(game.legalMoves(), isEmpty);
      expect(game.state.lastRollHadNoLegalMove, isTrue);
      expect(game.currentPlayerIndex, 0); // six still grants its roll
      expect(game.state.phase, TurnPhase.awaitingRoll);
      game.rollDice(); // 2: still no release roll
      expect(game.state.lastRollHadNoLegalMove, isTrue);
      expect(game.currentPlayerIndex, 1);
    });
  });

  group('consecutive-sixes limit variants (BR-07)', () {
    test('with a limit of 1, even the first six is not played', () {
      // The six that reaches the limit is shown but not played
      // (BR-07): with a limit of 1, that is already the first six,
      // so no move is ever pending off a six and the turn passes.
      const variant = RulesetConfig(maxConsecutiveSixes: 1);
      final game = freshGame(const [6, 2], ruleset: variant);
      final first = game.rollDice();
      expect(first, 6);
      expect(game.state.lastRollWasThirdSix, isTrue);
      expect(game.state.phase, TurnPhase.awaitingRoll);
      expect(game.legalMoves(), isEmpty);
      expect(game.currentPlayerIndex, 1);
      expect(game.state.consecutiveSixes, 0);
      // The next player rolls normally.
      expect(game.rollDice(), 2);
    });

    test('with a limit of 2, the second six is not played', () {
      const variant = RulesetConfig(maxConsecutiveSixes: 2);
      final game = freshGame(const [6, 6, 6, 2], ruleset: variant);
      game.rollDice();
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      final second = game.rollDice();
      expect(second, 6);
      expect(game.state.lastRollWasThirdSix, isTrue);
      expect(game.currentPlayerIndex, 1);
    });

    test('with the limit off, a non-six resets the count', () {
      const variant = RulesetConfig(maxConsecutiveSixes: 0);
      final game = freshGame(const [6, 6, 3], ruleset: variant);
      game.rollDice();
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(game.state.consecutiveSixes, 1);
      game.rollDice();
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(game.state.consecutiveSixes, 2);
      game.rollDice(); // 3
      expect(game.state.consecutiveSixes, 0);
      expect(game.state.lastRollWasThirdSix, isFalse);
    });
  });
}
