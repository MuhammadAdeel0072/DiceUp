import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/board.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/move.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/token.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

void main() {
  group('Cell', () {
    test('the four constructors build the four kinds', () {
      expect(const Cell.yard().kind, CellKind.yard);
      expect(const Cell.track(5).kind, CellKind.track);
      expect(const Cell.homePath(2).kind, CellKind.homePath);
      expect(const Cell.home().kind, CellKind.home);
      expect(const Cell.yard().index, -1);
      expect(const Cell.track(5).index, 5);
      expect(const Cell.homePath(2).index, 2);
      expect(const Cell.home().index, -1);
    });

    test('isYard / isHome name the endpoints only', () {
      expect(const Cell.yard().isYard, isTrue);
      expect(const Cell.yard().isHome, isFalse);
      expect(const Cell.home().isHome, isTrue);
      expect(const Cell.home().isYard, isFalse);
      expect(const Cell.track(0).isYard, isFalse);
      expect(const Cell.track(0).isHome, isFalse);
      expect(const Cell.homePath(0).isYard, isFalse);
      expect(const Cell.homePath(0).isHome, isFalse);
    });

    test('equality is by kind and index', () {
      expect(const Cell.track(5), const Cell.track(5));
      expect(const Cell.track(5), isNot(const Cell.track(6)));
      // Same index, different kind: not equal.
      expect(const Cell.track(5), isNot(const Cell.homePath(5)));
      expect(const Cell.yard(), const Cell.yard());
      expect(const Cell.home(), const Cell.home());
      expect(const Cell.track(5) == Object(), isFalse);
      expect(const Cell.track(5).hashCode, const Cell.track(5).hashCode);
      // Equal cells collapse in a Set (== and hashCode agree).
      final duplicates = [const Cell.track(5), const Cell.track(5)];
      expect(duplicates.toSet().length, 1);
    });

    test('toString names the kind and index', () {
      expect(const Cell.track(5).toString(), 'Cell(CellKind.track, 5)');
      expect(const Cell.yard().toString(), 'Cell(CellKind.yard, -1)');
      expect(const Cell.home().toString(), 'Cell(CellKind.home, -1)');
    });
  });

  group('Board.cellAt / isSafe', () {
    test('cellAt throws on steps past home', () {
      const board = Board();
      expect(() => board.cellAt(PlayerColour.red, 57), throwsArgumentError);
      expect(() => board.cellAt(PlayerColour.red, 100), throwsArgumentError);
    });

    test('cellAt treats zero and negative steps as the yard', () {
      const board = Board();
      expect(board.cellAt(PlayerColour.red, 0), const Cell.yard());
      expect(board.cellAt(PlayerColour.red, -3), const Cell.yard());
    });

    test('cellAt maps every home-path step', () {
      const board = Board();
      expect(board.cellAt(PlayerColour.red, 52), const Cell.homePath(0));
      expect(board.cellAt(PlayerColour.red, 53), const Cell.homePath(1));
      expect(board.cellAt(PlayerColour.red, 54), const Cell.homePath(2));
      expect(board.cellAt(PlayerColour.red, 55), const Cell.homePath(3));
    });

    test('isSafe covers home-path and home cells, not plain track cells', () {
      const board = Board();
      expect(board.isSafe(const Cell.homePath(0)), isTrue);
      expect(board.isSafe(const Cell.homePath(3)), isTrue);
      expect(board.isSafe(const Cell.home()), isTrue);
      expect(board.isSafe(const Cell.track(9)), isFalse);
      expect(board.isSafe(const Cell.track(8)), isTrue);
      expect(board.isSafe(const Cell.yard()), isFalse);
    });

    test('startCell names every colour start', () {
      const board = Board();
      expect(board.startCell(PlayerColour.red), 0);
      expect(board.startCell(PlayerColour.green), 13);
      expect(board.startCell(PlayerColour.yellow), 26);
      expect(board.startCell(PlayerColour.blue), 39);
    });
  });

  group('Token', () {
    test('position predicates split at the 0 / 51 / 52 / 56 boundaries', () {
      Token at(int steps) => Token(
        playerIndex: 0,
        index: 0,
        colour: PlayerColour.red,
        stepsTaken: steps,
      );
      expect(at(0).isInYard, isTrue);
      expect(at(0).isOnTrack, isFalse);
      expect(at(0).isInHomePath, isFalse);
      expect(at(0).isHome, isFalse);
      expect(at(1).isOnTrack, isTrue);
      expect(at(51).isOnTrack, isTrue);
      expect(at(51).isInHomePath, isFalse);
      expect(at(52).isInHomePath, isTrue);
      expect(at(52).isOnTrack, isFalse);
      expect(at(55).isInHomePath, isTrue);
      expect(at(56).isInHomePath, isFalse);
      expect(at(56).isHome, isTrue);
      expect(at(56).isOnTrack, isFalse);
    });

    test('cell follows the token along its path', () {
      Token at(int steps) => Token(
        playerIndex: 0,
        index: 0,
        colour: PlayerColour.red,
        stepsTaken: steps,
      );
      expect(at(0).cell, const Cell.yard());
      expect(at(1).cell, const Cell.track(0));
      expect(at(52).cell, const Cell.homePath(0));
      expect(at(56).cell, const Cell.home());
    });

    test('canMove: yard release, exact-finish boundary, non-exact home', () {
      Token at(int steps) => Token(
        playerIndex: 0,
        index: 0,
        colour: PlayerColour.red,
        stepsTaken: steps,
      );
      // Yard: only a release roll moves it.
      expect(at(0).canMove(6, releaseRolls: {6}, exactFinish: true), isTrue);
      expect(at(0).canMove(3, releaseRolls: {6}, exactFinish: true), isFalse);
      expect(at(0).canMove(1, releaseRolls: {6, 1}, exactFinish: true), isTrue);
      // Exact finish: 55 + 1 is legal, 55 + 2 is not.
      expect(at(55).canMove(1, releaseRolls: {6}, exactFinish: true), isTrue);
      expect(at(55).canMove(2, releaseRolls: {6}, exactFinish: true), isFalse);
      // Non-exact variant: any roll moves a token that is not home,
      // and a token already home never moves.
      expect(at(55).canMove(6, releaseRolls: {6}, exactFinish: false), isTrue);
      expect(at(56).canMove(6, releaseRolls: {6}, exactFinish: false), isFalse);
      expect(at(56).canMove(1, releaseRolls: {6}, exactFinish: true), isFalse);
    });

    test('copyWith with no arguments preserves the token', () {
      const token = Token(
        playerIndex: 0,
        index: 2,
        colour: PlayerColour.red,
        stepsTaken: 7,
      );
      final copy = token.copyWith();
      expect(copy, token);
      expect(copy.stepsTaken, 7);
      expect(copy.playerIndex, 0);
      expect(copy.index, 2);
      expect(copy.colour, PlayerColour.red);
    });

    test('copyWith replaces only the steps', () {
      const token = Token(
        playerIndex: 0,
        index: 2,
        colour: PlayerColour.red,
        stepsTaken: 7,
      );
      final moved = token.copyWith(stepsTaken: 12);
      expect(moved.stepsTaken, 12);
      expect(moved.playerIndex, 0);
      expect(moved.index, 2);
      expect(moved.colour, PlayerColour.red);
      expect(token.stepsTaken, 7); // the original is untouched
    });

    test('sentToYard returns the token to the yard', () {
      const token = Token(
        playerIndex: 0,
        index: 0,
        colour: PlayerColour.red,
        stepsTaken: 20,
      );
      expect(token.sentToYard.stepsTaken, 0);
      expect(token.sentToYard.isInYard, isTrue);
      expect(token.stepsTaken, 20);
    });

    test('toJson / fromJson round-trip', () {
      const token = Token(
        playerIndex: 1,
        index: 3,
        colour: PlayerColour.green,
        stepsTaken: 42,
      );
      expect(token.toJson(), {'stepsTaken': 42});
      final restored = Token.fromJson(
        playerIndex: 1,
        index: 3,
        colour: PlayerColour.green,
        json: Map<String, Object?>.of(token.toJson()),
      );
      expect(restored, token);
    });

    test('equality is by owner, index, colour and steps', () {
      const token = Token(
        playerIndex: 0,
        index: 1,
        colour: PlayerColour.red,
        stepsTaken: 9,
      );
      expect(
        token,
        const Token(
          playerIndex: 0,
          index: 1,
          colour: PlayerColour.red,
          stepsTaken: 9,
        ),
      );
      expect(
        token,
        isNot(
          const Token(
            playerIndex: 1,
            index: 1,
            colour: PlayerColour.red,
            stepsTaken: 9,
          ),
        ),
      );
      expect(
        token,
        isNot(
          const Token(
            playerIndex: 0,
            index: 2,
            colour: PlayerColour.red,
            stepsTaken: 9,
          ),
        ),
      );
      expect(
        token,
        isNot(
          const Token(
            playerIndex: 0,
            index: 1,
            colour: PlayerColour.green,
            stepsTaken: 9,
          ),
        ),
      );
      expect(
        token,
        isNot(
          const Token(
            playerIndex: 0,
            index: 1,
            colour: PlayerColour.red,
            stepsTaken: 10,
          ),
        ),
      );
      expect(token == Object(), isFalse);
      expect(token.hashCode, token.copyWith().hashCode);
      final duplicates = [token, token.copyWith()];
      expect(duplicates.toSet().length, 1);
    });

    test('toString names owner, index, colour and steps', () {
      const token = Token(
        playerIndex: 0,
        index: 2,
        colour: PlayerColour.red,
        stepsTaken: 7,
      );
      expect(token.toString(), 'Token(p0:2 red steps=7)');
    });
  });

  group('Move and TokenRef', () {
    test('tokenRef converts a move to its token reference', () {
      const move = Move(playerIndex: 1, tokenIndex: 2);
      expect(move.tokenRef, const TokenRef(1, 2));
      expect(move.tokenRef.playerIndex, 1);
      expect(move.tokenRef.tokenIndex, 2);
    });

    test('Move equality is by player and token', () {
      const move = Move(playerIndex: 1, tokenIndex: 2);
      expect(move, const Move(playerIndex: 1, tokenIndex: 2));
      expect(move, isNot(const Move(playerIndex: 0, tokenIndex: 2)));
      expect(move, isNot(const Move(playerIndex: 1, tokenIndex: 3)));
      expect(move == Object(), isFalse);
      expect(move.hashCode, const Move(playerIndex: 1, tokenIndex: 2).hashCode);
      final duplicates = [move, const Move(playerIndex: 1, tokenIndex: 2)];
      expect(duplicates.toSet().length, 1);
    });

    test('TokenRef equality is by player and token', () {
      const ref = TokenRef(1, 2);
      expect(ref, const TokenRef(1, 2));
      expect(ref, isNot(const TokenRef(0, 2)));
      expect(ref, isNot(const TokenRef(1, 3)));
      expect(ref == Object(), isFalse);
      expect(ref.hashCode, const TokenRef(1, 2).hashCode);
      final duplicates = [ref, const TokenRef(1, 2)];
      expect(duplicates.toSet().length, 1);
    });

    test('toString names the player and token', () {
      expect(
        const Move(playerIndex: 1, tokenIndex: 2).toString(),
        'Move(p1:2)',
      );
      expect(const TokenRef(1, 2).toString(), 'TokenRef(p1:2)');
    });
  });

  group('MoveResult', () {
    test('defaults are no capture, no home, no extra turn, no winner', () {
      const result = MoveResult(
        move: Move(playerIndex: 0, tokenIndex: 1),
        fromSteps: 3,
        toSteps: 4,
      );
      expect(result.captured, isEmpty);
      expect(result.enteredHomePath, isFalse);
      expect(result.reachedHome, isFalse);
      expect(result.extraTurn, isFalse);
      expect(result.winnerIndex, isNull);
      expect(result.isWinningMove, isFalse);
      expect(
        result.toString(),
        'MoveResult(Move(p0:1) 3->4 captured=[] extraTurn=false winner=null)',
      );
    });

    test('a winning move reports isWinningMove and its exact string', () {
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
      expect(result.winnerIndex, 0);
      expect(result.reachedHome, isTrue);
      expect(result.extraTurn, isFalse);
      expect(
        result.toString(),
        'MoveResult(Move(p0:3) 54->56 captured=[] extraTurn=false winner=0)',
      );
    });

    test('a home (non-winning) move reports its exact string', () {
      final game = gameWith(
        tokenSteps: const [
          [54, 0, 0, 0],
          [0, 0, 0, 0],
        ],
        lastRoll: 2,
        phase: TurnPhase.awaitingMove,
      );
      final result = game.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(result.isWinningMove, isFalse);
      expect(result.reachedHome, isTrue);
      expect(result.extraTurn, isTrue); // reaching home grants a roll
      expect(
        result.toString(),
        'MoveResult(Move(p0:0) 54->56 captured=[] extraTurn=true winner=null)',
      );
    });
  });

  group('Player', () {
    test('a player must own exactly 4 tokens', () {
      expect(
        () => Player(
          index: 0,
          name: 'Red',
          colour: PlayerColour.red,
          type: PlayerType.human,
          tokens: List<Token>.generate(
            3,
            (i) => Token(playerIndex: 0, index: i, colour: PlayerColour.red),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('a fresh player has 4 yard tokens, isHuman, and no wins', () {
      final player = Player(
        index: 0,
        name: 'Red',
        colour: PlayerColour.red,
        type: PlayerType.human,
      );
      expect(player.tokens.length, 4);
      expect(player.tokens.every((t) => t.isInYard), isTrue);
      expect(player.isHuman, isTrue);
      expect(player.isAi, isFalse);
      expect(player.tokensHome, 0);
      expect(player.hasWon, isFalse);
    });

    test('tokensHome counts home tokens and hasWon needs all four', () {
      Player withSteps(List<int> steps) => Player(
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
            stepsTaken: steps[i],
          ),
        ),
      );
      expect(withSteps([56, 56, 0, 0]).tokensHome, 2);
      expect(withSteps([56, 56, 0, 0]).hasWon, isFalse);
      expect(withSteps([56, 56, 56, 56]).tokensHome, 4);
      expect(withSteps([56, 56, 56, 56]).hasWon, isTrue);
    });

    test('copyWith with no arguments preserves the player', () {
      final player = Player(
        index: 0,
        name: 'Red',
        colour: PlayerColour.red,
        type: PlayerType.human,
      );
      final copy = player.copyWith();
      expect(copy.index, 0);
      expect(copy.name, 'Red');
      expect(copy.colour, PlayerColour.red);
      expect(copy.type, PlayerType.human);
      expect(copy.tokens.map((t) => t.stepsTaken).toList(), [0, 0, 0, 0]);
    });

    test('copyWith replaces only the tokens', () {
      final player = Player(
        index: 0,
        name: 'Red',
        colour: PlayerColour.red,
        type: PlayerType.human,
      );
      final moved = List<Token>.generate(
        4,
        (i) => Token(
          playerIndex: 0,
          index: i,
          colour: PlayerColour.red,
          stepsTaken: i == 0 ? 5 : 0,
        ),
      );
      final copy = player.copyWith(tokens: moved);
      expect(copy.tokens[0].stepsTaken, 5);
      expect(copy.name, 'Red');
      expect(player.tokens[0].stepsTaken, 0); // the original is untouched
    });

    test('toJson names the seat and its four tokens', () {
      final player = Player(
        index: 0,
        name: 'Red',
        colour: PlayerColour.red,
        type: PlayerType.human,
      );
      final json = player.toJson();
      expect(json['name'], 'Red');
      expect(json['colour'], 'red');
      expect(json['type'], 'human');
      expect((json['tokens'] as List).length, 4);
      expect((json['tokens'] as List).first, {'stepsTaken': 0});
    });
  });

  group('AiPlayer.copyWith', () {
    test('copyWith with no arguments preserves difficulty and tokens', () {
      final ai = AiPlayer(
        index: 1,
        name: 'Green',
        colour: PlayerColour.green,
        difficulty: AiDifficulty.hard,
      );
      final copy = ai.copyWith();
      expect(copy, isA<AiPlayer>());
      expect(copy.difficulty, AiDifficulty.hard);
      expect(copy.name, 'Green');
      expect(copy.colour, PlayerColour.green);
      expect(copy.type, PlayerType.ai);
      expect(copy.tokens.map((t) => t.stepsTaken).toList(), [0, 0, 0, 0]);
    });

    test('copyWith can change the difficulty and the tokens', () {
      final ai = AiPlayer(
        index: 1,
        name: 'Green',
        colour: PlayerColour.green,
        difficulty: AiDifficulty.medium,
      );
      final easier = ai.copyWith(difficulty: AiDifficulty.easy);
      expect(easier.difficulty, AiDifficulty.easy);
      expect(easier.name, 'Green');
      final moved = List<Token>.generate(
        4,
        (i) => Token(
          playerIndex: 1,
          index: i,
          colour: PlayerColour.green,
          stepsTaken: i == 0 ? 5 : 0,
        ),
      );
      final movedAi = ai.copyWith(tokens: moved);
      expect(movedAi.tokens[0].stepsTaken, 5);
      expect(movedAi.difficulty, AiDifficulty.medium);
      expect(ai.tokens[0].stepsTaken, 0);
    });
  });

  group('InvalidMatchConfig', () {
    test('toString names the type and the message', () {
      expect(
        const InvalidMatchConfig('A match needs 2–4 players (FR-13).')
            .toString(),
        'InvalidMatchConfig: A match needs 2–4 players (FR-13).',
      );
    });
  });
}
