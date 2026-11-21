import 'dart:convert';

import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/engine/move.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:flutter_test/flutter_test.dart';

/// M1.6 AI-difficulty fix: `LudoGame.newMatch` builds AI seats as
/// [AiPlayer]s carrying the seat difficulty, so snapshots written
/// from a live match resume with the true difficulty instead of
/// defaulting every AI seat to easy (the M1.1 limit: the old
/// `newMatch` built plain [Player]s of type AI, whose `toJson`
/// carries no difficulty).
void main() {
  test('newMatch builds AI seats as AiPlayers with the seat difficulty',
      () {
    final game = LudoGame.newMatch(
      seats: const [
        SeatConfig(name: 'Player 1', colour: PlayerColour.red),
        SeatConfig(
          name: 'Player 2',
          colour: PlayerColour.green,
          type: PlayerType.ai,
          difficulty: AiDifficulty.hard,
        ),
      ],
    );
    final ai = game.state.players[1];
    expect(ai, isA<AiPlayer>());
    expect((ai as AiPlayer).difficulty, AiDifficulty.hard);
    expect(game.state.players[0], isNot(isA<AiPlayer>()));
  });

  test('newMatch AI seat without a difficulty defaults to easy', () {
    final game = LudoGame.newMatch(
      seats: const [
        SeatConfig(name: 'Player 1', colour: PlayerColour.red),
        SeatConfig(
          name: 'Player 2',
          colour: PlayerColour.green,
          type: PlayerType.ai,
        ),
      ],
    );
    final ai = game.state.players[1];
    expect(ai, isA<AiPlayer>());
    expect((ai as AiPlayer).difficulty, AiDifficulty.easy);
  });

  test('snapshot round-trip preserves the true AI difficulty', () {
    final game = LudoGame.newMatch(
      seats: const [
        SeatConfig(name: 'Player 1', colour: PlayerColour.red),
        SeatConfig(
          name: 'Player 2',
          colour: PlayerColour.green,
          type: PlayerType.ai,
          difficulty: AiDifficulty.hard,
        ),
      ],
      diceRoller: FixedDiceRoller([6]),
    );
    game.rollDice();
    game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));

    final json = game.snapshot();
    expect(
      (json['players'] as List)[1],
      containsPair('difficulty', 'hard'),
    );
    final restored = GameState.fromJson(
      jsonDecode(jsonEncode(json)) as Map<String, Object?>,
    );
    expect(restored.moveCount, 1);
    expect(restored.startedAt, game.state.startedAt);
    final restoredAi = restored.players[1];
    expect(restoredAi, isA<AiPlayer>());
    expect((restoredAi as AiPlayer).difficulty, AiDifficulty.hard);
    // The restored game plays on with the hard AI seat intact.
    final resumed = LudoGame.fromState(restored);
    expect(resumed.state.players[1], isA<AiPlayer>());
  });

  test('AI seat stays an AiPlayer with its difficulty after a move',
      () {
    final game = LudoGame.newMatch(
      seats: const [
        SeatConfig(name: 'Player 1', colour: PlayerColour.red),
        SeatConfig(
          name: 'Player 2',
          colour: PlayerColour.green,
          type: PlayerType.ai,
          difficulty: AiDifficulty.medium,
        ),
      ],
      diceRoller: FixedDiceRoller([6]),
    );
    game.rollDice();
    game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
    final ai = game.state.players[1];
    expect(ai, isA<AiPlayer>());
    expect((ai as AiPlayer).difficulty, AiDifficulty.medium);
  });
}
