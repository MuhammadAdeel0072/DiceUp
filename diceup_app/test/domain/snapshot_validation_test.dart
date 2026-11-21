import 'dart:convert';

import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/engine/move.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/ruleset_config.dart';
import 'package:diceup/domain/engine/token.dart';
import 'package:test/test.dart';

import '../engine/test_helpers.dart';

/// A snapshot of a played 2-player match, decoded from JSON (the same
/// shape a persisted snapshot has on disk).
Map<String, Object?> playedSnapshot() {
  final game = freshGame(const [6, 3, 6, 2, 5]);
  game.rollDice(); // 6: red releases token 0
  game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
  game.rollDice(); // 3: red moves token 0 (extra roll from the 6)
  game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
  game.rollDice(); // 6: green releases token 1
  game.applyMove(const Move(playerIndex: 1, tokenIndex: 1));
  return jsonDecode(jsonEncode(game.snapshot())) as Map<String, Object?>;
}

Map<String, Object?> playerOf(Map<String, Object?> json, int index) =>
    (json['players'] as List)[index] as Map<String, Object?>;

Map<String, Object?> tokenOf(
  Map<String, Object?> json,
  int player,
  int token,
) =>
    (playerOf(json, player)['tokens'] as List)[token]
        as Map<String, Object?>;

Map<String, Object?> rulesetOf(Map<String, Object?> json) =>
    json['ruleset'] as Map<String, Object?>;

/// A finished 2-player match: red has all four tokens home.
Map<String, Object?> finishedSnapshot() {
  final state = GameState(
    players: [
      Player(
        index: 0,
        name: 'Red',
        colour: PlayerColour.red,
        type: PlayerType.human,
        tokens: List<Token>.generate(
          4,
          (i) => Token(
            playerIndex: 0,
            index: i,
            colour: PlayerColour.red,
            stepsTaken: 56,
          ),
        ),
      ),
      Player(
        index: 1,
        name: 'Green',
        colour: PlayerColour.green,
        type: PlayerType.human,
      ),
    ],
    currentPlayerIndex: 0,
    rulesetVersion: '1.0.0',
    phase: TurnPhase.finished,
    winnerIndex: 0,
  );
  return jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>;
}

