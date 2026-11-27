import 'dart:convert';

import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/engine/move.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/engine/token.dart';
import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:diceup/domain/snapshot_writer.dart';
import 'package:diceup/domain/usecases/apply_move.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine/test_helpers.dart';
import '../repositories/fakes/fakes.dart';

/// The fixed clock for [ApplyMove]: `stateWith` stamps `startedAt`
/// at 2026-11-21 12:00 UTC, so a completion recorded at this time
/// has a duration of exactly 90 seconds.
DateTime _fixedNow() => DateTime.utc(2026, 11, 21, 12, 1, 30);

/// A game one legal move from finished: seat 0 has three tokens home
/// and one on step 55; a roll of 1 is outstanding.
LudoGame _nearFinishedGame() => gameWith(
  tokenSteps: const [
    [56, 56, 56, 55],
    [0, 0, 0, 0],
  ],
  current: 0,
  lastRoll: 1,
  phase: TurnPhase.awaitingMove,
);

/// As [_nearFinishedGame] but seat 1 is a hard AI ("CPU") and seat 0
/// is the human "Ana" — so the recorded match is vs-AI with a true
/// difficulty, not the setup default.
LudoGame _nearFinishedVsAiGame() {
  final human = Player(
    index: 0,
    name: 'Ana',
    colour: PlayerColour.red,
    type: PlayerType.human,
    tokens: List<Token>.generate(
      4,
      (i) => Token(
        playerIndex: 0,
        index: i,
        colour: PlayerColour.red,
        stepsTaken: i == 3 ? 55 : 56,
      ),
    ),
  );
  final ai = AiPlayer(
    index: 1,
    name: 'CPU',
    colour: PlayerColour.green,
    difficulty: AiDifficulty.hard,
    tokens: List<Token>.generate(
      4,
      (i) => Token(playerIndex: 1, index: i, colour: PlayerColour.green),
    ),
  );
  return LudoGame.fromState(
    GameState(
      players: [human, ai],
      currentPlayerIndex: 0,
      rulesetVersion: '1.0.0',
      startedAt: DateTime.utc(2026, 11, 21, 12, 0),
      phase: TurnPhase.awaitingMove,
      lastRoll: 1,
    ),
  );
}

