import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/domain/ai/ai_player.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/engine/move.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/offline_game_controller.dart';
import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:diceup/domain/usecases/match_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import 'engine/test_helpers.dart';
import 'repositories/fakes/fakes.dart';

/// A [Timer] the test drives by hand: one-shot callbacks fire via
/// [fire], periodic callbacks via [tick]. The factory records every
/// scheduled delay so the tests assert the AI pacing BOUNDS
/// (700–1,199 ms, FR-40/D-31) without waiting wall-clock.
class _ManualTimer implements Timer {
  _ManualTimer.oneShot(this._callback) : _periodicCallback = null;

  _ManualTimer.periodic(this._periodicCallback) : _callback = null;

  final void Function()? _callback;
  final void Function(Timer)? _periodicCallback;
  bool _cancelled = false;
  bool _fired = false;
  int _ticks = 0;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => _ticks;

  bool get isPending => !_cancelled && !_fired;

  void fire() {
    if (_cancelled || _fired) return;
    _fired = true;
    _callback?.call();
  }

  void tickOnce() {
    if (_cancelled) return;
    _ticks++;
    _periodicCallback?.call(this);
  }
}

/// Manual time for the controller: records every scheduled delay and
/// lets the test fire timers exactly when it chooses.
class _ManualTimers {
  final List<Duration> oneShotDelays = [];
  final List<Duration> periodicDelays = [];
  final List<_ManualTimer> oneShots = [];
  final List<_ManualTimer> periodics = [];

  Timer oneShot(Duration duration, void Function() callback) {
    oneShotDelays.add(duration);
    final timer = _ManualTimer.oneShot(callback);
    oneShots.add(timer);
    return timer;
  }

  Timer periodic(Duration duration, void Function(Timer) callback) {
    periodicDelays.add(duration);
    final timer = _ManualTimer.periodic(callback);
    periodics.add(timer);
    return timer;
  }

  /// Fires pending one-shot timers until none remain (a callback may
  /// schedule the next one). Capped so a scheduling loop fails the
  /// test instead of hanging it.
  void fireOneShots() {
    var guard = 0;
    while (oneShots.any((t) => t.isPending)) {
      assert(++guard <= 100, 'one-shot timers keep rescheduling');
      oneShots.firstWhere((t) => t.isPending).fire();
    }
  }

  /// Advances every live periodic timer by [times] ticks.
  void tickPeriodics({int times = 1}) {
    for (var i = 0; i < times; i++) {
      for (final timer in List.of(periodics)) {
        timer.tickOnce();
      }
    }
  }
}

/// The fixed clock for the controller under test: `stateWith` stamps
/// `startedAt` at 2026-11-21 12:00 UTC, so a completion recorded at
/// this time has a duration of exactly 90 seconds.
DateTime _fixedNow() => DateTime.utc(2026, 11, 21, 12, 1, 30);

/// A match one move from a win: seat 0 has three tokens home and the
/// fourth one step away, with a 1 outstanding.
GameState _nearWinState() => stateWith(
  tokenSteps: const [
    [56, 56, 56, 55],
    [0, 0, 0, 0],
  ],
  current: 0,
  lastRoll: 1,
  phase: TurnPhase.awaitingMove,
);