void main() {
  group('valid snapshot round trips (M1.1)', () {
    test('a played match round-trips exactly', () {
      final json = playedSnapshot();
      final restored = LudoGame.restore(json);
      expect(jsonEncode(restored.snapshot()), jsonEncode(json));
      // After red's extra turn and green's release, it is green's turn.
      expect(restored.state.currentPlayerIndex, 1);
      expect(restored.state.moveCount, 3);
      expect(restored.players[0].tokens[0].stepsTaken, 4);
      expect(restored.players[1].tokens[1].stepsTaken, 1);
    });

    test('the snapshot has no moveHistory (D-23)', () {
      expect(playedSnapshot().containsKey('moveHistory'), isFalse);
    });

    test('AI difficulty round-trips for every difficulty', () {
      for (final difficulty in AiDifficulty.values) {
        final state = GameState(
          players: [
            Player(
              index: 0,
              name: 'Red',
              colour: PlayerColour.red,
              type: PlayerType.human,
            ),
            AiPlayer(
              index: 1,
              name: 'Green',
              colour: PlayerColour.green,
              difficulty: difficulty,
            ),
          ],
          currentPlayerIndex: 0,
          rulesetVersion: '1.0.0',
        );
        final json =
            jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>;
        expect(playerOf(json, 1)['difficulty'], difficulty.name);
        final restored = GameState.fromJson(json);
        final ai = restored.players[1];
        expect(ai, isA<AiPlayer>());
        expect((ai as AiPlayer).difficulty, difficulty);
        expect(restored.players[0], isNot(isA<AiPlayer>()));
      }
    });

    test('a missing AI difficulty defaults to Easy', () {
      final json = playedSnapshot();
      playerOf(json, 1)['type'] = 'ai';
      playerOf(json, 1).remove('difficulty');
      final restored = GameState.fromJson(json);
      final ai = restored.players[1];
      expect(ai, isA<AiPlayer>());
      expect((ai as AiPlayer).difficulty, AiDifficulty.easy);
    });

    test('the full ruleset round-trips and agrees with rulesetVersion',
        () {
      const ruleset = RulesetConfig(
        releaseOnSix: true,
        releaseOnOne: true,
        extraTurnOnSix: false,
        extraTurnOnCapture: true,
        extraTurnOnHome: false,
        maxConsecutiveSixes: 0,
        exactFinish: false,
        version: '1.2.0',
      );
      final game = freshGame(const [1], ruleset: ruleset);
      final snapshot = game.snapshot();
      expect(snapshot['rulesetVersion'], '1.2.0');
      expect(snapshot['ruleset'], ruleset.toJson());
      final restored = LudoGame.restore(
        jsonDecode(jsonEncode(snapshot)) as Map<String, Object?>,
        ruleset: ruleset,
      );
      expect(restored.state.ruleset, ruleset);
      expect(restored.state.rulesetVersion, '1.2.0');
    });

    test('startedAt round-trips as ISO-8601', () {
      final startedAt = DateTime.utc(2026, 11, 21, 17, 30);
      final state = GameState(
        players: [
          Player(
            index: 0,
            name: 'Red',
            colour: PlayerColour.red,
            type: PlayerType.human,
          ),
          Player(
            index: 1,
            name: 'Green',
            colour: PlayerColour.green,
            type: PlayerType.human,
          ),
        ],
        currentPlayerIndex: 0,
        rulesetVersion: '1.0.0',
        startedAt: startedAt,
      );
      final json =
          jsonDecode(jsonEncode(state.toJson())) as Map<String, Object?>;
      expect(json['startedAt'], '2026-11-21T17:30:00.000Z');
      expect(GameState.fromJson(json).startedAt, startedAt);
    });

    test('a missing or null startedAt is tolerated', () {
      final missing = playedSnapshot()..remove('startedAt');
      expect(GameState.fromJson(missing).startedAt, isNull);
      final nulled = playedSnapshot()..['startedAt'] = null;
      expect(GameState.fromJson(nulled).startedAt, isNull);
    });

    test('unknown top-level keys are ignored', () {
      final json = playedSnapshot()..['futureField'] = 'from v2';
      expect(GameState.fromJson(json).moveCount, 3);
    });

    test('a finished match round-trips with its winner', () {
      final restored = GameState.fromJson(finishedSnapshot());
      expect(restored.phase, TurnPhase.finished);
      expect(restored.winnerIndex, 0);
      expect(restored.isFinished, isTrue);
      final game = LudoGame.fromState(restored);
      expect(game.isFinished, isTrue);
      expect(game.winnerIndex, 0);
    });

    test('AiPlayer.copyWith preserves difficulty through applyMove', () {
      final state = GameState(
        players: [
          Player(
            index: 0,
            name: 'Red',
            colour: PlayerColour.red,
            type: PlayerType.human,
          ),
          AiPlayer(
            index: 1,
            name: 'Green',
            colour: PlayerColour.green,
            difficulty: AiDifficulty.hard,
          ),
        ],
        currentPlayerIndex: 1,
        rulesetVersion: '1.0.0',
        phase: TurnPhase.awaitingMove,
        lastRoll: 6,
      );
      final game = LudoGame.fromState(state);
      game.applyMove(const Move(playerIndex: 1, tokenIndex: 0));
      final player = game.state.players[1];
      expect(player, isA<AiPlayer>());
      expect((player as AiPlayer).difficulty, AiDifficulty.hard);
      expect(player.tokens[0].stepsTaken, 1);
      // And the difficulty survives a snapshot round-trip after the move.
      final restored = GameState.fromJson(
        jsonDecode(jsonEncode(game.snapshot())) as Map<String, Object?>,
      );
      expect((restored.players[1] as AiPlayer).difficulty, AiDifficulty.hard);
    });

    test('LudoGame.restore propagates FormatException', () {
      final json = playedSnapshot()..['formatVersion'] = 2;
      expect(() => LudoGame.restore(json), throwsFormatException);
    });
  });

  group('malformed snapshots are rejected with FormatException (M-11)',
      () {
    final rejects = <String, void Function(Map<String, Object?>)>{
      'missing formatVersion': (j) => j.remove('formatVersion'),
      'formatVersion 2': (j) => j['formatVersion'] = 2,
      'formatVersion as a string': (j) => j['formatVersion'] = '1',
      'formatVersion as a double': (j) => j['formatVersion'] = 1.0,
      'missing players': (j) => j.remove('players'),
      'players is not a list': (j) => j['players'] = {'red': true},
      'one player': (j) =>
          j['players'] = (j['players'] as List).sublist(0, 1),
      'five players': (j) {
        final players = j['players'] as List;
        while (players.length < 5) {
          players.add(jsonDecode(jsonEncode(players[0])));
        }
      },
      'zero players': (j) => j['players'] = <Object?>[],
      'duplicate colours': (j) => playerOf(j, 1)['colour'] = 'red',
      'zero human players': (j) {
        playerOf(j, 0)['type'] = 'ai';
        playerOf(j, 1)['type'] = 'ai';
      },
      'unknown colour': (j) => playerOf(j, 0)['colour'] = 'purple',
      'missing colour': (j) => playerOf(j, 0).remove('colour'),
      'unknown player type': (j) => playerOf(j, 0)['type'] = 'robot',
      'missing player type': (j) => playerOf(j, 0).remove('type'),
      'missing name': (j) => playerOf(j, 0).remove('name'),
      'name as a number': (j) => playerOf(j, 0)['name'] = 42,
      'unknown phase': (j) => j['phase'] = 'waiting',
      'missing phase': (j) => j.remove('phase'),
      'currentPlayerIndex -1': (j) => j['currentPlayerIndex'] = -1,
      'currentPlayerIndex out of range': (j) => j['currentPlayerIndex'] = 2,
      'currentPlayerIndex as a string': (j) => j['currentPlayerIndex'] = '0',
      'lastRoll 7': (j) => j['lastRoll'] = 7,
      'lastRoll -1': (j) => j['lastRoll'] = -1,
      'lastRoll as a string': (j) => j['lastRoll'] = '3',
      'consecutiveSixes 3': (j) => j['consecutiveSixes'] = 3,
      'consecutiveSixes -1': (j) => j['consecutiveSixes'] = -1,
      'moveCount -1': (j) => j['moveCount'] = -1,
      'moveCount as a string': (j) => j['moveCount'] = '4',
      'missing moveCount': (j) => j.remove('moveCount'),
      'lastRollWasThirdSix as a string': (j) =>
          j['lastRollWasThirdSix'] = 'false',
      'winnerIndex set while not finished': (j) => j['winnerIndex'] = 0,
      'winnerIndex as a string': (j) => j['winnerIndex'] = '0',
      'token stepsTaken 57': (j) => tokenOf(j, 0, 0)['stepsTaken'] = 57,
      'token stepsTaken -1': (j) => tokenOf(j, 0, 0)['stepsTaken'] = -1,
      'token stepsTaken as a string': (j) =>
          tokenOf(j, 0, 0)['stepsTaken'] = '0',
      'player with 3 tokens': (j) => playerOf(j, 0)['tokens'] =
          (playerOf(j, 0)['tokens'] as List).sublist(0, 3),
      'tokens is not a list': (j) => playerOf(j, 0)['tokens'] = 'nope',
      'token entry is not a map': (j) =>
          (playerOf(j, 0)['tokens'] as List)[0] = 42,
      'player entry is not a map': (j) => (j['players'] as List)[0] = 'red',
      'missing ruleset': (j) => j.remove('ruleset'),
      'ruleset is not a map': (j) => j['ruleset'] = '1.0.0',
      'ruleset missing a field': (j) => rulesetOf(j).remove('exactFinish'),
      'ruleset field with wrong type': (j) =>
          rulesetOf(j)['releaseOnSix'] = 'yes',
      'ruleset with no release roll': (j) {
        rulesetOf(j)['releaseOnSix'] = false;
        rulesetOf(j)['releaseOnOne'] = false;
      },
      'ruleset with negative maxConsecutiveSixes': (j) =>
          rulesetOf(j)['maxConsecutiveSixes'] = -1,
      'ruleset with empty version': (j) => rulesetOf(j)['version'] = '',
      'ruleset version disagrees with rulesetVersion': (j) =>
          rulesetOf(j)['version'] = '9.9.9',
      'missing rulesetVersion': (j) => j.remove('rulesetVersion'),
      'rulesetVersion as a number': (j) => j['rulesetVersion'] = 1.2,
      'malformed startedAt': (j) => j['startedAt'] = 'not-a-date',
      'startedAt as a number': (j) => j['startedAt'] = 12345,
      'unknown AI difficulty': (j) {
        playerOf(j, 1)['type'] = 'ai';
        playerOf(j, 1)['difficulty'] = 'insane';
      },
      'AI difficulty as a number': (j) {
        playerOf(j, 1)['type'] = 'ai';
        playerOf(j, 1)['difficulty'] = 42;
      },
    };

    for (final entry in rejects.entries) {
      test('rejects ${entry.key}', () {
        final json = playedSnapshot();
        entry.value(json);
        expect(
          () => GameState.fromJson(json),
          throwsFormatException,
        );
      });
    }

    test('rejects a finished snapshot with no winnerIndex', () {
      final json = finishedSnapshot()..remove('winnerIndex');
      expect(() => GameState.fromJson(json), throwsFormatException);
    });

    test('rejects a finished snapshot with an out-of-range winnerIndex',
        () {
      final json = finishedSnapshot()..['winnerIndex'] = 5;
      expect(() => GameState.fromJson(json), throwsFormatException);
    });
  });
}

// KNOWN ARCHITECTURE LIMIT (M1.1 — do not restructure to fix it; that is
// M3/M1.6 wiring): LudoGame.newMatch builds plain Players for AI seats
// and the game screen keeps each AI's difficulty in a separate
// _aiPlayers map, so a snapshot taken from a real game-screen match
// serialises AI seats without difficulty and restores them as Easy.
// M1.1 makes the round-trip exact WHEN the state holds AiPlayer
// instances (see the AI tests above); the game-screen wiring that
// puts AiPlayers into the state lands with M1.6/M3.
