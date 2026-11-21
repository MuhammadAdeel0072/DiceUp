import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../domain/ai/ai_player.dart';
import '../../domain/engine/dice_roller.dart';
import '../../domain/engine/game_state.dart';
import '../../domain/engine/ludo_game.dart';
import '../../domain/engine/move.dart';
import '../../domain/engine/player.dart';
import '../../domain/engine/player_colour.dart';
import '../navigation/app_routes.dart';
import '../widgets/dice_widget.dart';
import '../widgets/ludo_board.dart';

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
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.initialSetup, this.diceRoller});

  /// Setup supplied directly (widget tests, deep links). When null, the
  /// setup comes from the route arguments (see [AppRoutes.gameSetupOf]).
  final GameSetup? initialSetup;

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
  bool _initialized = false;
  Timer? _rollTimer;
  Timer? _aiTimer;
  final _random = Random();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final setup = widget.initialSetup ?? AppRoutes.gameSetupOf(context);
    _startMatch(setup);
  }

  void _startMatch(GameSetup setup) {
    final seats = List<SeatConfig>.generate(setup.playerCount, (i) {
      final isAi = setup.aiSeats.containsKey(i);
      return SeatConfig(
        name: 'Player ${i + 1}',
        colour: PlayerColour.values[i],
        type: isAi ? PlayerType.ai : PlayerType.human,
      );
    });
    _game = LudoGame.newMatch(seats: seats, diceRoller: widget.diceRoller);
    _aiPlayers.clear();
    for (final entry in setup.aiSeats.entries) {
      _aiPlayers[entry.key] = AiPlayer(
        index: entry.key,
        name: 'Player ${entry.key + 1}',
        colour: PlayerColour.values[entry.key],
        difficulty: entry.value,
      );
    }
    _legalMoves = [];
    _displayedRoll = null;
    _rolling = false;
    _winDialogShown = false;
    _status = '${_game.currentPlayer.name}, roll the dice to start.';
    _afterTurnChange();
  }

  @override
  void dispose() {
    _rollTimer?.cancel();
    _aiTimer?.cancel();
    super.dispose();
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showWinDialog();
        });
      }
      return;
    }
    if (_game.currentPlayer.isAi) {
      _scheduleAi();
    }
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
    final setup = AppRoutes.gameSetupOf(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('${winner.name} wins!'),
        content: Text(
          '${winner.name} brought all four tokens home in '
          '${_game.state.moveCount} moves.',
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
    if (leave && mounted) Navigator.of(context).pop();
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

    return Scaffold(
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
              final restart = await ConfirmationDialog.show(
                context,
                title: 'Restart match?',
                message: 'The current match will be discarded.',
                confirmLabel: 'Restart',
              );
              if (restart && mounted) {
                setState(() => _startMatch(AppRoutes.gameSetupOf(context)));
              }
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
