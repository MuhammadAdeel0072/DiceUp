import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/diceup_colors.dart';
import '../../../core/design_system/diceup_components.dart';
import '../../../core/design_system/diceup_shadows.dart';
import '../../../core/design_system/diceup_spacing.dart';
import '../../../domain/engine/game_state.dart';
import '../../../domain/engine/player_colour.dart';
import '../../../domain/online/connection_state.dart';
import '../../../l10n/app_strings.dart';
import '../../navigation/app_routes.dart';
import '../../providers/app_providers.dart';
import '../../widgets/dice_widget.dart';
import '../../widgets/ludo_board.dart';
import 'online_connection_banner.dart';
import 'online_error_messages.dart';

/// Online game screen (Phase 5, Stage 7; FR-49…FR-58, UI-07).
///
/// Renders the board from the server-authoritative snapshot the
/// [OnlineGameController] holds (`match:state`, refreshed after
/// every `dice:rolled` / `token:moved` / `turn:changed`); the dice
/// and the turn timer come from the same state. Dice rolls and
/// token moves are intents (`dice:roll`, `token:move`) — the server
/// rolls, validates and broadcasts; this screen never predicts a
/// transition and never runs the engine as an authority (the
/// engine is used read-only, by the controller, to highlight legal
/// tokens). A rejection surfaces as `action:rejected` copy, never a
/// raw error. `match:ended` navigates to the results screen with
/// an online [MatchResult] (Play Again hidden there — a rematch
/// starts from the lobby).
///
/// The turn timer and the grace countdowns tick once a second
/// (a [Timer.periodic] in this screen's state); widget tests drive
/// this screen with explicit `tester.pump` calls, never
/// `pumpAndSettle`, for exactly that reason.
class OnlineGameScreen extends ConsumerStatefulWidget {
  const OnlineGameScreen({super.key});

