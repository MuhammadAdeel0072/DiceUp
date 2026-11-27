import 'dart:convert';

import 'package:diceup/domain/engine/board.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/engine/move.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/ruleset_config.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('snapshot round-trip (SDD §6.1/§6.6, SRS FR-29)', () {
    test('a played match serialises to JSON and restores exactly', () {
      final game = freshGame(const [6, 3, 6, 2, 5]);
      game.rollDice(); // 6: red releases token 0
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      game.rollDice(); // 3: red moves token 0 (extra roll from the 6)
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      game.rollDice(); // 6: green releases token 1
      game.applyMove(const Move(playerIndex: 1, tokenIndex: 1));

      final json = jsonEncode(game.snapshot());
      final decoded = jsonDecode(json) as Map<String, Object?>;
      final restored = LudoGame.restore(decoded);

      expect(jsonEncode(restored.snapshot()), json);
      expect(restored.state.currentPlayerIndex, game.state.currentPlayerIndex);
      expect(restored.state.moveCount, game.state.moveCount);
      expect(restored.players[0].tokens[0].stepsTaken, 4);
      expect(restored.players[1].tokens[1].stepsTaken, 1);
    });

    test('a mid-turn snapshot restores the same legal moves', () {
      final game = gameWith(
        tokenSteps: const [
          [10, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        lastRoll: 4,
        phase: TurnPhase.awaitingMove,
      );
      final before = game.legalMoves();
      final restored = LudoGame.restore(
        jsonDecode(jsonEncode(game.snapshot())) as Map<String, Object?>,
      );
      expect(restored.state.phase, TurnPhase.awaitingMove);
      expect(restored.legalMoves(), before);
    });

    test('play can continue after a restore', () {
      final game = freshGame(const [6, 3]);
      game.rollDice();
      game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      final restored = LudoGame.restore(
        jsonDecode(jsonEncode(game.snapshot())) as Map<String, Object?>,
        diceRoller: FixedDiceRoller(const [3]),
      );
      expect(restored.rollDice(), 3);
      final result = restored.applyMove(
        const Move(playerIndex: 0, tokenIndex: 0),
      );
      expect(result.toSteps, 4);
    });

    test('a snapshot from another ruleset version is rejected', () {
      final game = freshGame(const [6]);
      const other = RulesetConfig(version: '2.0.0');
      expect(
        () => LudoGame.restore(
          jsonDecode(jsonEncode(game.snapshot())) as Map<String, Object?>,
          ruleset: other,
        ),
        throwsArgumentError,
      );
    });

    test('the snapshot carries the ruleset version (BR-14)', () {
      const ruleset = RulesetConfig(version: '1.2.0');
      final game = freshGame(const [1], ruleset: ruleset);
      final snapshot = game.snapshot();
      expect(snapshot['rulesetVersion'], '1.2.0');
      expect(snapshot['formatVersion'], 1);
    });
  });

  group('board geometry (SDD §6.2, SRS §7.1)', () {
    test('track has 52 cells, journey is 56 steps', () {
      expect(Board.trackSize, 52);
      expect(Board.stepsToHome, 56);
      expect(Board.homePathLength, 4);
    });

    test('start cells are 13 apart and star cells are 8 past them', () {
      const board = Board();
      expect(board.startCell(PlayerColour.red), 0);
      expect(board.startCell(PlayerColour.green), 13);
      expect(board.startCell(PlayerColour.yellow), 26);
      expect(board.startCell(PlayerColour.blue), 39);
      expect(Board.starCells, {8, 21, 34, 47});
    });

    test('a token walks the full path: yard, track, home path, home', () {
      const board = Board();
      expect(board.cellAt(PlayerColour.red, 0), const Cell.yard());
      expect(board.cellAt(PlayerColour.red, 1), const Cell.track(0));
      expect(board.cellAt(PlayerColour.red, 51), const Cell.track(50));
      expect(board.cellAt(PlayerColour.red, 52), const Cell.homePath(0));
      expect(board.cellAt(PlayerColour.red, 56), const Cell.home());
      // Green wraps around the track: step 40 lands on track 0.
      expect(board.cellAt(PlayerColour.green, 40), const Cell.track(0));
    });
  });
}
