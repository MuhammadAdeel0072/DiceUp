import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' show Random;

import 'ai/ai_player.dart';
import 'engine/dice_roller.dart';
import 'engine/game_state.dart';
import 'engine/ludo_game.dart';
import 'engine/move.dart';
import 'engine/player.dart';
import 'repositories/local_match_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/snapshot_repository.dart';
import 'snapshot_writer.dart';
import 'usecases/apply_move.dart';
import 'usecases/match_setup.dart';
import 'usecases/roll_dice.dart';
import 'usecases/start_offline_match.dart';

/// Creates a one-shot timer. The controller takes these as injectable
/// factories (defaulting to the real [Timer] constructors) so tests
/// can drive time manually and assert the scheduled delays — the AI
/// pacing bounds (FR-40, D-31) are asserted as scheduled bounds,
/// never wall-clock.
typedef OneShotTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

/// Creates a periodic timer. Same testability story as
/// [OneShotTimerFactory]; the dice tumble is 6 x 90 ms.
typedef PeriodicTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

/// The offline match controller (M3.2, H-07; SDD §3.2).
///
/// Plain Dart — no Flutter, no framework binding (that is M3.3).
/// Extracted verbatim from `_GameScreenState`, which owned all of
/// this before: the engine, the AI players, the timers, the legal
/// moves, the status line, the win trigger, snapshot saving, exactly-
/// once completion recording and resume handling. Behaviour is
/// bit-identical at extraction: the same 700–1,199 ms AI pacing
/// (D-31), the same 6 x 90 ms dice tumble, the same status strings,
/// the same win trigger, the same snapshot-after-move/settled-roll
/// behaviour, the same exactly-once completion, the same
/// resume/discard handling. No behaviour change in the same commit
/// as the move — this is a pure move + wiring.
///
/// The controller drives the match through the M3.1 use cases
/// ([StartOfflineMatch], [RollDice], [ApplyMove]) — it never
/// re-implements their logic. What the use cases cannot own stays
/// here: the timers and pacing, the status strings, the AI
/// scheduler, the vibration gate, and the resumed-finished
/// completion retry (a move is never applied to an already-finished
/// game, so that retry lives in the turn-change path, as the screen
/// did it).
///
/// Naming (M3.2 plan text vs M1.2 as built): the plan says the
/// controller takes `LocalSettingsRepository`, but M1.2 built
/// [SettingsRepository] and the briefs forbid renaming it. This
/// controller takes [SettingsRepository] — the existing name wins.
///
/// Observation: the view registers with [addListener]/[removeListener]
/// (plain callbacks — no Flutter `Listenable`, so the domain stays
/// framework-free) and re-reads [state], [legalMoves],
/// [displayedRoll], [rolling], [status] and [isFinished] on every
/// notification. The controller notifies after every state change,
/// including after an async completion record settles, so the view
/// can navigate to the results screen only once recording is decided (see
/// [completionPending]).
///
/// Persistence is optional, exactly as the screen's was: when the
/// repositories are absent (degraded startup, bare widget tests) the
/// match stays playable, nothing is persisted, and a finished match
/// reports [completionFailed] so the results screen can say so. When a
/// [SnapshotWriter] is supplied, all snapshot writes (settled rolls
/// and moves) go through its single ordered queue, and it is
/// invalidated before any completion record (M3.2, seam 3).
///
/// One deliberate hardening, recorded here rather than smuggled in:
/// [startMatch]/[restoreMatch] cancel any live timers first. The
/// screen never did — a restart confirmed while an AI timer was
/// pending could let that timer act on the *new* match. No test
/// covers that race (no test restarts mid-turn); cancelling is the
/// only correct behaviour for a match that no longer exists.
/// [startOfflineMatch]/[rollDice]/[applyMove] are the M3.1 use
/// cases, constructor-injected by the M3.3 composition root
/// ([offlineGameControllerProvider]). Each defaults to the
/// instance the controller built internally before M3.3, so
/// direct construction (controller tests) behaves exactly as
/// before; only the provider path injects them.
class OfflineGameController {
  OfflineGameController({
    DiceRoller? diceRoller,
    LocalMatchRepository? matches,
    SettingsRepository? settings,
    SnapshotRepository? snapshots,
    SnapshotWriter? snapshotWriter,
    StartOfflineMatch? startOfflineMatch,
    RollDice? rollDice,
    ApplyMove? applyMove,
    bool? vibrationEnabled,
    this.vibrationRefreshEnabled = true,
    DateTime Function()? now,
    Random? random,
    OneShotTimerFactory? oneShotTimer,
    PeriodicTimerFactory? periodicTimer,
    this.onMoveApplied,
  }) : _vibrationEnabled = vibrationEnabled ?? true,
       _now = now ?? DateTime.now,
       _random = random ?? Random(),
       _oneShotTimer =
           oneShotTimer ?? ((duration, callback) => Timer(duration, callback)),
       _periodicTimer =
           periodicTimer ??
           ((duration, callback) => Timer.periodic(duration, callback)) {
    // Assigned in the body (not the initializer list) so the
    // constructor keeps its public parameter names: an initializing
    // formal cannot carry a private name, and a same-name assignment
    // in the initializer list trips `prefer_initializing_formals`.
    _diceRoller = diceRoller;
    _matches = matches;
    _settings = settings;
    _snapshots = snapshots;
    _snapshotWriter = snapshotWriter;
    _startMatch =
        startOfflineMatch ?? StartOfflineMatch(diceRoller: _diceRoller);
    _rollDice = rollDice ?? RollDice();
    _applyMove =
        applyMove ??
        (_matches != null && _snapshots != null
            ? ApplyMove(
                matches: _matches,
                snapshots: _snapshots,
                snapshotWriter: _snapshotWriter,
                now: _now,
              )
            : null);
  }

