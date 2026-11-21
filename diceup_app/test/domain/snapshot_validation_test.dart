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
    // Fixed timestamp (not DateTime.now()): the finished snapshot is
    // hand-built, and strict deserialization requires a startedAt.
    startedAt: DateTime.utc(2026, 11, 21, 12, 0),
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
          // Fixed timestamp: strict deserialization requires startedAt.
          startedAt: DateTime.utc(2026, 11, 21, 12, 0),
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

    test('a GameState can be built in memory without startedAt', () {
      // The constructor keeps startedAt nullable: in-memory/test-only
      // states need no timestamp. Only the persisted-snapshot path
      // (fromJson) is strict — see the rejects below.
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
      );
      expect(state.startedAt, isNull);
    });

    test('startedAt accepts ISO-8601 with an offset and fractional seconds',
        () {
      // tryParse normalises an offset to the same UTC instant, so the
      // re-emitted string is the UTC rendering, not the input text.
      // What must survive exactly is the instant.
      for (final value in [
        '2026-11-21T17:30:00.000+05:00',
        '2026-11-21T17:30:00.123456Z',
      ]) {
        final json = playedSnapshot()..['startedAt'] = value;
        final restored = GameState.fromJson(json);
        expect(
          restored.startedAt!.microsecondsSinceEpoch,
          DateTime.parse(value).microsecondsSinceEpoch,
        );
      }
      // The fractional-seconds Z form also re-emits string-identically.
      final fractional = playedSnapshot()
        ..['startedAt'] = '2026-11-21T17:30:00.123456Z';
      expect(
        GameState.fromJson(fractional).toJson()['startedAt'],
        '2026-11-21T17:30:00.123456Z',
      );
    });

    test('startedAt accepts a naive date-time (the snapshot writer format)',
        () {
      // GameState.initial stamps DateTime.now(), whose toIso8601String
      // has no zone suffix — a persisted snapshot therefore carries a
      // naive timestamp, and the strict check must accept it.
      final json = playedSnapshot()..['startedAt'] = '2026-11-21T17:30:00';
      final restored = GameState.fromJson(json);
      expect(restored.startedAt, DateTime(2026, 11, 21, 17, 30));
    });

    test('startedAt accepts a plain UTC timestamp and a leap day', () {
      final utc = playedSnapshot()..['startedAt'] = '2026-11-21T17:30:00Z';
      expect(
        GameState.fromJson(utc).startedAt,
        DateTime.utc(2026, 11, 21, 17, 30),
      );
      // Positive control for the leap-year logic: Feb 29 is valid in
      // a leap year (and rejected in a non-leap year — see the rejects
      // below).
      final leap = playedSnapshot()
        ..['startedAt'] = '2024-02-29T12:00:00Z';
      expect(
        GameState.fromJson(leap).startedAt,
        DateTime.utc(2024, 2, 29, 12),
      );
    });

    test('startedAt preserves the instant for timezone offsets', () {
      // +05:00 means 17:30 local is 12:30 UTC; -05:00 means 22:30 UTC.
      final plus = playedSnapshot()
        ..['startedAt'] = '2026-11-21T17:30:00+05:00';
      expect(
        GameState.fromJson(plus).startedAt!.microsecondsSinceEpoch,
        DateTime.utc(2026, 11, 21, 12, 30).microsecondsSinceEpoch,
      );
      final minus = playedSnapshot()
        ..['startedAt'] = '2026-11-21T17:30:00-05:00';
      expect(
        GameState.fromJson(minus).startedAt!.microsecondsSinceEpoch,
        DateTime.utc(2026, 11, 21, 22, 30).microsecondsSinceEpoch,
      );
    });

    test('consecutiveSixes follows the embedded ruleset limit', () {
      // maxConsecutiveSixes 3 (default): 2 accepted (3 is rejected —
      // see the rejects below).
      final limited = playedSnapshot()..['consecutiveSixes'] = 2;
      expect(GameState.fromJson(limited).consecutiveSixes, 2);
      // maxConsecutiveSixes 2: 1 accepted, 2 rejected.
      final two = playedSnapshot();
      rulesetOf(two)['maxConsecutiveSixes'] = 2;
      two['consecutiveSixes'] = 1;
      expect(GameState.fromJson(two).consecutiveSixes, 1);
      two['consecutiveSixes'] = 2;
      expect(() => GameState.fromJson(two), throwsFormatException);
      // maxConsecutiveSixes 1: only 0 accepted.
      final one = playedSnapshot();
      rulesetOf(one)['maxConsecutiveSixes'] = 1;
      one['consecutiveSixes'] = 0;
      expect(GameState.fromJson(one).consecutiveSixes, 0);
      one['consecutiveSixes'] = 1;
      expect(() => GameState.fromJson(one), throwsFormatException);
    });

    test('a disabled third-six limit accepts any consecutiveSixes', () {
      for (final count in [5, 10]) {
        final json = playedSnapshot();
        rulesetOf(json)['maxConsecutiveSixes'] = 0;
        json['consecutiveSixes'] = count;
        expect(GameState.fromJson(json).consecutiveSixes, count);
      }
    });

    test('four consecutive sixes under a disabled limit round-trip '
        'through the engine', () {
      // D-29: maxConsecutiveSixes 0 disables the third-six limit, so
      // the count is never reset and a legitimate snapshot holds 4.
      const ruleset = RulesetConfig(maxConsecutiveSixes: 0);
      final game = freshGame(const [6, 6, 6, 6], ruleset: ruleset);
      for (var i = 0; i < 3; i++) {
        game.rollDice();
        game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      }
      game.rollDice(); // fourth consecutive six
      expect(game.state.consecutiveSixes, 4);
      final json =
          jsonDecode(jsonEncode(game.snapshot())) as Map<String, Object?>;
      final restored = LudoGame.restore(json, ruleset: ruleset);
      expect(jsonEncode(restored.snapshot()), jsonEncode(json));
      expect(restored.state.consecutiveSixes, 4);
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
        // Fixed timestamp: strict deserialization requires startedAt.
        startedAt: DateTime.utc(2026, 11, 21, 12, 0),
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
      'missing startedAt': (j) => j.remove('startedAt'),
      'startedAt is null': (j) => j['startedAt'] = null,
      'startedAt is an empty string': (j) => j['startedAt'] = '',
      'startedAt with wrong separators': (j) =>
          j['startedAt'] = '2026/11/21T17:30:00Z',
      'malformed startedAt': (j) => j['startedAt'] = 'not-a-date',
      'startedAt as a number': (j) => j['startedAt'] = 12345,
      // Strict ISO-8601 date-time (M1.1 review): tryParse alone
      // normalises these, so the component checks must reject them.
      'startedAt month 13 day 45 hour 99': (j) =>
          j['startedAt'] = '2026-13-45T99:99:99Z',
      'startedAt hour 99': (j) =>
          j['startedAt'] = '2026-11-21T99:99:99Z',
      'startedAt month 13': (j) =>
          j['startedAt'] = '2026-13-21T17:30:00Z',
      'startedAt month 00': (j) =>
          j['startedAt'] = '2026-00-21T17:30:00Z',
      'startedAt Feb 30': (j) =>
          j['startedAt'] = '2026-02-30T17:30:00Z',
      'startedAt Feb 29 in a non-leap year': (j) =>
          j['startedAt'] = '2026-02-29T17:30:00Z',
      'startedAt April 31': (j) =>
          j['startedAt'] = '2026-04-31T17:30:00Z',
      'startedAt hour 24': (j) =>
          j['startedAt'] = '2026-11-21T24:30:00Z',
      'startedAt minute 60': (j) =>
          j['startedAt'] = '2026-11-21T23:60:00Z',
      'startedAt second 60': (j) =>
          j['startedAt'] = '2026-11-21T23:59:60Z',
      'startedAt date-only': (j) => j['startedAt'] = '2026-11-21',
      'startedAt with space separator': (j) =>
          j['startedAt'] = '2026-11-21 17:30:00Z',
      'startedAt offset hour 25': (j) =>
          j['startedAt'] = '2026-11-21T17:30:00+25:00',
      'startedAt offset minute 60': (j) =>
          j['startedAt'] = '2026-11-21T17:30:00+05:60',
      'startedAt without seconds': (j) =>
          j['startedAt'] = '2026-11-21T17:30Z',
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