void main() {
  group('OfflineGameController', () {
    late InMemoryStore store;
    late InMemoryLocalMatchRepository matches;
    late InMemorySnapshotRepository snapshots;
    late InMemorySettingsRepository settings;
    late SnapshotSaver writer;
    late _ManualTimers timers;
    late int moveVibrations;
    late int notifications;

    OfflineGameController makeController({
      DiceRoller? diceRoller,
      bool? vibrationEnabled,
      bool includeWriter = true,
      bool includeRepositories = true,
    }) {
      final controller = OfflineGameController(
        diceRoller: diceRoller,
        matches: includeRepositories ? matches : null,
        settings: includeRepositories ? settings : null,
        snapshots: includeRepositories ? snapshots : null,
        snapshotWriter: includeWriter ? writer : null,
        vibrationEnabled: vibrationEnabled,
        now: _fixedNow,
        random: Random(42),
        oneShotTimer: timers.oneShot,
        periodicTimer: timers.periodic,
        onMoveApplied: () => moveVibrations++,
      );
      controller.addListener(() => notifications++);
      return controller;
    }

    setUp(() {
      store = InMemoryStore();
      matches = InMemoryLocalMatchRepository(store);
      snapshots = InMemorySnapshotRepository(store);
      settings = InMemorySettingsRepository(store);
      writer = SnapshotSaver(snapshots);
      timers = _ManualTimers();
      moveVibrations = 0;
      notifications = 0;
    });

    const twoPlayerVsAi = MatchSetup(
      playerCount: 2,
      aiSeats: {1: AiDifficulty.easy},
    );
    const twoPlayerLocal = MatchSetup(playerCount: 2, aiSeats: {});

    /// Rolls and settles (6 x 90 ms tumble) in one step.
    void settleRoll() => timers.tickPeriodics(times: 6);

    /// Fires pending AI timers and lets the awaited move
    /// continuations land: an AI move's status update follows the
    /// move's persistence await (one microtask after the engine
    /// apply), so the test drains before asserting on it.
    Future<void> fireAiStep() async {
      timers.fireOneShots();
      await Future<void>.delayed(Duration.zero);
    }

    test('starts a match: initial state, status, no legal moves', () {
      final controller = makeController();
      controller.startMatch(twoPlayerVsAi);

      expect(controller.state.phase, TurnPhase.awaitingRoll);
      expect(controller.state.currentPlayerIndex, 0);
      expect(controller.status, 'Player 1, roll the dice to start.');
      expect(controller.legalMoves, isEmpty);
      expect(controller.displayedRoll, isNull);
      expect(controller.rolling, isFalse);
      expect(controller.isFinished, isFalse);
      expect(controller.winner, isNull);
      expect(controller.currentSetup, twoPlayerVsAi);
      expect(notifications, greaterThan(0));
      controller.dispose();
    });

    test('noteIllegalTap (M2.8): status only — no roll, no move, '
        'no turn change, no vibration', () {
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
      );
      controller.startMatch(twoPlayerLocal);
      controller.rollDice();
      settleRoll();
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      final before = notifications;

      controller.noteIllegalTap("That token can't move now");
      expect(controller.status, "That token can't move now");
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(controller.state.moveCount, 0);
      expect(controller.state.currentPlayerIndex, 0);
      expect(controller.state.phase, TurnPhase.awaitingMove);
      expect(controller.rolling, isFalse);
      expect(moveVibrations, 0);
      expect(notifications, before + 1);

      // The next real action overwrites the notice as usual.
      controller.dispose();
    });

    test('startMatch with an invalid setup throws the engine error', () {
      final controller = makeController();
      expect(
        () => controller.startMatch(
          const MatchSetup(playerCount: 1, aiSeats: {}),
        ),
        throwsA(isA<InvalidMatchConfig>()),
      );
      controller.dispose();
    });

    test('scripted human-vs-AI game: exact state/status/legal-move '
        'sequence', () async {
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6, 1, 6, 3], cycle: true),
      );
      controller.startMatch(twoPlayerVsAi);

      // P1 rolls 6.
      controller.rollDice();
      expect(controller.rolling, isTrue);
      expect(controller.status, 'Rolling…');
      expect(controller.displayedRoll, isNull);
      settleRoll();
      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(controller.status, 'Player 1, choose a token to move.');

      // P1 releases token 0: a six grants an extra roll.
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(controller.state.players[0].tokens[0].stepsTaken, 1);
      expect(controller.state.moveCount, 1);
      expect(controller.state.currentPlayerIndex, 0);
      expect(controller.status, 'Six! Player 1 rolls again.');
      expect(controller.legalMoves, isEmpty);

      // P1 rolls 1: exactly one legal move (token 0: step 1 -> 2).
      controller.rollDice();
      settleRoll();
      expect(controller.displayedRoll, 1);
      expect(controller.legalMoves, [
        const Move(playerIndex: 0, tokenIndex: 0),
      ]);
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(controller.state.players[0].tokens[0].stepsTaken, 2);
      expect(controller.state.currentPlayerIndex, 1);
      expect(controller.status, 'Player 2, roll the dice.');

      // AI pacing (FR-40, D-31): the scheduled delay is in bounds,
      // and the AI has not acted before its timer fires.
      expect(timers.oneShotDelays, hasLength(1));
      final aiDelay = timers.oneShotDelays.single;
      expect(aiDelay.inMilliseconds, greaterThanOrEqualTo(700));
      expect(aiDelay.inMilliseconds, lessThanOrEqualTo(1199));
      expect(controller.state.currentPlayerIndex, 1);

      // The AI rolls 6 and releases a token, then rolls 3 and moves.
      timers.fireOneShots();
      expect(controller.rolling, isTrue);
      settleRoll();
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(controller.status, 'Green (AI) rolled 6, choose a token to move.');
      await fireAiStep();
      expect(controller.status, 'Green (AI) rolled a six and rolls again.');
      expect(controller.state.currentPlayerIndex, 1);
      timers.fireOneShots();
      settleRoll();
      expect(controller.displayedRoll, 3);
      expect(controller.legalMoves, hasLength(1));
      await fireAiStep();
      expect(
        controller.status,
        'Green (AI) moved a token. Player 1, roll the dice.',
      );
      expect(controller.state.currentPlayerIndex, 0);

      // Every AI delay scheduled so far is in the 700–1,199 ms band,
      // and every dice tumble is 6 x 90 ms.
      expect(
        timers.oneShotDelays.every(
          (d) => d.inMilliseconds >= 700 && d.inMilliseconds <= 1199,
        ),
        isTrue,
      );
      expect(
        timers.periodicDelays.every(
          (d) => d == const Duration(milliseconds: 90),
        ),
        isTrue,
      );

      // P1 rolls again (sequence cycles to 6) and moves token 0.
      controller.rollDice();
      settleRoll();
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(controller.state.players[0].tokens[0].stepsTaken, 8);
      expect(controller.status, 'Six! Player 1 rolls again.');

      // Five completed moves vibrated once each (3 human + 2 AI).
      expect(moveVibrations, 5);
      controller.dispose();
    });

    test('capture: the status names the capture and the token returns '
        'to the yard', () async {
      // Red token 0 on step 10 (track 9); green token 0 on step 3
      // (track 15, not a safe cell). A roll of 6 lands red on 16
      // (track 15) and captures it.
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
      );
      controller.restoreMatch(
        stateWith(
          tokenSteps: const [
            [10, 0, 0, 0],
            [3, 0, 0, 0],
          ],
          current: 0,
          lastRoll: 6,
          phase: TurnPhase.awaitingMove,
        ),
      );
      expect(controller.displayedRoll, 6);
      expect(controller.status, 'Player 1, choose a token to move.');

      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(controller.state.players[0].tokens[0].stepsTaken, 16);
      expect(controller.state.players[1].tokens[0].stepsTaken, 0);
      expect(controller.status, 'Captured! 1 token(s) sent home.');
      controller.dispose();
    });

    test('reaching home grants another roll', () async {
      final controller = makeController();
      controller.restoreMatch(
        stateWith(
          tokenSteps: const [
            [55, 0, 0, 0],
            [0, 0, 0, 0],
          ],
          current: 0,
          lastRoll: 1,
          phase: TurnPhase.awaitingMove,
        ),
      );
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(controller.state.players[0].tokens[0].stepsTaken, 56);
      expect(controller.status, 'Token home! Player 1 rolls again.');
      expect(controller.state.currentPlayerIndex, 0);
      expect(controller.state.phase, TurnPhase.awaitingRoll);
      controller.dispose();
    });

    test('settled roll and completed move are both snapshotted', () async {
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
      );
      controller.startMatch(twoPlayerLocal);

      controller.rollDice();
      settleRoll();
      await writer.flush;
      var saved = await snapshots.loadSnapshot(kCurrentMatchKey);
      var json = jsonDecode(saved!.snapshotJson) as Map<String, Object?>;
      expect(json['lastRoll'], 6);
      expect(json['phase'], 'awaitingMove');
      expect(json['moveCount'], 0);

      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      await writer.flush;
      saved = await snapshots.loadSnapshot(kCurrentMatchKey);
      json = jsonDecode(saved!.snapshotJson) as Map<String, Object?>;
      expect(json['moveCount'], 1);
      expect(json['phase'], 'awaitingRoll');
      expect(json['lastRoll'], 0);
      controller.dispose();
    });

    test('resume restores the exact state incl. AI difficulty', () async {
      // A live match: human rolled a 6 against a hard AI.
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
        diceRoller: FixedDiceRoller(const [6]),
      );
      game.rollDice();
      final resumedState = game.state;

      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
      );
      controller.restoreMatch(resumedState);
      expect(controller.displayedRoll, 6);
      expect(controller.legalMoves, hasLength(4));
      expect(controller.status, 'Player 1, choose a token to move.');
      // The resumed setup keeps the restored AI difficulty for
      // Play Again — it is never reset to easy.
      expect(controller.currentSetup!.aiSeats, {1: AiDifficulty.hard});

      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      await writer.flush;
      final saved = await snapshots.loadSnapshot(kCurrentMatchKey);
      final json = jsonDecode(saved!.snapshotJson) as Map<String, Object?>;
      expect(json['moveCount'], 1);
      expect(json['currentPlayerIndex'], 0);
      expect(json['phase'], 'awaitingRoll');
      final players = json['players'] as List;
      expect((players[1] as Map<String, Object?>)['difficulty'], 'hard');
      expect((players[1] as Map<String, Object?>)['type'], 'ai');
      controller.dispose();
    });

    test(
      'a full match records exactly once and deletes the snapshot',
      () async {
        final controller = makeController(
          diceRoller: FixedDiceRoller(const [6, 6, 1], cycle: true),
        );
        controller.startMatch(twoPlayerVsAi);

        // Drive the whole match headlessly: human rolls/moves, AI
        // steps fire on the manual timers. The 6/6/1 cycle always
        // leaves a 1 to inch a token home under exact finish. The
        // microtask drain each iteration lets an awaited move's
        // continuation (which schedules the next AI timer) run before
        // the next step looks for it.
        var guard = 0;
        while (!controller.isFinished && guard++ < 2000) {
          await Future<void>.delayed(Duration.zero);
          final phase = controller.state.phase;
          if (phase == TurnPhase.awaitingRoll) {
            if (controller.state.currentPlayer.isAi) {
              timers.fireOneShots();
            } else {
              controller.rollDice();
            }
            settleRoll();
          } else if (phase == TurnPhase.awaitingMove) {
            if (controller.state.currentPlayer.isAi) {
              timers.fireOneShots();
            } else {
              await controller.applyMove(controller.legalMoves.first);
            }
          }
        }
        expect(controller.isFinished, isTrue, reason: 'guard: $guard');
        expect(controller.winner, isNotNull);
        expect(controller.completionFailed, isFalse);
        expect(controller.completionPending, isFalse);
        await writer.flush;
        expect(await matches.countMatches(), 1);
        final recorded = (await matches.listMatches()).single;
        expect(recorded.winnerName, controller.winner!.name);
        // The match started at the real wall-clock time while the
        // record uses the fixed test clock, so only the shape is
        // asserted here — the exact 90-second duration is pinned in
        // the ApplyMove tests, where `startedAt` is fixed.
        expect(recorded.durationSeconds, isNotNull);
        expect(recorded.durationSeconds, greaterThanOrEqualTo(0));
        expect(recorded.mode, LocalMatchMode.vsAi);
        expect(await snapshots.hasSnapshot(kCurrentMatchKey), isFalse);

        // Restarting starts a fresh match without recording again.
        await controller.restart();
        expect(await matches.countMatches(), 1);
        expect(controller.isFinished, isFalse);
        expect(controller.status, 'Player 1, roll the dice to start.');
        controller.dispose();
      },
    );

    test('a queued roll-save never resurrects a match completed by '
        'the next move', () async {
      // One move from a win, with a roll pending first: the roll
      // settle queues a snapshot save, and the winning move that
      // follows must invalidate it before the record deletes the row.
      final controller = makeController(diceRoller: FixedDiceRoller(const [1]));
      controller.restoreMatch(
        stateWith(
          tokenSteps: const [
            [56, 56, 56, 55],
            [0, 0, 0, 0],
          ],
          current: 0,
          lastRoll: 0,
          phase: TurnPhase.awaitingRoll,
        ),
      );
      controller.rollDice();
      settleRoll();
      // No await between the settle and the move: the queued save
      // has not landed yet when the completing move invalidates it.
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 3));
      expect(controller.isFinished, isTrue);
      expect(controller.completionFailed, isFalse);
      await writer.flush;
      expect(await matches.countMatches(), 1);
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      controller.dispose();
    });

    test('completion failure is reported, the snapshot stays, and '
        'resume retries the record exactly once', () async {
      final controller = makeController(diceRoller: FixedDiceRoller(const [1]));
      final nearWin = _nearWinState();
      writer.save(nearWin);
      await writer.flush;
      controller.restoreMatch(nearWin);

      store.failNextCall();
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 3));
      expect(controller.isFinished, isTrue);
      expect(controller.completionFailed, isTrue);
      expect(await matches.countMatches(), 0);
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isTrue);

      // Resume the finished match: the record is retried on the
      // turn-change path and succeeds exactly once in total.
      final finishedState = controller.state;
      controller.dispose();
      final retry = makeController(diceRoller: FixedDiceRoller(const [1]));
      retry.restoreMatch(finishedState);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(retry.completionFailed, isFalse);
      expect(retry.completionPending, isFalse);
      expect(await matches.countMatches(), 1);
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      retry.dispose();
    });

    test('clean exit discards the snapshot and records nothing', () async {
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
      );
      controller.startMatch(twoPlayerLocal);
      controller.rollDice();
      settleRoll();
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      await writer.flush;
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isTrue);

      await controller.discardSnapshot();
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      expect(await matches.countMatches(), 0);
      controller.dispose();
    });

    test('restart discards the snapshot and records nothing', () async {
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
      );
      controller.startMatch(twoPlayerLocal);
      controller.rollDice();
      settleRoll();
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      await writer.flush;
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isTrue);

      await controller.restart();
      expect(await snapshots.hasSnapshot(kCurrentMatchKey), isFalse);
      expect(await matches.countMatches(), 0);
      expect(controller.isFinished, isFalse);
      expect(controller.status, 'Player 1, roll the dice to start.');
      controller.dispose();
    });

    test('vibration gate: a move vibrates when enabled, not when '
        'disabled', () async {
      final enabled = makeController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
        vibrationEnabled: true,
      );
      enabled.startMatch(twoPlayerLocal);
      enabled.rollDice();
      settleRoll();
      await enabled.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(moveVibrations, 1);
      enabled.dispose();

      moveVibrations = 0;
      final disabled = makeController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
        vibrationEnabled: false,
      );
      disabled.startMatch(twoPlayerLocal);
      disabled.rollDice();
      settleRoll();
      await disabled.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(moveVibrations, 0);
      disabled.dispose();
    });

    test('vibration flag refreshes from the persisted setting', () async {
      await settings.setSetting('vibration_enabled', '0');
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [6], cycle: true),
      );
      controller.startMatch(twoPlayerLocal);
      // Let the async settings read land.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      controller.rollDice();
      settleRoll();
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 0));
      expect(moveVibrations, 0);
      controller.dispose();
    });

    test('rollDice is ignored while rolling, when a move is pending, '
        'and when finished', () async {
      final controller = makeController(diceRoller: FixedDiceRoller(const [6]));
      controller.startMatch(twoPlayerLocal);
      controller.rollDice();
      // A second roll mid-tumble is ignored (no second engine roll:
      // the one-shot fixed roller would throw if consumed twice).
      controller.rollDice();
      expect(controller.rolling, isTrue);
      settleRoll();
      expect(controller.displayedRoll, 6);
      // A roll while a move is pending is ignored.
      controller.rollDice();
      expect(controller.rolling, isFalse);
      expect(controller.displayedRoll, 6);
      controller.dispose();
    });

    test('degraded play without repositories stays playable and '
        'reports the failed record', () async {
      final controller = makeController(
        diceRoller: FixedDiceRoller(const [1]),
        includeRepositories: false,
        includeWriter: false,
      );
      controller.restoreMatch(_nearWinState());
      await controller.applyMove(const Move(playerIndex: 0, tokenIndex: 3));
      expect(controller.isFinished, isTrue);
      expect(controller.winner!.name, 'Player 1');
      expect(controller.completionFailed, isTrue);
      controller.dispose();
    });
  });
}