  late final DiceRoller? _diceRoller;
  late final LocalMatchRepository? _matches;
  late final SettingsRepository? _settings;
  late final SnapshotRepository? _snapshots;
  late final SnapshotWriter? _snapshotWriter;
  final DateTime Function() _now;
  final Random _random;
  final OneShotTimerFactory _oneShotTimer;
  final PeriodicTimerFactory _periodicTimer;

  /// Called once per completed move, after the vibration gate (see
  /// [_vibrateOnMove]). The view wires this to its [FeedbackService];
  /// the controller itself never touches haptics (presentation).
  final void Function()? onMoveApplied;

  /// Whether the persisted `vibration_enabled` setting is re-read
  /// after start. The view passes false when the test override
  /// ([GameScreen.vibrationEnabled]) is given, exactly as the screen
  /// skipped its refresh then; otherwise a toggle changed after
  /// startup is picked up.
  final bool vibrationRefreshEnabled;

  late final StartOfflineMatch _startMatch;
  late final RollDice _rollDice;
  late final ApplyMove? _applyMove;

  LudoGame? _game;
  final Map<int, AiPlayer> _aiPlayers = {};
  List<Move> _legalMoves = [];
  int? _displayedRoll;
  bool _rolling = false;
  String _status = 'Roll the dice to start.';

  /// Guard against duplicate completion records: the win path can
  /// be reached from a move, from a restored finished state, and
  /// from a repeated turn-change notification. Set synchronously
  /// when the completion flow starts.
  bool _completionAttempted = false;

  /// True when the completion record failed (or no repository was
  /// available): the results screen carries the failure notice.
  bool _completionFailed = false;

  /// True while a completion record is in flight for a finished
  /// match. The view navigates to the results screen only once this is false,
  /// so a failed record can be reported in the dialog itself, never
  /// presented as a success.
  bool get completionPending => _completionPending;
  bool _completionPending = false;

