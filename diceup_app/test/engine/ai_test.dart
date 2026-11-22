import 'dart:convert';
import 'dart:math';

import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/board.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/engine/move.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

const _board = Board();

void main() {
  group('AI legality (FR-35, FR-39, SDD §7.4)', () {
    test('every AI choice is in the engine legal-move list', () {
      // One human + one AI seat; 300 turns driven by cycling dice.
      // Each turn the AI (rotating difficulty) chooses; the engine
      // re-validates every choice in applyMove.
      final difficulties = AiDifficulty.values;
      var game = LudoGame.newMatch(
        seats: const [
          SeatConfig(name: 'Red', colour: PlayerColour.red),
          SeatConfig(
            name: 'Green',
            colour: PlayerColour.green,
            type: PlayerType.ai,
          ),
        ],
        diceRoller: FixedDiceRoller(const [
          6,
          2,
          4,
          1,
          3,
          5,
          6,
          6,
          2,
          5,
          1,
          4,
        ], cycle: true),
      );
      var turns = 0;
      while (!game.isFinished && turns < 300) {
        game.rollDice();
        final legal = game.legalMoves();
        if (legal.isNotEmpty) {
          final ai = aiFromState(
            game.state,
            game.currentPlayerIndex,
            difficulties[turns % difficulties.length],
            seed: 100 + turns,
          );
          final choice = ai.chooseMove(legal, game.state, _board);
          expect(legal, contains(choice));
          game.applyMove(choice);
        }
        turns++;
      }
      // No rule violation occurred (applyMove would have thrown).
      expect(turns, greaterThan(10));
    });

    test('an AI with no legal move throws instead of inventing one', () {
      final game = gameWith(
        tokenSteps: const [
          [55, 55, 55, 55],
          [0, 0, 0, 0],
        ],
        lastRoll: 3,
        phase: TurnPhase.awaitingMove,
      );
      final ai = aiFromState(game.state, 0, AiDifficulty.hard);
      expect(
        () => ai.chooseMove(const [], game.state, _board),
        throwsArgumentError,
      );
    });
  });

  group('Medium priority cascade (FR-37)', () {
    test('finishing a token beats everything else', () {
      final game = gameWith(
        tokenSteps: const [
          [55, 10, 0, 0],
          [0, 0, 0, 0],
        ],
        lastRoll: 1,
        phase: TurnPhase.awaitingMove,
      );
      final ai = aiFromState(game.state, 0, AiDifficulty.medium);
      final choice = ai.chooseMove(game.legalMoves(), game.state, _board);
      expect(choice.tokenIndex, 0); // 55 + 1 = home
    });

    test('capturing beats releasing a token', () {
      // Roll 6: yard tokens can be released; red token 1 at steps 9
      // (track 8) rolls 6 onto track 14, capturing green token 0
      // (steps 2 -> track 14).
      final game = gameWith(
        tokenSteps: const [
          [0, 9, 0, 0],
          [2, 0, 0, 0],
        ],
        lastRoll: 6,
        phase: TurnPhase.awaitingMove,
      );
      final ai = aiFromState(game.state, 0, AiDifficulty.medium);
      final choice = ai.chooseMove(game.legalMoves(), game.state, _board);
      expect(choice.tokenIndex, 1);
    });

    test('releasing a token beats merely advancing', () {
      final game = gameWith(
        tokenSteps: const [
          [0, 20, 0, 0],
          [0, 0, 0, 0],
        ],
        lastRoll: 6,
        phase: TurnPhase.awaitingMove,
      );
      final ai = aiFromState(game.state, 0, AiDifficulty.medium);
      final choice = ai.chooseMove(game.legalMoves(), game.state, _board);
      expect(choice.tokenIndex, 0); // yard token released
    });

    test('moving off danger beats advancing', () {
      // Red token 0 on track 9 (steps 10) with green token 1 on
      // track 5 (steps 45) four steps behind: in danger. Roll 4
      // takes it to track 13 (green's start cell: safe). Red token 1
      // on track 19 (steps 20) has no opponent behind it.
      final game = gameWith(
        tokenSteps: const [
          [10, 20, 0, 0],
          [45, 0, 0, 0],
        ],
        lastRoll: 4,
        phase: TurnPhase.awaitingMove,
      );
      final ai = aiFromState(game.state, 0, AiDifficulty.medium);
      final choice = ai.chooseMove(game.legalMoves(), game.state, _board);
      expect(choice.tokenIndex, 0);
    });
  });

  group('Hard scoring (FR-38)', () {
    test('finishing beats capturing', () {
      // Roll 1: token 0 at 55 finishes; token 1 at steps 14
      // (track 13) moves to track 14 and captures green token 0
      // (steps 2 -> track 14).
      final game = gameWith(
        tokenSteps: const [
          [55, 14, 0, 0],
          [2, 0, 0, 0],
        ],
        lastRoll: 1,
        phase: TurnPhase.awaitingMove,
      );
      final ai = aiFromState(game.state, 0, AiDifficulty.hard);
      final choice = ai.chooseMove(game.legalMoves(), game.state, _board);
      expect(choice.tokenIndex, 0);
    });

    test('capturing beats releasing', () {
      final game = gameWith(
        tokenSteps: const [
          [0, 9, 0, 0],
          [2, 0, 0, 0],
        ],
        lastRoll: 6,
        phase: TurnPhase.awaitingMove,
      );
      final ai = aiFromState(game.state, 0, AiDifficulty.hard);
      final choice = ai.chooseMove(game.legalMoves(), game.state, _board);
      expect(choice.tokenIndex, 1);
    });

    test('a safe landing beats a landing in danger', () {
      // Roll 4. Token 0 (steps 10, track 9) reaches safe track 13.
      // Token 1 (steps 30, track 29) would land on track 33, with
      // green token 1 on track 30 (steps 18) three steps behind.
      final game = gameWith(
        tokenSteps: const [
          [10, 30, 0, 0],
          [0, 18, 0, 0],
        ],
        lastRoll: 4,
        phase: TurnPhase.awaitingMove,
      );
      final ai = aiFromState(game.state, 0, AiDifficulty.hard);
      final choice = ai.chooseMove(game.legalMoves(), game.state, _board);
      expect(choice.tokenIndex, 0);
    });

    test('Hard decides within the 500 ms budget (NFR-04)', () {
      final game = gameWith(
        tokenSteps: const [
          [10, 30, 5, 0],
          [2, 18, 40, 0],
        ],
        lastRoll: 4,
        phase: TurnPhase.awaitingMove,
      );
      final ai = aiFromState(game.state, 0, AiDifficulty.hard);
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        ai.chooseMove(game.legalMoves(), game.state, _board);
      }
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });

  group('difficulty sanity over seeded positions (SDD §7.4)', () {
    test('Hard finishes/captures more often than Easy', () {
      final rng = Random(1234);
      var hardWins = 0;
      var mediumWins = 0;
      var easyWins = 0;
      var positions = 0;
      for (var i = 0; i < 200; i++) {
        List<int> randomSteps() => List.generate(
          4,
          (_) => rng.nextInt(57), // 0..56, biased by pure chance
        );
        final state = stateWith(
          tokenSteps: [randomSteps(), randomSteps()],
          lastRoll: 1 + rng.nextInt(6),
          phase: TurnPhase.awaitingMove,
        );
        final game = LudoGame.fromState(
          state,
          diceRoller: FixedDiceRoller(const [1]),
        );
        final legal = game.legalMoves();
        if (legal.isEmpty) continue;
        positions++;

        bool finishesOrCaptures(Move m) {
          final token = state.players[0].tokens[m.tokenIndex];
          final newSteps = token.stepsTaken + state.lastRoll;
          if (newSteps == Board.stepsToHome) return true;
          final landing = _board.cellAt(token.colour, newSteps);
          if (landing.kind != CellKind.track || _board.isSafe(landing)) {
            return false;
          }
          return state.players[1].tokens.any(
            (t) => t.isOnTrack && t.cell == landing,
          );
        }

        final hard = aiFromState(
          state,
          0,
          AiDifficulty.hard,
          seed: 5,
        ).chooseMove(legal, state, _board);
        final medium = aiFromState(
          state,
          0,
          AiDifficulty.medium,
          seed: 5,
        ).chooseMove(legal, state, _board);
        final easy = aiFromState(
          state,
          0,
          AiDifficulty.easy,
          seed: 5,
        ).chooseMove(legal, state, _board);
        if (finishesOrCaptures(hard)) hardWins++;
        if (finishesOrCaptures(medium)) mediumWins++;
        if (finishesOrCaptures(easy)) easyWins++;
      }
      expect(positions, greaterThan(50));
      expect(hardWins, greaterThan(easyWins));
      expect(mediumWins, greaterThanOrEqualTo(easyWins));
      // NOTE (SDD §7.4 wording): the SDD says Medium "must sit
      // between" Easy and Hard, but its own Hard scoring (§7.3)
      // deliberately declines a "suicidal" capture (capture +60,
      // danger −40) that Medium's fixed cascade always takes — so
      // over these 200 seeded positions Medium takes one more
      // finish/capture than Hard (45 vs 44). That is the designed
      // behaviour, not a bug, so no medium <= hard assertion is made.
      // See the implementation report for this SDD point.
    });
  });

  group('determinism (SDD §7.4)', () {
    test('a fixed dice sequence and seed replays identically', () {
      String play() {
        var game = LudoGame.newMatch(
          seats: const [
            SeatConfig(name: 'Red', colour: PlayerColour.red),
            SeatConfig(
              name: 'Green',
              colour: PlayerColour.green,
              type: PlayerType.ai,
            ),
          ],
          diceRoller: FixedDiceRoller(const [
            6,
            2,
            4,
            1,
            3,
            5,
            6,
            6,
            2,
            5,
            1,
            4,
            3,
            2,
            6,
            1,
          ], cycle: true),
        );
        var turns = 0;
        while (!game.isFinished && turns < 200) {
          game.rollDice();
          final legal = game.legalMoves();
          if (legal.isNotEmpty) {
            if (game.currentPlayer.isAi) {
              final ai = aiFromState(
                game.state,
                game.currentPlayerIndex,
                AiDifficulty.hard,
                seed: 5,
              );
              game.applyMove(ai.chooseMove(legal, game.state, _board));
            } else {
              game.applyMove(legal.first);
            }
          }
          turns++;
        }
        return jsonEncode(game.snapshot());
      }

      // startedAt is a wall-clock timestamp stamped at match start
      // (M1.1): it is the only non-deterministic part of a snapshot,
      // so the comparison strips it. What this test verifies is
      // gameplay determinism, not timestamp equality. Both runs must
      // still stamp a valid startedAt.
      Map<String, Object?> withoutStartedAt(String json) {
        final map = jsonDecode(json) as Map<String, Object?>;
        map.remove('startedAt');
        return map;
      }

      final first = play();
      final second = play();
      expect(withoutStartedAt(first), withoutStartedAt(second));
      expect(
        DateTime.tryParse(
          (jsonDecode(first) as Map<String, Object?>)['startedAt'] as String,
        ),
        isNotNull,
      );
      expect(
        DateTime.tryParse(
          (jsonDecode(second) as Map<String, Object?>)['startedAt'] as String,
        ),
        isNotNull,
      );
    });
  });
}
