import 'dart:convert';
import 'dart:developer';
import 'dart:math' show max;

import '../ai/ai_player.dart';
import '../engine/game_state.dart';
import '../engine/ludo_game.dart';
import '../engine/move.dart';
import '../repositories/local_match_repository.dart';
import '../repositories/snapshot_repository.dart';
import '../snapshot_writer.dart';

/// The outcome of applying one move.
///
/// [completionRecorded] is true only when this call recorded the
/// completed match. [completionFailed] is true when the match
/// finished but recording failed — the move still stands and the
/// match stays finished; the caller reports the failure (the win
/// dialog's "couldn't be saved to your history" notice in the game
/// screen today) and recording is retried when the finished match
/// is resumed.
class AppliedMove {
  const AppliedMove({
    required this.result,
    required this.state,
    required this.completionRecorded,
    this.completionFailed = false,
  });

  /// What the engine reports about the move (captures, extra turn,
  /// winner) — the caller animates exactly this, never re-derives it.
  final MoveResult result;

  /// The match state immediately after the move.
  final GameState state;

  /// True when this call recorded the completed match.
  final bool completionRecorded;

  /// True when the match finished but recording failed.
  final bool completionFailed;
}

/// Applies one move and owns its persistence side effects (M3.1,
/// SDD §3.2, FR-17/FR-29/FR-30).
///
/// Behaviour mirrors the game screen's `_applyMove` +
/// `_recordCompletionAndShowDialog` exactly, moved into one place so
/// snapshot-after-every-move and completion recording are
/// enforceable together:
///
/// 1. The engine validates first ([LudoGame.applyMove] throws
///    [StateError] when no move is pending or the match is finished,
///    [ArgumentError] when the move is not legal) — on failure the
///    state is unchanged and nothing is persisted.
/// 2. A non-finishing move saves the post-move snapshot under
///    [kCurrentMatchKey] (FR-29). A snapshot failure never breaks
///    the move: it is logged and the move still succeeds, exactly as
///    the `SnapshotSaver` behaves today — the next save retries.
/// 3. A finishing move records the match exactly once via
///    [LocalMatchRepository.recordMatch] (one transaction: match row
///    + statistics + prune + snapshot delete, FR-30) and saves no
///    snapshot — a finished match is never snapshotted.
///
/// Duplicate-completion protection lives here, not in the widget:
/// the record runs only when the engine state transitions to
/// finished on a game this instance has not already recorded, and
/// the flag is set synchronously before the first await, so a second
/// completion callback cannot start a second record. The flag is
/// keyed by game instance: a fresh match (Play Again) through the
/// same instance records normally.
///
/// Two seams stay with the caller (M3.2 controller) — both resolved
/// there (M3.2):
/// * A move is never applied to an already-finished game — the
///   engine throws — so a *resumed* finished match (record failed
///   earlier, retry on resume) is still recorded by the controller's
///   turn-change path, as the screen does today; this use case only
///   records the transition it performs.
/// * The snapshot queue: when a [SnapshotWriter] is supplied, move
///   snapshots are routed through it (fire-and-forget, ordered with
///   the caller's roll saves on the same queue) and it is invalidated
///   before the completion record, so no stale roll-save can land
///   after the record's snapshot delete. Without a writer the direct
///   awaited repository write is used instead (the M3.1 behaviour,
///   kept for use-case tests and degraded play).
class ApplyMove {
  ApplyMove({
    required LocalMatchRepository matches,
    required SnapshotRepository snapshots,
    SnapshotWriter? snapshotWriter,
    DateTime Function()? now,
  }) : _matchRepository = matches,
       _snapshotRepository = snapshots,
       _writer = snapshotWriter,
       _now = now ?? DateTime.now;

  final LocalMatchRepository _matchRepository;
  final SnapshotRepository _snapshotRepository;
  final SnapshotWriter? _writer;

  /// Clock for `playedAt` / `createdAt` / `savedAt` and the duration
  /// computation. Defaults to [DateTime.now]; tests pass a fixed
  /// clock for exact durations.
  final DateTime Function() _now;

  /// The game whose completion this instance already recorded, if
  /// any — see the class doc: completion is recorded once per game,
  /// not once per instance.
  LudoGame? _completedGame;
  bool _completionRecorded = false;