  /// The setup this match was started (or resumed) with — Play Again
  /// and Restart reuse it instead of re-reading route arguments,
  /// which a resumed match does not have.
  MatchSetup? get currentSetup => _currentSetup;
  MatchSetup? _currentSetup;

  bool _vibrationEnabled;
  bool _vibrationLoadStarted = false;

  /// Whether the match is paused (M2.6, D-10): a freeze — the AI
  /// and dice timers are cancelled and no turn advances until
  /// [resume]. State is preserved exactly: the same turn, the same
  /// legal moves, the same displayed roll. A roll whose tumble was
  /// interrupted keeps its decided value in [_settlingRollValue]
  /// and settles on resume.
  bool get isPaused => _paused;
  bool _paused = false;

  /// The dice value the engine already fixed for a roll whose
  /// tumble is still running (or was interrupted by [pause]).
  /// The tumble only displays this value; it is never re-rolled.
  int? _settlingRollValue;

  bool _disposed = false;
  Timer? _rollTimer;
  Timer? _aiTimer;

  final List<void Function()> _listeners = [];

  /// The current immutable snapshot. Observers must treat it as
  /// read-only. Throws [StateError] before any match has started.
  GameState get state => _requireGame().state;

  /// Legal moves for the outstanding roll, empty otherwise.
  List<Move> get legalMoves => List.unmodifiable(_legalMoves);

  /// The settled dice value, or the tumbling face while rolling.
  int? get displayedRoll => _displayedRoll;

  /// True while the dice tumble animation is running.
  bool get rolling => _rolling;

  /// The status line, exactly as the screen rendered it.
  String get status => _status;

  /// Reports an illegal tap in the status line (M2.8, FR-21).
  ///
  /// Display only: [message] replaces [_status] until the next
  /// roll or move overwrites it. Game state is untouched — no roll
  /// is started, no move applied, no turn changed, nothing
  /// persisted — and no notification other than the status change
  /// itself is produced. The screen pairs this with a SnackBar
  /// carrying the same message; the controller owns the status
  /// line because the screen holds no copy of it (M3.2).
  void noteIllegalTap(String message) {
    if (_disposed) return;
    _status = message;
    _notify();
  }

  /// True once a player has won (BR-11).
  bool get isFinished => _game?.isFinished ?? false;

  /// The winning player, or null while the match is unfinished.
  Player? get winner => _game?.winner;

  /// True when the completion record failed (or no repository was
  /// available). The results screen carries the failure notice then.
  bool get completionFailed => _completionFailed;

