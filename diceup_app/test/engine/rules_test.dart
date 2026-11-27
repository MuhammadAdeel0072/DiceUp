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

void main() {
  group('match setup (SDD §6.3, BR-01, FR-13/FR-14)', () {
    test('starts with 2–4 players, 4 tokens each in the yard', () {
      final game = LudoGame.newMatch(
        seats: const [
          SeatConfig(name: 'Red', colour: PlayerColour.red),
          SeatConfig(name: 'Green', colour: PlayerColour.green),
          SeatConfig(name: 'Blue', colour: PlayerColour.blue),
        ],
        diceRoller: FixedDiceRoller(const [1]),
      );
      expect(game.players.length, 3);
      for (final player in game.players) {
        expect(player.tokens.length, 4);
        expect(player.tokens.every((t) => t.isInYard), isTrue);
      }
      expect(game.currentPlayerIndex, 0);
      expect(game.state.phase, TurnPhase.awaitingRoll);
    });

    test('rejects fewer than 2 or more than 4 players', () {
      expect(
        () => LudoGame.newMatch(
          seats: const [SeatConfig(name: 'Solo', colour: PlayerColour.red)],
        ),
        throwsA(isA<InvalidMatchConfig>()),
      );
    });

    test('rejects duplicate colours', () {
      expect(
        () => LudoGame.newMatch(
          seats: const [
            SeatConfig(name: 'A', colour: PlayerColour.red),
            SeatConfig(name: 'B', colour: PlayerColour.red),
          ],
        ),
        throwsA(isA<InvalidMatchConfig>()),
      );
    });

    test('rejects a match with no human seat', () {
      expect(
        () => LudoGame.newMatch(
          seats: const [
            SeatConfig(
              name: 'AI 1',
              colour: PlayerColour.red,
              type: PlayerType.ai,
            ),
            SeatConfig(
              name: 'AI 2',
              colour: PlayerColour.green,
              type: PlayerType.ai,
            ),
          ],
        ),
        throwsA(isA<InvalidMatchConfig>()),
      );
    });
  });

  group('dice (FR-15, BR-02)', () {
    test('dice values are always 1..6', () {
      final roller = RandomDiceRoller.seeded(7);
      for (var i = 0; i < 600; i++) {
        final value = roller.roll();
        expect(value, inInclusiveRange(1, 6));
      }
    });

    test('a seeded roller replays the same sequence', () {
      final a = RandomDiceRoller.seeded(99);
      final b = RandomDiceRoller.seeded(99);
      for (var i = 0; i < 50; i++) {
        expect(a.roll(), b.roll());
      }
    });

    test('a second roll while one is outstanding is rejected', () {
      final game = freshGame(const [6, 4]);
      game.rollDice(); // 6: yard tokens can move, roll is outstanding.
      expect(() => game.rollDice(), throwsStateError);
      expect(game.state.lastRoll, 6);
    });

    test('a fixed roller rejects out-of-range values at construction', () {
      expect(() => FixedDiceRoller(const [0]), throwsArgumentError);
      expect(() => FixedDiceRoller(const [7]), throwsArgumentError);
    });
  });

  group('token release (FR-18, BR-04)', () {
    test('a token leaves the yard only on a 6', () {
      final game = freshGame(const [3]);
      game.rollDice();
      expect(game.legalMoves(), isEmpty);
      // No legal move and no six: the turn passes to player 2.
      expect(game.currentPlayerIndex, 1);
    });

    test('a 6 offers all four yard tokens', () {
      final game = freshGame(const [6]);
      game.rollDice();
      expect(game.legalMoves().length, 4);
      final result = game.applyMove(const Move(playerIndex: 0, tokenIndex: 2));
      expect(result.fromSteps, 0);
      expect(result.toSteps, 1);
      expect(
        game.players[0].tokens[2].cell,
        const Cell.track(0),
      ); // red start cell
    });

    test('release on 1 works only when the variant is enabled', () {
      const variant = RulesetConfig(releaseOnOne: true, version: '1.1.0');
      final game = freshGame(const [1], ruleset: variant);
      game.rollDice();
      expect(game.legalMoves().length, 4);
    });
  });

  group('valid moves and exact finish (FR-16, BR-10)', () {
    test('exact-finish overshoot is illegal for that token', () {
      // Red token 0 is 2 steps from home (54); roll 6. The 6 releases
      // the three yard tokens but cannot move token 0 (54 + 6 > 56).
      final game = gameWith(
        tokenSteps: const [
          [54, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        lastRoll: 6,
        phase: TurnPhase.awaitingMove,
      );
      final moves = game.legalMoves();
      expect(moves.any((m) => m.tokenIndex == 0), isFalse);
      expect(moves.length, 3);
    });

    test('an exact roll to 56 is legal and reaches home', () {
      final game = gameWith(
        tokenSteps: const [
          [54, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        lastRoll: 2,
        phase: TurnPhase.awaitingMove,
      );
      expect(
        game.legalMoves(),
        contains(const Move(playerIndex: 0, tokenIndex: 0)),
      );
      final result = game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(result.reachedHome, isTrue);
      expect(result.toSteps, 56);
    });
  });

  group('capture and safe cells (FR-22/FR-23, BR-08/BR-09)', () {
    test('landing on an opponent on a normal cell captures it', () {
      // Green token 0 at steps 2 sits on track 14 (not safe).
      // Red token 0 at steps 12 sits on track 11; roll 3 -> track 14.
      final game = gameWith(
        tokenSteps: const [
          [12, 0, 0, 0],
          [2, 0, 0, 0],
        ],
        lastRoll: 3,
        phase: TurnPhase.awaitingMove,
      );
      final result = game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(result.captured, [const TokenRef(1, 0)]);
      expect(game.players[1].tokens[0].isInYard, isTrue);
      expect(result.extraTurn, isTrue); // capture grants an extra roll
    });

    test('tokens on safe cells cannot be captured', () {
      // Green token 0 on its start cell (track 13, steps 1) — safe.
      // Red token 0 at steps 11 rolls 3 and lands on track 13.
      final game = gameWith(
        tokenSteps: const [
          [11, 0, 0, 0],
          [1, 0, 0, 0],
        ],
        lastRoll: 3,
        phase: TurnPhase.awaitingMove,
      );
      final result = game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(result.captured, isEmpty);
      expect(game.players[1].tokens[0].stepsTaken, 1);
    });

    test('all 8 safe cells are start cells + star cells', () {
      expect(Board.safeCells, {0, 8, 13, 21, 26, 34, 39, 47});
      const board = Board();
      expect(board.isSafeTrackCell(8), isTrue);
      expect(board.isSafeTrackCell(9), isFalse);
    });
  });

  group('home path (FR-24, BR-10)', () {
    test('a token completing the track enters its home path', () {
      final game = gameWith(
        tokenSteps: const [
          [50, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        lastRoll: 3,
        phase: TurnPhase.awaitingMove,
      );
      final result = game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(result.enteredHomePath, isTrue);
      expect(result.toSteps, 53);
      expect(game.players[0].tokens[0].cell, const Cell.homePath(1));
    });
  });

  group('winning (FR-25, BR-11)', () {
    test('all four tokens home wins and ends the match', () {
      final game = gameWith(
        tokenSteps: const [
          [56, 56, 56, 54],
          [0, 0, 0, 0],
        ],
        lastRoll: 2,
        phase: TurnPhase.awaitingMove,
      );
      final result = game.applyMove(const Move(playerIndex: 0, tokenIndex: 3));
      expect(result.isWinningMove, isTrue);
      expect(game.isFinished, isTrue);
      expect(game.winnerIndex, 0);
      expect(() => game.rollDice(), throwsStateError);
    });
  });

  group('extra turns and consecutive sixes (FR-20, BR-06/BR-07)', () {
    test('a six grants an extra roll to the same player', () {
      final game = freshGame(const [6, 2]);
      game.rollDice(); // 6
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(game.currentPlayerIndex, 0); // extra roll, not player 2
      expect(game.state.phase, TurnPhase.awaitingRoll);
      game.rollDice(); // 2
      expect(game.state.phase, TurnPhase.awaitingMove);
    });

    test('a non-six move passes the turn clockwise', () {
      final game = freshGame(const [6, 3]);
      game.rollDice();
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      game.rollDice(); // 3, token on track moves
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(game.currentPlayerIndex, 1);
    });

    test('a third consecutive six is not played and the turn passes', () {
      final game = freshGame(const [6, 6, 6]);
      game.rollDice();
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      game.rollDice();
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 1));
      final third = game.rollDice();
      expect(third, 6);
      expect(game.state.lastRollWasThirdSix, isTrue);
      expect(game.currentPlayerIndex, 1); // turn passed
      expect(game.state.phase, TurnPhase.awaitingRoll);
    });

    test('reaching home grants an extra roll', () {
      final game = gameWith(
        tokenSteps: const [
          [56, 56, 0, 54],
          [0, 0, 0, 0],
        ],
        lastRoll: 2,
        phase: TurnPhase.awaitingMove,
        diceRoller: FixedDiceRoller(const [4]),
      );
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 3));
      expect(game.isFinished, isFalse);
      expect(game.currentPlayerIndex, 0); // extra roll for reaching home
    });
  });

  group('no legal move (FR-21, BR-13)', () {
    test('a roll with no legal move passes the turn', () {
      // All red tokens are 1 step from home; roll 3 overshoots all.
      final game = gameWith(
        tokenSteps: const [
          [55, 55, 55, 55],
          [0, 0, 0, 0],
        ],
        diceRoller: FixedDiceRoller(const [3]),
      );
      game.rollDice();
      expect(game.state.lastRollHadNoLegalMove, isTrue);
      expect(game.currentPlayerIndex, 1);
    });

    test('a six with no legal move still grants its extra roll', () {
      final game = gameWith(
        tokenSteps: const [
          [55, 55, 55, 55],
          [0, 0, 0, 0],
        ],
        diceRoller: FixedDiceRoller(const [6]),
      );
      game.rollDice();
      expect(game.state.lastRollHadNoLegalMove, isTrue);
      expect(game.currentPlayerIndex, 0); // same player rolls again
      expect(game.state.phase, TurnPhase.awaitingRoll);
    });
  });

  group('invalid moves (FR-21)', () {
    test('an illegal move is rejected and the state is unchanged', () {
      final game = gameWith(
        tokenSteps: const [
          [54, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        lastRoll: 3,
        phase: TurnPhase.awaitingMove,
      );
      final before = game.snapshot();
      // Token 0 cannot move on a 3 (54 + 3 overshoots 56).
      expect(
        () => game.applyMove(const Move(playerIndex: 0, tokenIndex: 0)),
        throwsArgumentError,
      );
      expect(game.snapshot(), before);
    });

    test('moving before rolling is rejected', () {
      final game = freshGame(const [6]);
      expect(
        () => game.applyMove(const Move(playerIndex: 0, tokenIndex: 0)),
        throwsStateError,
      );
    });

    test('moving another player\'s token is rejected', () {
      final game = gameWith(
        tokenSteps: const [
          [5, 0, 0, 0],
          [5, 0, 0, 0],
        ],
        lastRoll: 2,
        phase: TurnPhase.awaitingMove,
      );
      expect(
        () => game.applyMove(const Move(playerIndex: 1, tokenIndex: 0)),
        throwsArgumentError,
      );
    });
  });
}