  Future<AppliedMove> call(LudoGame game, Move move) async {
    final result = game.applyMove(move);
    if (!game.isFinished) {
      await _saveSnapshot(game.state);
      return AppliedMove(
        result: result,
        state: game.state,
        completionRecorded: false,
      );
    }
    if (_completionRecorded && identical(game, _completedGame)) {
      // Defence-in-depth: the engine already forbids a second
      // finishing transition on the same game object (a finished
      // match throws on apply), so this arm is unreachable through
      // the engine — but the exactly-once contract must not depend
      // on the caller never asking twice.
      return AppliedMove(
        result: result,
        state: game.state,
        completionRecorded: false,
      );
    }
    // Set synchronously before the first await, so a second
    // completion callback cannot start a second record — the same
    // guard the game screen's `_completionRecorded` flag provides.
    // It stays set even when the record fails: this instance never
    // records the same game twice, and the retry happens on resume
    // (a new game object), exactly as the screen retries a failed
    // record when the finished match is resumed.
    _completionRecorded = true;
    _completedGame = game;
    // No stale snapshot write may land after the record deletes the
    // row in its transaction (M3.2, seam 3).
    _writer?.invalidate();
    try {
      await _matchRepository.recordMatch(buildLocalMatch(game, _now()));
      return AppliedMove(
        result: result,
        state: game.state,
        completionRecorded: true,
      );
    } catch (error) {
      log('DiceUp match recording failed ($error)', name: 'DiceUpApplyMove');
      // The move stands and the match stays finished: only the
      // record failed. No snapshot is saved for a finished match,
      // and the last pre-finish snapshot is left in place, so the
      // finished match stays resumable and recording is retried on
      // resume. The caller reports the failure.
      return AppliedMove(
        result: result,
        state: game.state,
        completionRecorded: false,
        completionFailed: true,
      );
    }
  }

  /// Saves the post-move snapshot (FR-29). With a [SnapshotWriter]
  /// the save is queued on the shared ordered queue (fire-and-forget,
  /// exactly as the game screen queued it before M3.2); without one
  /// the repository is written directly and awaited. Either way it
  /// never throws: a storage failure must never wedge a move — the
  /// save is logged and the next move's save retries, exactly as the
  /// `SnapshotSaver` behaves today.
  Future<void> _saveSnapshot(GameState state) async {
    final writer = _writer;
    if (writer != null) {
      writer.save(state);
      return;
    }
    try {
      await _snapshotRepository.saveSnapshot(
        SavedSnapshot(
          matchKey: kCurrentMatchKey,
          snapshotJson: jsonEncode(state.toJson()),
          savedAt: _now(),
        ),
      );
    } catch (error) {
      log(
        'DiceUp snapshot save failed ($error); the match stays '
        'playable and the next save is retried.',
        name: 'DiceUpApplyMove',
      );
    }
  }

  /// The completed match for the record (FR-30), built exactly as
  /// the game screen builds it: date, mode, players, winner and
  /// duration in one value. Mode is vs-AI when any seat is AI, else
  /// local multiplayer; duration comes from the state's
  /// [GameState.startedAt]; player difficulties come from the live
  /// [AiPlayer] seats, never the setup default.
  ///
  /// Public and static so the [OfflineGameController]'s resumed-
  /// finished retry records the identical row shape (M3.2, seam 4):
  /// both record paths share this one builder instead of drifting.
  static LocalMatch buildLocalMatch(LudoGame game, DateTime now) {
    final state = game.state;
    final winner = game.winner;
    final startedAt = state.startedAt;
    return LocalMatch(
      playedAt: now,
      mode: state.players.any((player) => player.isAi)
          ? LocalMatchMode.vsAi
          : LocalMatchMode.localMultiplayer,
      playerCount: state.players.length,
      players: [
        for (final player in state.players)
          LocalMatchPlayer(
            name: player.name,
            colour: player.colour,
            isAi: player.isAi,
            difficulty: player is AiPlayer ? player.difficulty : null,
          ),
      ],
      winnerIndex: game.winnerIndex,
      winnerName: winner?.name,
      durationSeconds: startedAt == null
          ? null
          : max(0, now.difference(startedAt).inSeconds),
      rulesetVersion: state.rulesetVersion,
      createdAt: now,
    );
  }
}