void main() {
  group('ApplyMove', () {
    late InMemoryStore store;
    late InMemoryLocalMatchRepository matches;
    late InMemorySnapshotRepository snapshots;
    late ApplyMove applyMove;

    setUp(() {
      store = InMemoryStore();
      matches = InMemoryLocalMatchRepository(store);
      snapshots = InMemorySnapshotRepository(store);
      applyMove = ApplyMove(
        matches: matches,
        snapshots: snapshots,
        now: _fixedNow,
      );
    });

    test(
      'an illegal move is rejected, state unchanged, nothing stored',
      () async {
        final game = freshGame(const [6]);
        game.rollDice();
        final before = game.state.toJson();

        await expectLater(
          () => applyMove(game, const Move(playerIndex: 1, tokenIndex: 0)),
          throwsArgumentError,
        );
        expect(game.state.toJson(), before);
        expect(await matches.countMatches(), 0);
        expect(await snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      },
    );

    test('a legal move applies and the snapshot is saved', () async {
      final game = freshGame(const [6]);
      game.rollDice();

      final outcome = await applyMove(
        game,
        const Move(playerIndex: 0, tokenIndex: 0),
      );

      expect(outcome.result.fromSteps, 0);
      expect(outcome.result.toSteps, 1);
      expect(outcome.completionRecorded, isFalse);
      expect(outcome.completionFailed, isFalse);
      expect(game.state.players[0].tokens[0].stepsTaken, 1);
      expect(await matches.countMatches(), 0);
      final saved = await snapshots.loadSnapshot(kCurrentMatchKey);
      expect(saved, isNotNull);
      final restored = GameState.fromJson(
        jsonDecode(saved!.snapshotJson) as Map<String, Object?>,
      );
      expect(restored.players[0].tokens[0].stepsTaken, 1);
      expect(restored.moveCount, 1);
    });

    test('a completing move records the match exactly once and deletes '
        'the snapshot', () async {
      final game = _nearFinishedGame();
      await snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: jsonEncode(game.state.toJson()),
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );

      final outcome = await applyMove(
        game,
        const Move(playerIndex: 0, tokenIndex: 3),
      );

      expect(outcome.result.isWinningMove, isTrue);
      expect(outcome.completionRecorded, isTrue);
      expect(outcome.completionFailed, isFalse);
      expect(game.isFinished, isTrue);
      final recorded = await matches.listMatches();
      expect(recorded, hasLength(1));
      final match = recorded.first;
      expect(match.mode, LocalMatchMode.localMultiplayer);
      expect(match.playerCount, 2);
      expect(match.players[0].name, 'Player 1');
      expect(match.players[0].isAi, isFalse);
      expect(match.players[0].difficulty, isNull);
      expect(match.players[1].name, 'Player 2');
      expect(match.winnerIndex, 0);
      expect(match.winnerName, 'Player 1');
      expect(match.durationSeconds, 90);
      expect(match.playedAt, DateTime.utc(2026, 11, 21, 12, 1, 30));
      expect(match.rulesetVersion, '1.0.0');
      expect(store.statistics.matchesPlayed, 1);
      expect(store.statistics.matchesWon, 1);
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isFalse);

      // A second ApplyMove after completion records nothing.
      await expectLater(
        () => applyMove(game, const Move(playerIndex: 0, tokenIndex: 3)),
        throwsStateError,
      );
      expect(await matches.countMatches(), 1);
    });

    test(
      'a vs-AI completion records the mode and true AI difficulties',
      () async {
        final game = _nearFinishedVsAiGame();

        final outcome = await applyMove(
          game,
          const Move(playerIndex: 0, tokenIndex: 3),
        );

        expect(outcome.completionRecorded, isTrue);
        final match = (await matches.listMatches()).first;
        expect(match.mode, LocalMatchMode.vsAi);
        expect(match.players[0].name, 'Ana');
        expect(match.players[0].isAi, isFalse);
        expect(match.players[0].difficulty, isNull);
        expect(match.players[1].name, 'CPU');
        expect(match.players[1].isAi, isTrue);
        expect(match.players[1].difficulty, AiDifficulty.hard);
        expect(match.winnerIndex, 0);
        expect(match.winnerName, 'Ana');
        expect(match.durationSeconds, 90);
      },
    );

    test('the same instance records a second, different match', () async {
      final first = _nearFinishedGame();
      await applyMove(first, const Move(playerIndex: 0, tokenIndex: 3));
      expect(await matches.countMatches(), 1);

      final second = _nearFinishedGame();
      final outcome = await applyMove(
        second,
        const Move(playerIndex: 0, tokenIndex: 3),
      );

      expect(outcome.completionRecorded, isTrue);
      expect(await matches.countMatches(), 2);
    });

    test('a failed record leaves the move standing, the snapshot kept, '
        'and reports completionFailed', () async {
      final game = _nearFinishedGame();
      await snapshots.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: jsonEncode(game.state.toJson()),
          savedAt: DateTime.utc(2026, 11, 21, 12, 0),
        ),
      );
      store.failNextCall();

      final outcome = await applyMove(
        game,
        const Move(playerIndex: 0, tokenIndex: 3),
      );

      expect(outcome.completionRecorded, isFalse);
      expect(outcome.completionFailed, isTrue);
      expect(game.isFinished, isTrue);
      expect(await matches.countMatches(), 0);
      // The pre-finish snapshot is left in place, so the finished
      // match stays resumable and recording is retried on resume.
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isTrue);
    });

    test('a failed snapshot save never breaks the move', () async {
      final game = freshGame(const [6]);
      game.rollDice();
      store.failNextCall();

      final outcome = await applyMove(
        game,
        const Move(playerIndex: 0, tokenIndex: 0),
      );

      expect(outcome.result.toSteps, 1);
      expect(outcome.completionRecorded, isFalse);
      expect(game.state.players[0].tokens[0].stepsTaken, 1);
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
    });

    test('with a writer, move snapshots go through the queue and a '
        'finishing move invalidates it before recording', () async {
      final writer = _RecordingWriter();
      final queued = ApplyMove(
        matches: matches,
        snapshots: snapshots,
        snapshotWriter: writer,
        now: _fixedNow,
      );

      // A non-finishing move is queued on the writer — and only
      // there: the repository holds nothing yet.
      final game = freshGame(const [6]);
      game.rollDice();
      await queued(game, const Move(playerIndex: 0, tokenIndex: 0));
      expect(writer.savedStates, hasLength(1));
      expect(writer.savedStates.single.moveCount, 1);
      expect(writer.invalidations, 0);
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isFalse);

      // A finishing move invalidates the queue before the record,
      // so a save queued earlier cannot land after the delete.
      final finisher = _nearFinishedGame();
      await queued(finisher, const Move(playerIndex: 0, tokenIndex: 3));
      expect(writer.invalidations, 1);
      expect(writer.savedStates, hasLength(1));
      expect(await matches.countMatches(), 1);
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
    });
  });
}

/// A [SnapshotWriter] that records calls instead of writing, for the
/// M3.2 seam-3 tests: the use case must route move snapshots through
/// it and invalidate it before a completion record.
class _RecordingWriter implements SnapshotWriter {
  final List<GameState> savedStates = [];
  var invalidations = 0;
  var discards = 0;

  @override
  void save(GameState state) => savedStates.add(state);

  @override
  void invalidate() => invalidations++;

  @override
  Future<void> discard() async {
    discards++;
  }
}
