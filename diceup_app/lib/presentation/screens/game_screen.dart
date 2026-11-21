import 'dart:async';
import 'dart:developer';
import 'dart:math' hide log;

import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../data/local/app_dependencies.dart';
import '../../domain/ai/ai_player.dart';
import '../../domain/engine/dice_roller.dart';
import '../../domain/engine/game_state.dart';
import '../../domain/engine/ludo_game.dart';
import '../../domain/engine/move.dart';
import '../../domain/engine/player.dart';
import '../../domain/engine/player_colour.dart';
import '../../domain/repositories/local_match_repository.dart';
import '../app_dependencies_scope.dart';
import '../navigation/app_routes.dart';
import '../widgets/dice_widget.dart';
import '../widgets/ludo_board.dart';

/// Shown in the win dialog when the completed match could not be
/// recorded (M1.6). The snapshot is left in place in that case, so
/// the finished match stays resumable and recording is retried on
/// resume; the dialog must never present the win as if recording
/// had succeeded without this notice.
const String kMatchRecordFailedMessage =
    "This match finished, but it couldn't be saved to your history.";

/// Offline match screen (SRS UI-03…UI-05, FR-15…FR-28).
///
/// Owns the match controller: it drives [LudoGame] and the AI, and renders
/// [GameState] snapshots. It never re-derives rules — the engine decides
/// dice, legal moves, captures and the winner; the UI only displays what
/// the engine reports ([MoveResult]) and animates it.
///
/// Dice honesty: [LudoGame.rollDice] is called the moment the player taps
/// Roll, so the engine fixes the value immediately; the tumbling animation
/// only displays random faces until it settles on the engine's value.
///
/// AI pacing (FR-40): 700–1,199 ms before an AI rolls or moves (D-31).
///
/// Persistence (M1.6, FR-28…FR-31): after every completed move — and
/// after a dice roll settles, because a roll changes state — the
/// current snapshot is queued with [SnapshotSaver] (fire-and-forget,
/// ordered, never throwing into the turn loop). A finished match is
/// recorded exactly once via [LocalMatchRepository.recordMatch],
/// which also deletes the snapshot in the same transaction (SDD
/// §6.6). Leaving an unfinished match (AppBar close, Restart,
/// system back) deletes the snapshot and records nothing (D-11,
/// D-12). No snapshot code for pause (M2.6) or results screen (M2.5)
/// lives here — the win dialog is still the results presentation.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.initialSetup, this.initialState, this.diceRoller});

  /// Setup supplied directly (widget tests, deep links). When null, the
  /// setup comes from the route arguments (see [AppRoutes.gameSetupOf]).
  /// Ignored when [initialState] is given.
  final GameSetup? initialSetup;

  /// A restored match to resume (M1.6): the exact [GameState] from
  /// the saved snapshot, via route arguments (see
  /// [AppRoutes.resumedStateOf]) or directly in tests. Takes
  /// precedence over [initialSetup].
  final GameState? initialState;

  /// Dice source override for tests ([FixedDiceRoller]). Production
  /// always uses the engine's random roller.
  final DiceRoller? diceRoller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late LudoGame _game;
  final Map<int, AiPlayer> _aiPlayers = {};
  List<Move> _legalMoves = [];
  int? _displayedRoll;
  bool _rolling = false;
  String _status = 'Roll the dice to start.';
  bool _winDialogShown = false;

  /// Guard against duplicate completion callbacks: the win path can
  /// be reached from a move, from a restored finished state, and
  /// from a repeated turn-change notification. Set synchronously
  /// when the completion flow starts; the existing [_winDialogShown]
  /// flag alone is not sufficient because it only guards the dialog.
  bool _completionRecorded = false;

  /// True when the completion record failed (or no repository was
  /// available): the win dialog carries [kMatchRecordFailedMessage].
  bool _completionFailed = false;

  /// The setup this match was started (or resumed) with — Play Again
  /// and Restart reuse it instead of re-reading route arguments,
  /// which a resumed match does not have as a [GameSetup].
  GameSetup? _currentSetup;

  /// The app dependencies, or null when the database is unavailable
  /// (degraded startup) or the screen runs outside [DiceUpApp]
  /// (bare widget tests): the match stays playable, nothing is
  /// persisted, and completion reports the failure in the dialog.
  AppDependencies? _deps;

  bool _initialized = false;
  Timer? _rollTimer;
  Timer? _aiTimer;
  final _random = Random();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _deps = AppDependenciesScope.maybeOf(context)?.dependencies;
    if (_initialized) return;
    _initialized = true;
    final resumed = widget.initialState ?? AppRoutes.resumedStateOf(context);
    if (resumed != null) {
      _restoreMatch(resumed);
    } else {
      _startMatch(widget.initialSetup ?? AppRoutes.gameSetupOf(context));
    }
  }

  void _startMatch(GameSetup setup) {
    final seats = List<SeatConfig>.generate(setup.playerCount, (i) {
      final difficulty = setup.aiSeats[i];
      return SeatConfig(
        name: 'Player ${i + 1}',
        colour: PlayerColour.values[i],
        type: difficulty == null ? PlayerType.human : PlayerType.ai,
        difficulty: difficulty,
      );
    });
    _game = LudoGame.newMatch(seats: seats, diceRoller: widget.diceRoller);
    _currentSetup = setup;
    _rebuildAiPlayers();
    _legalMoves = [];
    _displayedRoll = null;
    _rolling = false;
    _winDialogShown = false;
    _completionRecorded = false;
    _completionFailed = false;
    _status = '${_game.currentPlayer.name}, roll the dice to start.';
    _afterTurnChange();
  }

  /// Rebuilds a match around a restored snapshot (M1.6, D-11).
  ///
  /// The exact state is restored via [LudoGame.fromState] — player
  /// config, AI difficulty, ruleset, dice state, all required
  /// fields — and the AI map is rebuilt from the restored state's
  /// [AiPlayer] seats, never from route arguments.
  void _restoreMatch(GameState state) {
    _game = LudoGame.fromState(state, diceRoller: widget.diceRoller);
    _currentSetup = GameSetup(
      playerCount: state.players.length,
      aiSeats: {
        for (final player in state.players)
          if (player is AiPlayer) player.index: player.difficulty,
      },
    );
    _rebuildAiPlayers();
    _legalMoves = _game.legalMoves();
    _displayedRoll = state.lastRoll == 0 ? null : state.lastRoll;
    _rolling = false;
    _winDialogShown = false;
    _completionRecorded = false;
    _completionFailed = false;
    _status = switch (state.phase) {
      TurnPhase.awaitingMove =>
        '${_game.currentPlayer.name}, choose a token to move.',
      TurnPhase.finished => 'Match over.',
      TurnPhase.awaitingRoll =>
        '${_game.currentPlayer.name}, roll the dice to start.',
    };
    _afterTurnChange();
  }

  /// The live state's [AiPlayer] seats are the single source of
  /// truth for AI difficulty — the map is rebuilt from them, never
  /// from the setup, so a resumed match keeps its true difficulties.
  void _rebuildAiPlayers() {
    _aiPlayers.clear();
    for (final player in _game.state.players) {
      if (player is AiPlayer) _aiPlayers[player.index] = player;
    }
  }

  @override
  void dispose() {
    _rollTimer?.cancel();
    _aiTimer?.cancel();
    super.dispose();
  }

  // -- Persistence ---------------------------------------------------------

  /// Queues a snapshot save of the current state (FR-29). Skipped
  /// when there is nothing to persist into, and never for a finished
  /// match — the snapshot is deleted at completion, not saved.
  /// Fire-and-forget: [SnapshotSaver.save] never throws.
  void _saveSnapshot() {
    final deps = _deps;
    if (deps == null || _game.isFinished) return;
    deps.snapshotSaver.save(_game.state);
  }

  /// Deletes the in-progress snapshot for a deliberate exit from an
  /// unfinished match (D-11/D-12). A no-op for a finished match —
  /// its snapshot is already gone — and when nothing is persisted.
  /// Never throws: exiting must never trap the user behind storage.
  Future<void> _discardSnapshot() async {
    final deps = _deps;
    if (deps == null || _game.isFinished) return;
    try {
      await deps.snapshotSaver.discard();
    } catch (error) {
      log(
        'DiceUp snapshot discard failed ($error)',
        name: 'DiceUpGameScreen',
      );
    }
  }

  // -- Dice ---------------------------------------------------------------

  void _rollDice() {
    if (_rolling || _game.isFinished) return;
    if (_game.state.phase != TurnPhase.awaitingRoll) return;
    // The engine decides the value now; the animation only displays it.
    final value = _game.rollDice();
    setState(() {
      _rolling = true;
      _displayedRoll = null;
      _status = 'Rolling…';
    });
    var ticks = 0;
    _rollTimer?.cancel();
    _rollTimer = Timer.periodic(const Duration(milliseconds: 90), (timer) {
      ticks++;
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (ticks >= 6) {
        timer.cancel();
        setState(() {
          _rolling = false;
          _displayedRoll = value;
          _legalMoves = _game.legalMoves();
          _status = _rollStatus();
        });
        _afterTurnChange();
        // A roll changes state (lastRoll / phase), and a capture
        // after a roll but before a move must resume the rolled
        // state — so the settled roll is snapshotted too (FR-29).
        _saveSnapshot();
      } else {
        setState(() => _displayedRoll = _random.nextInt(6) + 1);
      }
    });
  }

  String _rollStatus() {
    final state = _game.state;
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

  void _applyMove(Move move) {
    if (_game.state.phase != TurnPhase.awaitingMove) return;
    final result = _game.applyMove(move);
    setState(() {
      _legalMoves = _game.legalMoves();
      if (result.captured.isNotEmpty) {
        _status = 'Captured! ${result.captured.length} token(s) sent home.';
      } else if (result.reachedHome) {
        _status = 'Token home! ${_game.currentPlayer.name} rolls again.';
      } else if (result.extraTurn) {
        _status = 'Six! ${_game.currentPlayer.name} rolls again.';
      } else {
        _status = '${_game.currentPlayer.name}, roll the dice.';
      }
    });
    _afterTurnChange();
    _saveSnapshot();
  }

  void _onBoardTap(TapDownDetails details, double boardSide) {
    if (_rolling || _game.isFinished) return;
    if (_game.state.phase != TurnPhase.awaitingMove) return;
    if (_game.currentPlayer.isAi) return;
    final tokens = _boardTokens();
    final cell = boardSide / 15;
    for (final move in _legalMoves) {
      final token = _game.currentPlayer.tokens[move.tokenIndex];
      final view = BoardToken(
        id: '${token.playerIndex}:${token.index}',
        seatIndex: token.playerIndex,
        stepsTaken: token.stepsTaken,
      );
      final centre = boardTokenCenter(
        view,
        Size(boardSide, boardSide),
        tokens,
      );
      if ((details.localPosition - centre).distance <= cell * 0.6) {
        _applyMove(move);
        return;
      }
    }
  }

  List<BoardToken> _boardTokens() {
    return [
      for (final player in _game.state.players)
        for (final token in player.tokens)
          BoardToken(
            id: '${token.playerIndex}:${token.index}',
            seatIndex: token.playerIndex,
            stepsTaken: token.stepsTaken,
          ),
    ];
  }

  // -- Turn flow ----------------------------------------------------------

  void _afterTurnChange() {
    if (_game.isFinished) {
      if (!_winDialogShown) {
        _winDialogShown = true;
        _recordCompletionAndShowDialog();
      }
      return;
    }
    if (_game.currentPlayer.isAi) {
      _scheduleAi();
    }
  }

  /// Records the finished match exactly once, then shows the win
  /// dialog. The record runs before the dialog so a failed record
  /// can be reported in the dialog itself, never presented as a
  /// success. The [_completionRecorded] flag is set synchronously
  /// here, before the first await, so a second completion callback
  /// cannot start a second record.
  Future<void> _recordCompletionAndShowDialog() async {
    if (_completionRecorded) return;
    _completionRecorded = true;
    final recordFailed = await _recordCompletion();
    if (!mounted) return;
    _completionFailed = recordFailed;
    _showWinDialog();
  }

  /// Records the match once via [LocalMatchRepository.recordMatch]
  /// (one transaction: match row + statistics + prune + snapshot
  /// delete, FR-30). Returns true when recording failed.
  ///
  /// On failure the match is not lost silently: the error is
  /// logged, the game screen stays usable, and the win dialog
  /// carries [kMatchRecordFailedMessage]. The snapshot is left in
  /// place deliberately — the finished match stays resumable and
  /// recording is retried when it is resumed.
  Future<bool> _recordCompletion() async {
    final deps = _deps;
    if (deps == null) {
      log(
        'DiceUp match completed but no dependencies are available; '
        'nothing was recorded.',
        name: 'DiceUpGameScreen',
      );
      return true;
    }
    // No stale snapshot write may land after the record deletes the
    // row in its transaction.
    deps.snapshotSaver.invalidate();
    try {
      await deps.matches.recordMatch(_buildLocalMatch());
      return false;
    } catch (error) {
      log(
        'DiceUp match recording failed ($error)',
        name: 'DiceUpGameScreen',
      );
      return true;
    }
  }

  /// The completed match for the record (FR-30): date, mode,
  /// players, winner and duration in one value. Mode is vs-AI when
  /// any seat is AI, else local multiplayer; duration comes from the
  /// state's [GameState.startedAt]; player difficulties come from
  /// the live [AiPlayer] seats, never the setup default.
  LocalMatch _buildLocalMatch() {
    final state = _game.state;
    final winner = _game.winner;
    final now = DateTime.now();
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
            difficulty:
                player is AiPlayer ? player.difficulty : null,
          ),
      ],
      winnerIndex: _game.winnerIndex,
      winnerName: winner?.name,
      durationSeconds: startedAt == null
          ? null
          : max(0, now.difference(startedAt).inSeconds),
      rulesetVersion: state.rulesetVersion,
      createdAt: now,
    );
  }

  void _scheduleAi() {
    _aiTimer?.cancel();
    final delay =
        Duration(milliseconds: 700 + _random.nextInt(500)); // FR-40
    _aiTimer = Timer(delay, () {
      if (!mounted || _game.isFinished) return;
      if (!_game.currentPlayer.isAi) return;
      if (_game.state.phase == TurnPhase.awaitingRoll) {
        _rollDice();
      } else if (_game.state.phase == TurnPhase.awaitingMove) {
        final ai = _aiPlayers[_game.currentPlayerIndex];
        if (ai == null) return;
        final moves = _game.legalMoves();
        if (moves.isEmpty) return;
        final choice = ai.chooseMove(moves, _game.state, _game.board);
        _applyMove(choice);
      }
    });
  }

  // -- Dialogs ------------------------------------------------------------

  Future<void> _showWinDialog() async {
    final winner = _game.winner;
    if (winner == null) return;
    final setup =
        _currentSetup ?? AppRoutes.gameSetupOf(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('${winner.name} wins!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${winner.name} brought all four tokens home in '
              '${_game.state.moveCount} moves.',
            ),
            if (_completionFailed) ...[
              const SizedBox(height: 12),
              const Text(kMatchRecordFailedMessage),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Back to menu'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() => _startMatch(setup));
            },
            child: const Text('Play again'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmExit() async {
    final leave = await ConfirmationDialog.show(
      context,
      title: 'Leave the match?',
      message: _game.isFinished
          ? 'This match is over.'
          : 'Your progress in this match will be lost.',
      confirmLabel: 'Leave',
    );
    if (!leave || !mounted) return;
    // Clean exit (D-11/D-12): an unfinished match is deleted from
    // the snapshot store and records nothing — no history row, no
    // statistics, no saved match. A finished match's snapshot is
    // already gone, so nothing is deleted.
    if (!_game.isFinished) await _discardSnapshot();
    if (mounted) Navigator.of(context).pop();
  }

  // -- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final state = _game.state;
    final current = state.currentPlayer;
    final isHumanTurn = current.isHuman &&
        state.phase != TurnPhase.finished &&
        !_rolling;
    final boardSide = _boardSide(context);

    // System back (PopScope) only guards the snapshot: a back-pop
    // from an unfinished match deletes it, so the abandoned match
    // can never be resumed. It builds no pause menu (M2.6) and adds
    // no confirmation — the FR-28 confirmation still applies
    // through the AppBar path. A finished match deletes nothing.
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_game.isFinished) {
          unawaited(_discardSnapshot());
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('DiceUp'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Leave match',
            onPressed: _confirmExit,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Restart match',
              onPressed: () async {
                // Resolve the setup before any async gap: the
                // context must not be used after an await.
                final setup =
                    _currentSetup ?? AppRoutes.gameSetupOf(context);
                final restart = await ConfirmationDialog.show(
                  context,
                  title: 'Restart match?',
                  message: 'The current match will be discarded.',
                  confirmLabel: 'Restart',
                );
                if (!restart || !mounted) return;
                // Restart discards the current match (D-11/D-12):
                // its snapshot is deleted before the new match
                // starts, and nothing is recorded.
                if (!_game.isFinished) await _discardSnapshot();
                if (!mounted) return;
                setState(() => _startMatch(setup));
              },
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: DiceUpSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TurnBanner(
                  player: current,
                  status: _status,
                  rolling: _rolling,
                ),
                const SizedBox(height: DiceUpSpacing.md),
                Center(
                  child: GestureDetector(
                    onTapDown: (details) => _onBoardTap(details, boardSide),
                    child: SizedBox(
                      width: boardSide,
                      height: boardSide,
                      child: CustomPaint(
                        painter: LudoBoardPainter(
                          tokens: _boardTokens(),
                          legalTokenIds: _legalMoves
                              .map((m) => '${m.playerIndex}:${m.tokenIndex}')
                              .toSet(),
                          currentSeat: state.currentPlayerIndex,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: DiceUpSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DiceWidget(value: _displayedRoll, rolling: _rolling),
                    const SizedBox(width: DiceUpSpacing.lg),
                    PrimaryButton(
                      label: _rolling ? 'Rolling…' : 'Roll dice',
                      onPressed: isHumanTurn &&
                              state.phase == TurnPhase.awaitingRoll
                          ? _rollDice
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: DiceUpSpacing.md),
                Wrap(
                  spacing: DiceUpSpacing.sm,
                  runSpacing: DiceUpSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final player in state.players)
                      _PlayerChip(
                        player: player,
                        isCurrent: player.index == state.currentPlayerIndex,
                      ),
                  ],
                ),
                const SizedBox(height: DiceUpSpacing.sm),
                Text(
                  'Safe cells are marked with a star. '
                  'Tokens on safe cells cannot be captured.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _boardSide(BuildContext context) {
    final width = MediaQuery.of(context).size.width -
        DiceUpSpacing.md * 2 -
        DiceUpSpacing.md; // screen + safe-area padding
    return width.clamp(280.0, 480.0);
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({
    required this.player,
    required this.status,
    required this.rolling,
  });

  final Player player;
  final String status;
  final bool rolling;

  @override
  Widget build(BuildContext context) {
    return DiceUpCard(
      child: Row(
        children: [
          PlayerAvatar(name: player.name, seatIndex: player.index),
          const SizedBox(width: DiceUpSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${player.name}${player.isAi ? ' (AI)' : ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(status, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          if (rolling)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({required this.player, required this.isCurrent});

  final Player player;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DiceUpSpacing.sm,
        vertical: DiceUpSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isCurrent
            ? DiceUpColors.teal.withValues(alpha: 0.12)
            : DiceUpColors.surfaceMuted,
        borderRadius: DiceUpSpacing.radiusMdBorder,
        border: Border.all(
          color: isCurrent ? DiceUpColors.teal : DiceUpColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: DiceUpColors.playerColor(player.index),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: DiceUpSpacing.xs),
          Text(
            '${player.name} · Home ${player.tokensHome}/4',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