  /// Registers a change listener (see the class doc). The view adds
  /// one; tests may add their own. A throwing listener is logged
  /// and skipped — it must never break the turn loop.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Unregisters a listener added with [addListener].
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (error) {
        log(
          'DiceUp controller listener failed ($error)',
          name: 'DiceUpOfflineGameController',
        );
      }
    }
  }

  LudoGame _requireGame() {
    final game = _game;
    if (game == null) {
      throw StateError('OfflineGameController: no match has started yet.');
    }
    return game;
  }

  /// Starts a fresh match from [setup] (M3.1 [StartOfflineMatch]).
  /// Cancels any live timers from a previous match first.
  void startMatch(MatchSetup setup) {
    if (_disposed) return;
    _cancelTimers();
    _paused = false;
    _settlingRollValue = null;
    _game = _startMatch(setup);
    _currentSetup = setup;
    _rebuildAiPlayers();
    _legalMoves = [];
    _displayedRoll = null;
    _rolling = false;
    _completionAttempted = false;
    _completionFailed = false;
    _completionPending = false;
    _status = '${_game!.currentPlayer.name}, roll the dice to start.';
    _loadVibrationSetting();
    _afterTurnChange();
    _notify();
  }

  /// Rebuilds a match around a restored snapshot (M1.6, D-11).
  ///
  /// The exact state is restored via [LudoGame.fromState] — player
  /// config, AI difficulty, ruleset, dice state, all required
  /// fields — and the AI map is rebuilt from the restored state's
  /// [AiPlayer] seats, never from route arguments. Play Again /
  /// Restart reuse the restored match's own options, exactly as the
  /// screen's `_restoreMatch` did.
  void restoreMatch(GameState state) {
    if (_disposed) return;
    _cancelTimers();
    _paused = false;
    _settlingRollValue = null;
    _game = LudoGame.fromState(state, diceRoller: _diceRoller);
    _currentSetup = MatchSetup(
      playerCount: state.players.length,
      aiSeats: {
        for (final player in state.players)
          if (player is AiPlayer) player.index: player.difficulty,
      },
      names: [for (final player in state.players) player.name],
      colours: [for (final player in state.players) player.colour],
      ruleset: _game!.ruleset,
    );
    _rebuildAiPlayers();
    _legalMoves = _game!.legalMoves();
    _displayedRoll = state.lastRoll == 0 ? null : state.lastRoll;
    _rolling = false;
    _completionAttempted = false;
    _completionFailed = false;
    _completionPending = false;
    _status = switch (state.phase) {
      TurnPhase.awaitingMove =>
        '${_game!.currentPlayer.name}, choose a token to move.',
      TurnPhase.finished => 'Match over.',
      TurnPhase.awaitingRoll =>
        '${_game!.currentPlayer.name}, roll the dice to start.',
    };
    _loadVibrationSetting();
    _afterTurnChange();
    _notify();
  }

  /// The live state's [AiPlayer] seats are the single source of
  /// truth for AI difficulty — the map is rebuilt from them, never
  /// from the setup, so a resumed match keeps its true difficulties.
  void _rebuildAiPlayers() {
    _aiPlayers.clear();
    for (final player in _game!.state.players) {
      if (player is AiPlayer) _aiPlayers[player.index] = player;
    }
  }

  /// Restarts the current match with the same setup (M2.6 restart:
  /// the current match is discarded first — its snapshot is deleted
  /// before the new match starts, and nothing is recorded). Throws
  /// [StateError] when no match has started yet.
  Future<void> restart() async {
    final setup = _currentSetup;
    if (setup == null) {
      throw StateError(
        'OfflineGameController: cannot restart — no match has started yet.',
      );
    }
    _cancelTimers();
    await discardSnapshot();
    startMatch(setup);
  }

  /// Deletes the in-progress snapshot for a deliberate exit from an
  /// unfinished match (D-11/D-12). A no-op for a finished match —
  /// its snapshot is already gone — and when nothing is persisted.
  /// Never throws: exiting must never trap the user behind storage.
  Future<void> discardSnapshot() async {
    final game = _game;
    if (game == null || game.isFinished) return;
    final writer = _snapshotWriter;
    if (writer != null) {
      await writer.discard();
      return;
    }
    final snapshots = _snapshots;
    if (snapshots == null) return;
    try {
      await snapshots.deleteSnapshot(kCurrentMatchKey);
    } catch (error) {
      log(
        'DiceUp snapshot discard failed ($error)',
        name: 'DiceUpOfflineGameController',
      );
    }
  }

  /// Pauses the match (M2.6, D-10): a freeze, not a menu-only
  /// overlay. Both timers are cancelled — the AI pacing timer and
  /// the dice tumble — so nothing advances while paused: no AI
  /// roll or move, no tumble tick, no turn change. State is
  /// untouched: the same turn, legal moves and displayed roll are
  /// all still there on [resume]. A roll mid-tumble keeps its
  /// engine-decided value in [_settlingRollValue] and settles on
  /// resume. Idempotent; a no-op on a finished match (there is
  /// nothing left to freeze — the results screen owns that state).
  /// Does not touch the snapshot: a paused match is still
  /// in-progress and stays resumable.
  void pause() {
    if (_disposed || _paused || isFinished) return;
    _paused = true;
    _cancelTimers();
    _notify();
  }

  /// Resumes a paused match (M2.6, D-10): the turn flow restarts
  /// exactly once. A tumble interrupted by [pause] settles now on
  /// its already-decided value ([_settleRoll], which runs the
  /// turn-change path once); otherwise the turn-change path runs
  /// once directly — an AI turn re-schedules its pacing timer
  /// fresh (700–1,199 ms, D-31), a human turn schedules nothing.
  /// A stale timer can never act on the resumed state: [pause]
  /// cancelled both timers, and this is the only path that
  /// re-schedules. Idempotent; a no-op when not paused.
  void resume() {
    if (_disposed || !_paused) return;
    _paused = false;
    if (_rolling) {
      _settleRoll();
    } else {
      _afterTurnChange();
      _notify();
    }
  }

  /// Cancels the roll and AI timers. The controller must not be
  /// used after this (the view disposes it with the screen).
  void dispose() {
    _disposed = true;
    _cancelTimers();
  }

  void _cancelTimers() {
    _rollTimer?.cancel();
    _rollTimer = null;
    _aiTimer?.cancel();
    _aiTimer = null;
  }

  // -- Persistence ---------------------------------------------------------

  /// Refreshes the vibration flag from the persisted setting (M1.7).
  ///
  /// The startup-loaded snapshot is the first value (so a move can
  /// never vibrate before this read lands), and this read picks up a
  /// toggle changed after startup. Skipped when the test override
  /// is given ([vibrationRefreshEnabled] is false) or there is
  /// nothing to read from. A failed read keeps the current value:
  /// storage trouble must never silence feedback by accident, and
  /// never wedge the match.
  Future<void> _loadVibrationSetting() async {
    if (!vibrationRefreshEnabled || _vibrationLoadStarted) {
      return;
    }
    _vibrationLoadStarted = true;
    final settings = _settings;
    if (settings == null) return;
    try {
      final stored = await settings.getSetting('vibration_enabled');
      if (_disposed || stored == null) return;
      _vibrationEnabled = stored != '0';
    } catch (_) {
      // Keep the startup-loaded value (see above).
    }
  }

  /// Queues a snapshot save of the current state (FR-29). Skipped
  /// when there is nothing to persist into, and never for a finished
  /// match — the snapshot is deleted at completion, not saved.
  /// Fire-and-forget: [SnapshotWriter.save] never throws, and the
  /// direct fallback below never throws either.
  void _saveSnapshot() {
    final game = _game;
    if (game == null || game.isFinished) return;
    final writer = _snapshotWriter;
    if (writer != null) {
      writer.save(game.state);
      return;
    }
    final snapshots = _snapshots;
    if (snapshots == null) return;
    unawaited(_saveSnapshotDirect(game.state, snapshots));
  }

  Future<void> _saveSnapshotDirect(
    GameState state,
    SnapshotRepository snapshots,
  ) async {
    try {
      await snapshots.saveSnapshot(
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
        name: 'DiceUpOfflineGameController',
      );
    }
  }

  // -- Dice ---------------------------------------------------------------

  /// Rolls the dice for the active player (FR-15).
  ///
  /// The engine decides the value now; the tumble only displays it.
  /// Ignored while a roll is animating, when the match is finished,
  /// or when no roll is pending — exactly as the screen's `_rollDice`
  /// ignored those taps.
  void rollDice() {
    if (_disposed || _rolling || _paused) return;
    final game = _game;
    if (game == null || game.isFinished) return;
    if (game.state.phase != TurnPhase.awaitingRoll) return;
    // The engine decides the value now; the animation only displays it.
    final roll = _rollDice(game, isRolling: _rolling);
    final value = roll.value;
    _settlingRollValue = value;
    _rolling = true;
    _displayedRoll = null;
    _status = 'Rolling…';
    _notify();
    var ticks = 0;
    _rollTimer?.cancel();
    _rollTimer = _periodicTimer(const Duration(milliseconds: 90), (timer) {
      ticks++;
      if (_disposed) {
        timer.cancel();
        return;
      }
      if (ticks >= 6) {
        timer.cancel();
        _settleRoll();
      } else {
        _displayedRoll = _random.nextInt(6) + 1;
        _notify();
      }
    });
  }

  /// Settles a roll on its engine-decided value (M2.6): the tumble
  /// ends, the legal moves and status are computed, the turn-change
  /// path runs once (an AI turn schedules its pacing timer), and
  /// the settled roll is snapshotted. Shared by the tumble timer
  /// and by [resume] — a tumble interrupted by [pause] settles
  /// here, on the same value, with the same side effects, exactly
  /// once. A no-op when no roll is settling.
  void _settleRoll() {
    final value = _settlingRollValue;
    if (value == null || _game == null) return;
    _settlingRollValue = null;
    _rollTimer?.cancel();
    _rollTimer = null;
    _rolling = false;
    _displayedRoll = value;
    _legalMoves = _game!.legalMoves();
    _status = _rollStatus();
    _notify();
    _afterTurnChange();
    // A roll changes state (lastRoll / phase), and a capture
    // after a roll but before a move must resume the rolled
    // state — so the settled roll is snapshotted too (FR-29).
    _saveSnapshot();
  }

  String _rollStatus() {
    final state = _game!.state;
    if (state.lastRollWasThirdSix) {
      return 'Third six in a row — the roll is not played, turn passes.';
    }
    if (state.lastRollHadNoLegalMove) {
      return state.lastRoll == 6
          ? 'No legal move — but a six earns another roll.'
          : 'No legal move — turn passes.';
    }
    return '${state.currentPlayer.name}, choose a token to move.';
  }

  // -- Moves --------------------------------------------------------------

  /// Applies one move (FR-17) via the [ApplyMove] use case, which
  /// owns the engine call and its persistence side effects
  /// (snapshot-after-move, exactly-once completion recording).
  ///
  /// Ignored when the match is finished or no move is pending —
  /// exactly as the screen's `_applyMove` ignored those calls. The
  /// returned future completes once the move's persistence has
  /// settled, so the view sees the final state (including the
  /// completion record) in the notification that follows; the UI
  /// state itself is updated from the use case's result, never
  /// re-derived.
  Future<void> applyMove(Move move) async {
    if (_disposed || _paused) return;
    final game = _game;
    if (game == null || game.isFinished) return;
    if (game.state.phase != TurnPhase.awaitingMove) return;
    final apply = _applyMove;
    if (apply == null) {
      // Degraded play (no repositories): the engine move still
      // applies and the turn still flows; nothing is persisted and
      // a finished match reports the failure, exactly as the screen
      // did without dependencies.
      final result = game.applyMove(move);
      _legalMoves = game.legalMoves();
      _status = _moveStatus(result);
      if (game.isFinished) {
        _completionAttempted = true;
        _completionFailed = true;
      }
      _vibrateOnMove();
      _afterTurnChange();
      _notify();
      return;
    }
    final applied = await apply(game, move);
    // The game may have been replaced (restart) while the record
    // was in flight: the applied result belongs to the old match.
    if (!identical(_game, game) || _disposed) return;
    _legalMoves = game.legalMoves();
    _status = _moveStatus(applied.result);
    if (game.isFinished) {
      _completionAttempted = true;
      _completionFailed = applied.completionFailed;
    }
    _vibrateOnMove();
    _afterTurnChange();
    _notify();
  }

  String _moveStatus(MoveResult result) {
    final game = _game!;
    if (result.captured.isNotEmpty) {
      return 'Captured! ${result.captured.length} token(s) sent home.';
    } else if (result.reachedHome) {
      return 'Token home! ${game.currentPlayer.name} rolls again.';
    } else if (result.extraTurn) {
      return 'Six! ${game.currentPlayer.name} rolls again.';
    } else {
      return '${game.currentPlayer.name}, roll the dice.';
    }
  }

  /// One light haptic per completed move (M1.7, D-32), through the
  /// [onMoveApplied] callback the view wires to its [FeedbackService]
  /// abstraction, and only while vibration is enabled.
  /// Fire-and-forget and never throwing into the turn loop: a failed
  /// haptic must not wedge a move. The provider's closure already
  /// swallows async failures (`catchError`); this try/catch covers
  /// a hook that throws synchronously (M2.11: proved by
  /// `test/haptics_gate_test.dart`, "a throwing feedback hook
  /// never wedges a move").
  void _vibrateOnMove() {
    if (!_vibrationEnabled) return;
    try {
      onMoveApplied?.call();
    } catch (error) {
      log(
        'DiceUp haptic feedback failed ($error)',
        name: 'DiceUpOfflineGameController',
      );
    }
  }

  // -- Turn flow ----------------------------------------------------------

  void _afterTurnChange() {
    final game = _game;
    if (game == null || _disposed || _paused) return;
    if (game.isFinished) {
      if (!_completionAttempted) {
        // A resumed finished match (M3.2, seam 4): no move was
        // applied here, so no use case recorded it — the record is
        // retried on this path, as the screen did it. The flag is
        // set synchronously before the first await, so a second
        // completion callback cannot start a second record.
        _completionAttempted = true;
        _completionPending = true;
        unawaited(_recordCompletionAndNotify(game));
      }
      return;
    }
    if (game.currentPlayer.isAi) {
      _scheduleAi();
    }
  }

  /// Records the finished match, then notifies so the view can show
  /// the results screen with the record's outcome decided. The record
  /// runs before the dialog so a failed record can be reported in
  /// the dialog itself, never presented as a success. A restart
  /// that replaced the match while the record was in flight leaves
  /// the new match untouched.
  Future<void> _recordCompletionAndNotify(LudoGame game) async {
    final recordFailed = await _recordCompletion(game);
    if (!identical(_game, game) || _disposed) return;
    _completionFailed = recordFailed;
    _completionPending = false;
    _notify();
  }

  /// Records the match once via [LocalMatchRepository.recordMatch]
  /// (one transaction: match row + statistics + prune + snapshot
  /// delete, FR-30). Returns true when recording failed.
  ///
  /// On failure the match is not lost silently: the error is
  /// logged, and the results screen carries the failure notice. The
  /// snapshot is left in place deliberately — the finished match
  /// stays resumable and recording is retried when it is resumed.
  Future<bool> _recordCompletion(LudoGame game) async {
    final matches = _matches;
    if (matches == null) {
      log(
        'DiceUp match completed but no match repository is available; '
        'nothing was recorded.',
        name: 'DiceUpOfflineGameController',
      );
      return true;
    }
    // No stale snapshot write may land after the record deletes the
    // row in its transaction.
    _snapshotWriter?.invalidate();
    try {
      await matches.recordMatch(ApplyMove.buildLocalMatch(game, _now()));
      return false;
    } catch (error) {
      log(
        'DiceUp match recording failed ($error)',
        name: 'DiceUpOfflineGameController',
      );
      return true;
    }
  }

  void _scheduleAi() {
    _aiTimer?.cancel();
    final delay = Duration(milliseconds: 700 + _random.nextInt(500)); // FR-40
    _aiTimer = _oneShotTimer(delay, () {
      if (_disposed || _paused) return;
      final game = _game;
      if (game == null || game.isFinished) return;
      if (!game.currentPlayer.isAi) return;
      if (game.state.phase == TurnPhase.awaitingRoll) {
        rollDice();
      } else if (game.state.phase == TurnPhase.awaitingMove) {
        final ai = _aiPlayers[game.currentPlayerIndex];
        if (ai == null) return;
        final moves = game.legalMoves();
        if (moves.isEmpty) return;
        final choice = ai.chooseMove(moves, game.state, game.board);
        unawaited(applyMove(choice));
      }
    });
  }
}