  @override
  ConsumerState<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends ConsumerState<OnlineGameScreen> {
  Timer? _ticker;
  String? _matchId;
  bool _navigatedToResults = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final matchId = AppRoutes.onlineGameMatchIdOf(context);
    if (matchId != null && matchId != _matchId) {
      _matchId = matchId;
      Future.microtask(
        () => ref.read(onlineGameControllerProvider(matchId).notifier).start(),
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    final matchId = _matchId;
    if (matchId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.onlineGameTitle)),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DiceUpSpacing.maxContentWidth,
              ),
              child: Padding(
                padding: DiceUpSpacing.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.onlineGameLoadFailed,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: DiceUpSpacing.lg),
                    SecondaryButton(
                      label: l10n.mainMenu,
                      onPressed: () => _goHome(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final provider = onlineGameControllerProvider(matchId);
    final state = ref.watch(provider);
    final notifier = ref.read(provider.notifier);

    ref.listen(provider, (previous, next) {
      final ended = next.ended;
      if (ended != null && !_navigatedToResults) {
        _navigatedToResults = true;
        _goToResults(context, next);
      }
    });
    ref.listen(provider.select((s) => s.errorCode), (previous, next) {
      if (next == null || next == previous) return;
      final message = onlineErrorMessage(stringsOf(context), next);
      if (message != null) _showFeedback(message);
      ref.read(provider.notifier).clearError();
    });
    ref.listen(provider.select((s) => s.notice), (previous, next) {
      if (next == null || next == previous) return;
      _showPresenceNotice(next, state);
    });

    final snapshot = state.snapshot;
    return PopScope(
      canPop: state.ended != null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_confirmLeave());
      },
      child: Scaffold(
        backgroundColor: DiceUpColors.table,
        appBar: AppBar(
          title: Text(l10n.onlineGameTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: l10n.onlineGameLeave,
              onPressed: state.ended == null ? _confirmLeave : null,
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = constraints.maxWidth > 560
                  ? 560.0
                  : constraints.maxWidth;
              final boardSide = contentWidth - DiceUpSpacing.md * 2;
              return SingleChildScrollView(
                child: Center(
                  child: SizedBox(
                    width: contentWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DiceUpSpacing.md,
                        vertical: DiceUpSpacing.md,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OnlineConnectionBanner(
                            state: state.connectionState,
                            onRetry: notifier.retryConnection,
                          ),
                          if (state.connectionState !=
                              GameSocketConnectionState.connected)
                            const SizedBox(height: DiceUpSpacing.sm),
                          if (state.isLoading) ...[
                            const SizedBox(height: DiceUpSpacing.lg),
                            const Center(child: CircularProgressIndicator()),
                            const SizedBox(height: DiceUpSpacing.md),
                            Text(
                              l10n.onlineGameLoading,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: DiceUpColors.surface,
                              ),
                            ),
                          ] else if (snapshot == null) ...[
                            const SizedBox(height: DiceUpSpacing.lg),
                            Text(
                              l10n.onlineGameLoadFailed,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: DiceUpColors.surface,
                              ),
                            ),
                            const SizedBox(height: DiceUpSpacing.md),
                            Center(
                              child: SecondaryButton(
                                label: l10n.onlineConnectionRetry,
                                onPressed: notifier.retryConnection,
                              ),
                            ),
                          ] else ...[
                            _TurnBanner(
                              state: state,
                              nameOf: (userId) => _nameOf(state, userId),
                            ),
                            const SizedBox(height: DiceUpSpacing.sm),
                            if (state.snapshotError)
                              Text(
                                l10n.onlineGameLoadFailed,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: DiceUpColors.surface,
                                ),
                              ),
                            if (state.snapshotError)
                              const SizedBox(height: DiceUpSpacing.sm),
                            Center(
                              child: Semantics(
                                label: _boardLabel(state),
                                child: GestureDetector(
                                  onTapDown: (details) =>
                                      _onBoardTap(details, boardSide),
                                  child: RepaintBoundary(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            DiceUpSpacing.radiusBoardBorder,
                                        border: Border.all(
                                          color: DiceUpColors.ivory,
                                          width: 2,
                                        ),
                                        boxShadow: DiceUpShadows.table,
                                      ),
                                      child: ClipRRect(
                                        borderRadius:
                                            DiceUpSpacing.radiusLgBorder,
                                        child: SizedBox(
                                          width: boardSide,
                                          height: boardSide,
                                          child: CustomPaint(
                                            painter: LudoBoardPainter(
                                              tokens: _boardTokens(snapshot),
                                              legalTokenIds:
                                                  state.legalTokenIds,
                                              currentSeat:
                                                  snapshot.currentPlayerIndex,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: DiceUpSpacing.sm),
                            _DiceRow(
                              state: state,
                              onDiceTap: _onDiceTap,
                              onRoll: notifier.rollDice,
                            ),
                            const SizedBox(height: DiceUpSpacing.md),
                            _PlayerList(
                              state: state,
                              nameOf: (userId) => _nameOf(state, userId),
                            ),
                            if (state.myPresence != null &&
                                state.myPresence!.missedTurns > 0) ...[
                              const SizedBox(height: DiceUpSpacing.md),
                              Text(
                                l10n.onlineGameMissedTurns(
                                  state.myPresence!.missedTurns,
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: DiceUpColors.surface,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Display name for [userId]: the room member's name when the
  /// server named them, else "Player N" by seat.
  String _nameOf(OnlineGameState state, String userId) {
    final named = state.displayNameOf(userId);
    if (named != null && named.isNotEmpty) return named;
    final seat = state.seatOf(userId);
    return stringsOf(context).playerName((seat ?? 0) + 1);
  }

  String _boardLabel(OnlineGameState state) {
    final l10n = stringsOf(context);
    final snapshot = state.snapshot;
    if (snapshot == null) return l10n.onlineGameLoading;
    final currentId = state.turnPlayerId;
    if (currentId == null) return l10n.onlineGameTitle;
    if (state.isMyTurn) return l10n.onlineGameYourTurn;
    return l10n.onlineGameWaitingFor(_nameOf(state, currentId));
  }

  /// Tokens the board painter draws, adapted from the server
  /// snapshot (same [BoardToken] shape the offline screen uses).
  List<BoardToken> _boardTokens(GameState snapshot) => [
    for (final player in snapshot.players)
      for (final token in player.tokens)
        BoardToken(
          id: '${token.playerIndex}:${token.index}',
          seatIndex: token.playerIndex,
          stepsTaken: token.stepsTaken,
          colour: token.colour,
        ),
  ];

  void _onBoardTap(TapDownDetails details, double boardSide) {
    final matchId = _matchId;
    if (matchId == null) return;
    final state = ref.read(onlineGameControllerProvider(matchId));
    final snapshot = state.snapshot;
    if (snapshot == null || state.ended != null) return;
    if (!state.canMove) return;
    final tokens = _boardTokens(snapshot);
    final cell = boardSide / 15;
    // A legal tap moves (the offline hit area: full cell, or the
    // token radius) — the controller re-checks legality and the
    // server re-validates, so a stale highlight can never move an
    // illegal token.
    for (final tokenId in state.legalTokenIds) {
      final parts = tokenId.split(':');
      if (parts.length != 2) continue;
      final seat = int.tryParse(parts[0]);
      final index = int.tryParse(parts[1]);
      if (seat == null ||
          index == null ||
          seat < 0 ||
          seat >= snapshot.players.length ||
          index < 0 ||
          index >= snapshot.players[seat].tokens.length) {
        continue;
      }
      final token = snapshot.players[seat].tokens[index];
      final view = BoardToken(
        id: tokenId,
        seatIndex: token.playerIndex,
        stepsTaken: token.stepsTaken,
        colour: token.colour,
      );
      final centre = boardTokenCenter(view, Size(boardSide, boardSide), tokens);
      final offset = details.localPosition - centre;
      if ((offset.dx.abs() <= cell / 2 && offset.dy.abs() <= cell / 2) ||
          offset.distance <= cell * 0.6) {
        ref
            .read(onlineGameControllerProvider(matchId).notifier)
            .moveToken(tokenId);
        return;
      }
    }
    // Any other token tap gets brief feedback and moves nothing.
    final tappedToken = _tokenAt(details.localPosition, boardSide, tokens);
    if (tappedToken != null) {
      _showFeedback(stringsOf(context).gameIllegalTokenMove);
    }
  }

  /// The token under [position] on the board, if any — the same
  /// full-cell + radius hit area as a legal tap.
  BoardToken? _tokenAt(
    Offset position,
    double boardSide,
    List<BoardToken> tokens,
  ) {
    final cell = boardSide / 15;
    for (final token in tokens) {
      final centre = boardTokenCenter(
        token,
        Size(boardSide, boardSide),
        tokens,
      );
      final offset = position - centre;
      if ((offset.dx.abs() <= cell / 2 && offset.dy.abs() <= cell / 2) ||
          offset.distance <= cell * 0.6) {
        return token;
      }
    }
    return null;
  }

  void _onDiceTap() {
    final matchId = _matchId;
    if (matchId == null) return;
    final state = ref.read(onlineGameControllerProvider(matchId));
    final l10n = stringsOf(context);
    if (state.ended != null) return;
    if (state.connectionState != GameSocketConnectionState.connected) {
      _showFeedback(l10n.onlineConnectionDisconnected);
      return;
    }
    if (!state.isMyTurn) {
      _showFeedback(l10n.gameDiceNotYourTurn);
      return;
    }
    if (state.isBusy) {
      _showFeedback(l10n.gameRolling);
      return;
    }
    if (state.snapshot?.phase != TurnPhase.awaitingRoll) {
      _showFeedback(l10n.gameDiceChooseToken);
      return;
    }
    ref.read(onlineGameControllerProvider(matchId).notifier).rollDice();
  }

  /// Brief feedback: a short SnackBar, clearing any already
  /// showing so rapid taps show the latest message, never a queue.
  void _showFeedback(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _showPresenceNotice(OnlinePresenceNotice notice, OnlineGameState state) {
    final l10n = stringsOf(context);
    final name = _nameOf(state, notice.playerId);
    final message = switch (notice.kind) {
      'disconnected' => l10n.onlinePlayerDisconnected(
        name,
        _secondsLeft(notice.graceEndsAt, fallbackSeconds: 60),
      ),
      'reconnected' => l10n.onlinePlayerReconnected(name),
      'forfeited' => l10n.onlinePlayerForfeited(name),
      _ => null,
    };
    if (message != null) _showFeedback(message);
  }

  /// Seconds from now until [deadline], clamped at 0 — the
  /// countdown display. [fallbackSeconds] is the configured grace
  /// (60 s) when the event carried no deadline.
  int _secondsLeft(DateTime? deadline, {required int fallbackSeconds}) {
    if (deadline == null) return fallbackSeconds;
    final seconds = deadline.difference(DateTime.now()).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  /// Leave mid-match: confirm first — leaving forfeits the match
  /// for the leaver (Stage 6, BR-15). On success, pop back to the
  /// lobby (the lobby notifier cleared the room).
  Future<void> _confirmLeave() async {
    final l10n = stringsOf(context);
    final confirmed = await DiceUpDialog.show<bool>(
      context,
      title: l10n.onlineGameForfeitTitle,
      content: Text(l10n.onlineGameForfeitMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.onlineGameForfeitConfirm),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    final left = await ref.read(roomLobbyProvider.notifier).leaveRoom();
    if (!mounted) return;
    if (left) {
      Navigator.of(context).pop();
    } else {
      final error = ref.read(roomLobbyProvider).errorCode;
      final message = onlineErrorMessage(stringsOf(context), error);
      if (message != null) _showFeedback(message);
    }
  }

  /// `match:ended` → the results screen, keeping Home below it
  /// (as the offline game does), with an online [MatchResult].
  /// The standings come from `state.ended` — no data-layer type is
  /// named here; the element type is inferred from the list.
  void _goToResults(BuildContext context, OnlineGameState state) {
    final ended = state.ended;
    if (ended == null) return;
    final snapshot = state.snapshot;
    final finishedAt = DateTime.now();
    final players = List.of(ended.standings)
      ..sort((a, b) => a.seat.compareTo(b.seat));
    final winner =
        players.where((s) => s.rank == 1).firstOrNull ??
        (players.isEmpty ? null : players.first);
    final winnerSeat = winner?.seat ?? snapshot?.winnerIndex ?? 0;
    final winnerColour = _parseColour(winner?.colour, fallbackSeat: winnerSeat);
    // Duration from the snapshot's `startedAt` — the server stamps
    // it Z-suffixed (UTC) since Stage 8, but a snapshot stamped
    // without a zone (legacy rows, or a device in another zone
    // reading a naive stamp as the future) can still make the
    // difference go negative. Then (and only then) fall back to the
    // time since this client first saw the match.
    var duration = Duration.zero;
    final startedAt = snapshot?.startedAt;
    if (startedAt != null) {
      duration = finishedAt.difference(startedAt);
    }
    if (duration.isNegative) {
      final firstSeen = state.firstSnapshotAt;
      duration = firstSeen == null
          ? Duration.zero
          : finishedAt.difference(firstSeen);
      if (duration.isNegative) duration = Duration.zero;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.results,
      ModalRoute.withName(AppRoutes.home),
      arguments: MatchResult(
        winnerSeat: winnerSeat,
        winnerName: winner == null
            ? stringsOf(context).playerName(winnerSeat + 1)
            : _nameOf(state, winner.userId),
        winnerColour: winnerColour,
        players: [
          for (final standing in players)
            MatchResultPlayer(
              seat: standing.seat,
              name: _nameOf(state, standing.userId),
              colour: _parseColour(
                standing.colour,
                fallbackSeat: standing.seat,
              ),
              isAi: false,
              tokensHome: standing.tokensHome,
            ),
        ],
        duration: duration,
        moveCount: snapshot?.moveCount ?? 0,
        finishedAt: finishedAt,
        setup: GameSetup(playerCount: players.length, aiSeats: const {}),
        isOnline: true,
      ),
    );
  }

  /// A seat colour from the server's colour string (`red` /
  /// `green` / `yellow` / `blue`); the seat-order default when the
  /// string is missing or unknown — never a crash on bad data.
  PlayerColour _parseColour(String? raw, {required int fallbackSeat}) {
    if (raw != null) {
      for (final colour in PlayerColour.values) {
        if (colour.name == raw) return colour;
      }
    }
    return PlayerColour.values[fallbackSeat % PlayerColour.values.length];
  }

  void _goHome(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
    }
  }
}

/// The turn banner: whose turn it is, plus the turn timer from
/// `turnEndsAt` (rebuilt once a second by the screen's ticker).
class _TurnBanner extends StatelessWidget {
  const _TurnBanner({required this.state, required this.nameOf});

  final OnlineGameState state;
  final String Function(String userId) nameOf;

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    final snapshot = state.snapshot;
    final currentId = state.turnPlayerId;
    final status = snapshot == null || currentId == null
        ? l10n.onlineGameTitle
        : state.isMyTurn
        ? l10n.onlineGameYourTurn
        : l10n.onlineGameWaitingFor(nameOf(currentId));
    final turnEndsAt = state.turnEndsAt;
    final secondsLeft = turnEndsAt?.difference(DateTime.now()).inSeconds;
    return DiceUpCard(
      child: Row(
        children: [
          Expanded(
            child: Text(status, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (secondsLeft != null && secondsLeft >= 0) ...[
            const SizedBox(width: DiceUpSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DiceUpSpacing.sm,
                vertical: DiceUpSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: secondsLeft <= 10
                    ? DiceUpColors.amberLight
                    : DiceUpColors.surfaceMuted,
                borderRadius: DiceUpSpacing.radiusMdBorder,
              ),
              child: Text(
                l10n.onlineGameTurnTimeLeft(secondsLeft),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The dice row: the dice and the single Roll action on an ivory
/// tray (the offline layout, without the tumble — the server rolls).
class _DiceRow extends StatelessWidget {
  const _DiceRow({
    required this.state,
    required this.onDiceTap,
    required this.onRoll,
  });

  final OnlineGameState state;
  final VoidCallback onDiceTap;
  final VoidCallback onRoll;

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DiceUpSpacing.md,
          vertical: DiceUpSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: DiceUpColors.surface,
          borderRadius: DiceUpSpacing.radiusLgBorder,
          border: Border.all(color: DiceUpColors.border),
          boxShadow: DiceUpShadows.raised,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DiceWidget(
              value: state.lastDiceValue,
              enabled: state.canRoll,
              onTap: onDiceTap,
              showRollableBorder: state.canRoll,
            ),
            const SizedBox(width: DiceUpSpacing.md),
            PrimaryButton(
              label: state.isBusy ? l10n.gameRolling : l10n.gameRollDice,
              onPressed: state.canRoll ? onRoll : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// The player list: colour, name, turn marker, and the presence
/// status — disconnected with its grace countdown, or forfeited.
class _PlayerList extends StatelessWidget {
  const _PlayerList({required this.state, required this.nameOf});

  final OnlineGameState state;
  final String Function(String userId) nameOf;

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    final snapshot = state.snapshot;
    if (snapshot == null) return const SizedBox.shrink();
    // The presence status line for one player, or null when they are
    // live: "Forfeited", or the grace countdown while disconnected.
    // The element type of `state.players` is inferred — no
    // data-layer type is named here.
    String? statusFor(String userId) {
      for (final player in state.players) {
        if (player.userId != userId) continue;
        if (player.result == 'forfeit') {
          return l10n.onlineGamePlayerForfeited;
        }
        if (!player.disconnected) return null;
        final graceEndsAt = player.graceEndsAt;
        final deadline = graceEndsAt == null
            ? null
            : DateTime.tryParse(graceEndsAt);
        final seconds = deadline == null
            ? 60
            : deadline.difference(DateTime.now()).inSeconds;
        return l10n.onlineGamePlayerDisconnected(seconds < 0 ? 0 : seconds);
      }
      return null;
    }

    String userIdOfSeat(int seat) {
      for (final seatView in state.seats) {
        if (seatView.seat == seat) return seatView.userId;
      }
      return '';
    }

    return DiceUpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < snapshot.players.length; i++) ...[
            _PlayerRow(
              name: nameOf(userIdOfSeat(i)),
              colour: snapshot.players[i].colour,
              isCurrent: snapshot.currentPlayerIndex == i,
              isMe: state.localSeat == i,
              status: statusFor(userIdOfSeat(i)),
            ),
            if (i != snapshot.players.length - 1)
              const SizedBox(height: DiceUpSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.name,
    required this.colour,
    required this.isCurrent,
    required this.isMe,
    required this.status,
  });

  final String name;
  final PlayerColour colour;
  final bool isCurrent;
  final bool isMe;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    // Fields do not promote under null checks, so copy to a local
    // before the `statusText != null` branch below.
    final statusText = status;
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: DiceUpColors.forColour(colour),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: DiceUpSpacing.sm),
        Expanded(
          child: Text(
            isMe ? '$name · ${l10n.onlineYou}' : name,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (statusText != null)
          Text(
            statusText,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: DiceUpColors.error),
          )
        else if (isCurrent)
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: DiceUpColors.teal,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}
