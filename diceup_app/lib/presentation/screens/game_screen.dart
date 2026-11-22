import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../domain/engine/game_state.dart';
import '../../domain/engine/player.dart';
import '../../domain/offline_game_controller.dart';
import '../../domain/usecases/match_setup.dart';
import '../navigation/app_routes.dart';
import '../providers/app_providers.dart';
import '../widgets/dice_widget.dart';
import '../widgets/ludo_board.dart';

/// Translates the domain layer's [MatchSetup] back into the
/// presentation layer's [GameSetup] at the boundary (M2.5, the
/// inverse of [_matchSetupOf]). Play Again restarts from the
/// retained setup, so the results screen needs the presentation
/// form: field-for-field identical, same defaults — the engine
/// receives the same seats the match played with.
///
/// Known limitation (M3.2/M3.3 follow-up decision item, NOT fixed
/// here): after a *resumed* match, [OfflineGameController]
/// rebuilds its setup from the restored state, and
/// [LudoGame.fromState] uses the stock ruleset rather than the
/// state's embedded ruleset — so a resumed custom-ruleset match
/// plays under stock rules and Play Again after it restarts under
/// stock rules too. After a *normal* match the setup here is the
/// exact setup the match started with, ruleset included.
GameSetup _gameSetupOf(MatchSetup setup) => GameSetup(
  playerCount: setup.playerCount,
  aiSeats: Map.of(setup.aiSeats),
  names: List.of(setup.names),
  colours: List.of(setup.colours),
  ruleset: setup.ruleset,
);

/// Translates the presentation layer's [GameSetup] into the domain
/// layer's [MatchSetup] at the boundary (M3.2, seam 1). This is the
/// single translation point: the controller takes [MatchSetup] and
/// never sees [GameSetup] (which imports Flutter and cannot live in
/// the domain layer). The resolution is field-for-field identical —
/// [MatchSetup.nameFor]/[colourFor] apply the same defaults as
/// [GameSetup]'s — so the engine receives the same seats the screen
/// built before the extraction.
MatchSetup _matchSetupOf(GameSetup setup) => MatchSetup(
  playerCount: setup.playerCount,
  aiSeats: setup.aiSeats,
  names: setup.names,
  colours: setup.colours,
  ruleset: setup.ruleset,
);

/// Offline match screen (SRS UI-03…UI-05, FR-15…FR-28).
///
/// A thin view over [OfflineGameController] (M3.2, H-07), obtained
/// from the Riverpod composition root (M3.3, D-06) — see
/// [offlineGameControllerProvider]. The screen reads the
/// controller through the provider and renders [GameState]; it
/// keeps only input handling — taps, buttons, dialogs, navigation.
/// All match logic (engine, AI players, timers, legal moves,
/// status, win trigger, snapshot saving, completion recording,
/// resume handling) lives in the controller; the screen never
/// re-derives rules — the engine decides dice, legal moves,
/// captures and the winner; the UI only displays what the engine
/// reports ([MoveResult]) and animates it. The screen holds no
/// copy of the game state: a state change driven through the
/// provider is what it renders.
///
/// The provider owns the controller's lifecycle: the screen's
/// [ref.watch] subscription keeps the `autoDispose` provider alive
/// while the screen is mounted, and the provider disposes the
/// controller (timers cancelled) when the screen leaves. The
/// screen never disposes the controller and never constructs one —
/// the single seam is the provider override (fixed dice, fake
/// feedback, vibration flag in tests; see
/// `test/test_providers.dart`). There is no constructor override
/// for the controller, the dice roller or the feedback service
/// anymore: [initialSetup]/[initialState] are route data, not DI.
/// A fresh navigation to this screen creates a fresh controller
/// (a fresh match per navigation), exactly as the pre-Riverpod
/// screen built a fresh controller per screen.
///
/// Dice honesty: the engine fixes the dice value the moment the
/// player taps Roll, so the value is fixed before the animation; the
/// tumbling animation only displays faces until it settles on
/// the engine's value.
///
/// Animations (M2.7, CON-01): this state is the
/// [TickerProviderStateMixin] host for three [AnimationController]s.
/// The dice tumble runs ~540 ms and cycles the displayed face from
/// the controller's value while the engine's decided value is
/// pending; it ends on the engine value, never a random one. The
/// domain controller keeps its 6 x 90 ms timer as the state-timing
/// authority — the domain layer cannot own a Ticker, and the M2.6
/// pause/settle semantics plus the fake-timer controller tests
/// depend on it — so the two run the same 540 ms and settle
/// together; the timer is no longer what the user *sees*. A move
/// hops its token's rendered centre from the old cell to the new
/// one in ≤250 ms (engine state already final — the hop animates
/// rendering only); the M3 upgrade sequences a multi-cell move one
/// cell at a time, this hop interpolates straight across. Legal
/// tokens pulse once per legal-move appearance via a 1,200 ms
/// controller feeding [pulse] into the painter (not a continuous
/// repeat — see [_pulseController]). All three freeze on pause and
/// are disposed with the screen; input is locked while the tumble
/// or a hop is in flight.
///
/// AI pacing (FR-40): 700–1,199 ms before an AI rolls or moves (D-31).
///
/// Pause (M2.6, FR-27/FR-28; D-10, D-30): the AppBar pause button
/// opens the pause menu (Resume / Restart / Main Menu). Pause is a
/// freeze — the controller cancels the AI and dice timers, so
/// nothing advances behind the menu — and Resume restarts the turn
/// flow exactly once. Restart and Main Menu ask confirmation (the
/// existing dialogs, reused); cancelling either resumes the match.
/// Main Menu always lands on Home (D-30): a single
/// `pushNamedAndRemoveUntil` to Home, whether the match started
/// from setup (Home → Mode → Setup → Game) or from Play Again
/// (Home → Game) — the old AppBar-close pop landed on setup from a
/// first match. System back opens the same pause menu while the
/// match is unfinished ([PopScope] `canPop: false`); it is allowed
/// once the match is finished. Leaving an unfinished match
/// (Main Menu, confirmed) deletes the snapshot and records
/// nothing (D-11, D-12). Results (M2.5, FR-26): when the
/// finished match's completion record is decided, the screen
/// navigates to the results route ([AppRoutes.results]) with a frozen
/// [MatchResult] — the M1.6 win dialog is gone. The results screen
/// owns Play Again / Main Menu; this screen never re-records the
/// completion and never shows a second results presentation.
///
/// Haptics (M1.7, D-32): every completed move vibrates once through
/// [FeedbackService], gated by the persisted `vibration_enabled`
/// setting (default on, D-25). Sound is a named follow-up — there is
/// no audio code here.
///
/// Illegal taps + tappable dice (M2.8, FR-21, M-02): the dice is
/// tappable — [_onDiceTap] rolls under exactly the Roll button's
/// guards, and a tap that cannot roll gets brief feedback (SnackBar
/// + status line, via [OfflineGameController.noteIllegalTap]) with
/// the reason named, never a second roll and never a state change.
/// A tap on a token that cannot move ([_onBoardTap]) gets the
/// plan's message, "That token can't move now"; taps on empty board
/// area stay silent. Feedback never breaks the M2.7 input lock.
///
/// What the user picked in the pause dialog (M2.6). A dismissed
/// dialog (back button, tap outside) yields null and counts as
/// [resume].
enum _PauseChoice { resume, restart, exit }

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, this.initialSetup, this.initialState});

  /// Setup supplied directly (widget tests, deep links). When null, the
  /// setup comes from the route arguments (see [AppRoutes.gameSetupOf]).
  /// Ignored when [initialState] is given.
  final GameSetup? initialSetup;

  /// A restored match to resume (M1.6): the exact [GameState] from
  /// the saved snapshot, via route arguments (see
  /// [AppRoutes.resumedStateOf]) or directly in tests. Takes
  /// precedence over [initialSetup].
  final GameState? initialState;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with TickerProviderStateMixin {
  /// The provider-owned controller this screen observes. Set in
  /// [didChangeDependencies] from
  /// [offlineGameControllerProvider]; the screen removes its
  /// listener on dispose but never disposes the controller — the
  /// `autoDispose` provider does that when this screen's watch
  /// ends.
  OfflineGameController? _controller;

  /// The dice tumble (M2.7): ~540 ms, started when the controller
  /// reports a roll in flight, driving the displayed face from its
  /// value ([_tumbleFace]) until the engine value settles.
  late final AnimationController _diceTumbleController;

  /// The token hop (M2.7): ≤250 ms, interpolating one token's
  /// rendered centre from [_hopFrom] to [_hopTo].
  late final AnimationController _hopController;

  /// The legal-move pulse (M2.7): a 1,200 ms controller that plays
  /// one pulse cycle each time legal moves newly appear (a roll
  /// settles, a move leaves moves legal, a resume) and then rests
  /// at the static ring. It is deliberately NOT a continuously
  /// repeating controller: a running ticker schedules a frame on
  /// every vsync, so `tester.pumpAndSettle()` — which the existing
  /// suite uses throughout, and which M2.7 must not rewrite — never
  /// terminates while one repeats (verified: the repeating form
  /// timed out `game_screen_test.dart` and the characterization
  /// test unmodified). The painter still receives a changing pulse
  /// (0→1→0 over the cycle) and the ring radius/alpha oscillate;
  /// a continuous pulse is a named M3 revisit if the harness ever
  /// moves off `pumpAndSettle`.
  late final AnimationController _pulseController;

  /// The board's per-frame animation source: the pulse and hop
  /// controllers merged, so one [AnimatedBuilder] rebuilds the
  /// [CustomPaint] on either tick.
  late final Listenable _boardAnimation;

  /// The token currently hopping ([BoardToken.id]), or null when no
  /// hop is in flight. The hop's endpoints are board centres in the
  /// current board size, captured when the move was detected.
  String? _hopTokenId;
  Offset? _hopFrom;
  Offset? _hopTo;

  /// The tokens and move count the last build rendered — the
  /// pre-change baseline for hop detection (see [_maybeStartHop]).
  /// Updated at the end of every build; null until the first build.
  List<BoardToken>? _prevTokens;
  int? _prevMoveCount;

  /// The results route is opened once per finished match, when the
  /// controller reports the completion record decided.
  bool _resultsShown = false;

  /// The pause menu is open (M2.6): guards [_showPauseMenu]
  /// against re-entry — system back while the menu is open
  /// dismisses the dialog (which resumes), it must not open a
  /// second menu underneath.
  bool _pauseMenuOpen = false;

  /// Fallback match-start time for the results duration (M2.5): the
  /// state's own [GameState.startedAt] is used first (it survives
  /// resume and restart); this covers states built without one
  /// (hand-built test states), where it is stamped when the match
  /// starts or resumes here.
  DateTime? _matchStartedAt;

  @override
  void initState() {
    super.initState();
    _diceTumbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 540),
    );
    _hopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addStatusListener(_onHopStatus);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addStatusListener(_onPulseStatus);
    _boardAnimation = Listenable.merge([_pulseController, _hopController]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The provider-owned controller (M3.3): `ref.read` here and
    // `ref.watch` in [build] return the same instance — the
    // provider's dependencies are stable while this screen lives —
    // so the match started here is the match the build renders.
    final controller = ref.read(offlineGameControllerProvider);
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_onControllerChanged);
    _controller = controller;
    _resultsShown = false;
    // A new controller means a new match: no animation may act on
    // the old match's state (M3.2 timer-cancellation discipline,
    // applied to animations too).
    _cancelHop();
    _diceTumbleController.reset();
    _pulseController.stop();
    _prevTokens = null;
    _prevMoveCount = null;
    // Start the match before subscribing: the start notification
    // must not call setState during didChangeDependencies.
    final resumed = widget.initialState ?? AppRoutes.resumedStateOf(context);
    if (resumed != null) {
      controller.restoreMatch(resumed);
      // A resumed match's duration runs from its original start
      // (the snapshot's startedAt), not from the resume.
      _matchStartedAt = resumed.startedAt ?? DateTime.now();
    } else {
      controller.startMatch(
        _matchSetupOf(widget.initialSetup ?? AppRoutes.gameSetupOf(context)),
      );
      _matchStartedAt = controller.state.startedAt ?? DateTime.now();
    }
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _diceTumbleController.dispose();
    _hopController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// The controller changed (a roll settled, a move applied, a
  /// completion record decided, an AI step ran): detect a move to
  /// hop, sync the animations to the new state, rebuild, and
  /// navigate to the results screen once the finished match's
  /// record is decided.
  void _onControllerChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller != null) {
      _maybeStartHop(controller);
      _syncAnimationState(controller);
    }
    setState(() {});
    _maybeShowResults();
  }

  /// Starts a token hop when exactly one move was just applied
  /// (M2.7): the move count rose by exactly one since the last
  /// build, and one token's progress increased. Start, restore and
  /// restart reset (or jump) the count, so they never hop; a
  /// capture's returning token snaps to the yard — its smooth
  /// return is the M3 capture animation, not this hop. The moved
  /// token's rendered centre interpolates from its pre-move cell
  /// ([_prevTokens]) to its post-move cell; the engine state is
  /// already final, so the hop can never change the game.
  void _maybeStartHop(OfflineGameController controller) {
    final prevCount = _prevMoveCount;
    final newCount = controller.state.moveCount;
    if (prevCount == null || newCount != prevCount + 1) return;
    if (controller.isPaused) return;
    final prevTokens = _prevTokens;
    if (prevTokens == null) return;
    final tokens = _boardTokens();
    final prevById = {for (final token in prevTokens) token.id: token};
    BoardToken? from;
    BoardToken? to;
    for (final token in tokens) {
      final old = prevById[token.id];
      if (old != null && token.stepsTaken > old.stepsTaken) {
        from = old;
        to = token;
        break;
      }
    }
    if (from == null || to == null) return;
    final side = _boardSide(context);
    final size = Size(side, side);
    final hopFrom = boardTokenCenter(from, size, prevTokens);
    final hopTo = boardTokenCenter(to, size, tokens);
    if (hopFrom == hopTo) return;
    // A hop already in flight (a move landing while the previous
    // hop still renders) is replaced, not overlapped: the old hop
    // snaps to its destination, which is the engine position.
    _hopTokenId = to.id;
    _hopFrom = hopFrom;
    _hopTo = hopTo;
    _hopController.forward(from: 0.0);
  }

  /// A hop finished: the token is drawn at its engine position
  /// from here on (the painter's computed centre is the same
  /// point), and input unlocks.
  void _onHopStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _hopTokenId = null;
    _hopFrom = null;
    _hopTo = null;
    if (mounted) setState(() {});
  }

  /// A pulse cycle finished: back to the static ring (pulse 0)
  /// until legal moves newly appear again. The reset is what makes
  /// the pulse finite — without it the controller would sit at 1.0
  /// and the next legal-move state could not tell a fresh cycle
  /// from a finished one.
  void _onPulseStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _pulseController.reset();
  }

  /// Cancels a hop in flight, leaving the token drawn at its
  /// engine position. Used on pause (the hop's destination is
  /// already the final state) and on controller swaps.
  void _cancelHop() {
    if (_hopTokenId == null) return;
    _hopTokenId = null;
    _hopFrom = null;
    _hopTo = null;
    _hopController.stop();
  }

  /// Syncs the three animation controllers to the controller's
  /// state after every notification (M2.7). The tumble runs while
  /// a roll is in flight and resets when it settles; the pulse
  /// runs only while legal moves exist; on pause everything stops
  /// where it is — the tumble's engine value is kept in the
  /// controller and settles on resume, the hop's destination is
  /// already the engine position, so freezing is just stopping.
  void _syncAnimationState(OfflineGameController controller) {
    if (controller.isPaused) {
      _diceTumbleController.stop();
      _pulseController.stop();
      _cancelHop();
      return;
    }
    if (controller.rolling) {
      if (!_diceTumbleController.isAnimating) {
        _diceTumbleController.forward(from: 0.0);
      }
    } else {
      _diceTumbleController.reset();
    }
    // Stopping the pulse when nothing is legal also stops the
    // board repainting every frame while the match waits for a roll.
    // A cycle plays once per legal-move appearance (see
    // [_pulseController]): while it runs, no new cycle starts; once
    // it completes and resets, the next notification restarts it —
    // and no notification arrives while a human simply thinks, so
    // the ring rests static between turns.
    if (controller.legalMoves.isNotEmpty && !controller.isFinished) {
      if (!_pulseController.isAnimating) {
        _pulseController.forward(from: 0.0);
      }
    } else {
      _pulseController.stop();
    }
  }

  /// The dice face shown mid-tumble (M2.7): the tumble value cycles
  /// 1..6 as the 540 ms controller runs. Only read while rolling —
  /// once the roll settles the screen shows the engine value.
  int get _tumbleFace => ((_diceTumbleController.value * 6).floor() % 6) + 1;

  /// The legal-move pulse (M2.7): a smooth 0..1..0 oscillation
  /// over each 1,200 ms repeat, or 0 when the pulse is stopped.
  double get _pulseValue {
    if (!_pulseController.isAnimating) return 0.0;
    return (math.sin(_pulseController.value * 2 * math.pi) + 1) / 2;
  }

  /// The hopping token's rendered centre right now (M2.7): the
  /// eased interpolation between its pre-move and post-move cells,
  /// or null when no hop is in flight.
  Offset? get _hopCenter {
    final from = _hopFrom;
    final to = _hopTo;
    if (_hopTokenId == null || from == null || to == null) return null;
    return Offset.lerp(
      from,
      to,
      Curves.easeOut.transform(_hopController.value),
    )!;
  }

  /// Navigates to the results screen once, when the match is finished
  /// and its completion record has been decided (recorded, or failed —
  /// the results screen reports the failure, never a success).
  ///
  /// Navigation is `pushNamedAndRemoveUntil` keeping only Home below
  /// (M2.5, D-30): the stack becomes Home → Results, so the system
  /// back button lands on Home and there is no finished game screen
  /// underneath to pop back to — and no counted `pop()` anywhere,
  /// so the old double-pop (dialog, then game screen → setup) cannot
  /// recur. A resumed finished match reaches here through the same
  /// path (the controller retries its record on restore, M3.2); the
  /// [_resultsShown] guard and the controller's exactly-once guard
  /// together mean one record and one navigation, however many
  /// notifications arrive.
  void _maybeShowResults() {
    final controller = _controller;
    if (controller == null ||
        !controller.isFinished ||
        controller.completionPending ||
        _resultsShown) {
      return;
    }
    final winner = controller.winner;
    final setup = controller.currentSetup;
    if (winner == null || setup == null) return;
    _resultsShown = true;
    final finishedAt = DateTime.now();
    final startedAt = controller.state.startedAt ?? _matchStartedAt;
    final duration = startedAt == null
        ? Duration.zero
        : finishedAt.isAfter(startedAt)
        ? finishedAt.difference(startedAt)
        : Duration.zero;
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.results,
      ModalRoute.withName(AppRoutes.home),
      arguments: MatchResult(
        winnerSeat: winner.index,
        winnerName: winner.name,
        winnerColour: winner.colour,
        players: [
          for (final player in controller.state.players)
            MatchResultPlayer(
              seat: player.index,
              name: player.name,
              colour: player.colour,
              isAi: player.isAi,
            ),
        ],
        duration: duration,
        moveCount: controller.state.moveCount,
        finishedAt: finishedAt,
        setup: _gameSetupOf(setup),
        completionFailed: controller.completionFailed,
      ),
    );
  }

  /// One light haptic per completed move (M1.7, D-32) is wired in
  /// the composition root ([offlineGameControllerProvider]'s
  /// `onMoveApplied`), not here — the screen never touches
  /// haptics directly.

  void _onBoardTap(TapDownDetails details, double boardSide) {
    final controller = _controller!;
    if (controller.isFinished || controller.isPaused) {
      return;
    }
    final tokens = _boardTokens();
    final cell = boardSide / 15;
    // A legal tap still moves (M2.3 behaviour, unchanged): the
    // legal moves are hit-tested first, in engine order, so a tap
    // that used to move a token still moves exactly that token —
    // the feedback path below only runs when no legal move was
    // taken.
    if (!controller.rolling &&
        !_hopController.isAnimating &&
        controller.state.phase == TurnPhase.awaitingMove &&
        !controller.state.currentPlayer.isAi) {
      for (final move in controller.legalMoves) {
        final token = controller.state.currentPlayer.tokens[move.tokenIndex];
        final view = BoardToken(
          id: '${token.playerIndex}:${token.index}',
          seatIndex: token.playerIndex,
          stepsTaken: token.stepsTaken,
          colour: token.colour,
        );
        final centre = boardTokenCenter(
          view,
          Size(boardSide, boardSide),
          tokens,
        );
        final offset = details.localPosition - centre;
        // D-09: board tokens are exempt from the 48 dp rule, with the
        // full-cell hit area as the mitigation — any tap inside the
        // token's cell selects it. The pre-existing radius
        // (cell x 0.6) is kept as well, so a tap that used to land
        // (e.g. just outside the cell along an axis) still lands.
        if ((offset.dx.abs() <= cell / 2 && offset.dy.abs() <= cell / 2) ||
            offset.distance <= cell * 0.6) {
          unawaited(controller.applyMove(move));
          return;
        }
      }
    }
    // Illegal-tap feedback (M2.8, FR-21; SDD §6.5: "a tap on any
    // other token is ignored with brief feedback"): a tap on a
    // token that cannot move right now — a non-legal token of the
    // current player, an opponent's token, a token tapped during
    // the AI's turn, or one tapped mid-tumble — gets the SnackBar
    // + status update and changes nothing. Taps on empty board
    // area stay silent: the plan requires feedback for token taps
    // only.
    if (_tokenAt(details.localPosition, boardSide, tokens) != null) {
      _showIllegalTapFeedback("That token can't move now");
    }
  }

  /// The token under [position] on the board, if any — the same
  /// full-cell + radius hit area as a legal tap (M2.3, D-09).
  /// Only answers "is there a token here", never which move it is;
  /// the legal path above decides that first.
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

  /// Tapping the dice rolls exactly as the Roll button does (M2.8,
  /// FR-21 / UC-01 step 4): the same guards — human turn, awaiting
  /// a roll, not rolling, not paused, no hop in flight — and the
  /// controller's own guards are the second line of defence, so a
  /// tap racing the tumble start (a rapid double-tap, or a dice tap
  /// right after the button) is ignored, never queued, and rolls
  /// exactly once. A tap that cannot roll gets the same brief
  /// feedback as an illegal board tap, with the reason named, and
  /// the game state is untouched. Finished / paused taps are
  /// silent: the results screen (finished) and the pause dialog
  /// (paused) already own the screen, so no feedback path exists.
  void _onDiceTap() {
    final controller = _controller;
    if (controller == null || controller.isFinished || controller.isPaused) {
      return;
    }
    final state = controller.state;
    if (!state.currentPlayer.isHuman) {
      _showIllegalTapFeedback("It's not your turn yet.");
      return;
    }
    if (controller.rolling) {
      _showIllegalTapFeedback('Wait for the dice to settle.');
      return;
    }
    if (_hopController.isAnimating) {
      _showIllegalTapFeedback('Wait for the move to finish.');
      return;
    }
    if (state.phase != TurnPhase.awaitingRoll) {
      // Already rolled: the next action is a token move, not a roll.
      _showIllegalTapFeedback('Choose a token to move.');
      return;
    }
    controller.rollDice();
  }

  /// Brief illegal-tap feedback (M2.8, M-02; FR-21, SDD §6.5):
  /// the message appears in the status line (via the controller —
  /// the screen holds no copy of the status) and as a short
  /// SnackBar. Game state is untouched: no roll, no move, no turn
  /// change — the next roll or move overwrites the status as usual,
  /// and the feedback never breaks the M2.7 input lock or lets a
  /// second action through. No haptic: the plan names the SnackBar
  /// + status only, and haptics are reserved for completed moves
  /// (M1.7, D-32). Any SnackBar already showing is cleared first,
  /// so rapid illegal taps show the latest message, never a queue.
  void _showIllegalTapFeedback(String message) {
    final controller = _controller;
    controller?.noteIllegalTap(message);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  List<BoardToken> _boardTokens() {
    final state = _controller!.state;
    return [
      for (final player in state.players)
        for (final token in player.tokens)
          BoardToken(
            id: '${token.playerIndex}:${token.index}',
            seatIndex: token.playerIndex,
            stepsTaken: token.stepsTaken,
            colour: player.colour,
          ),
    ];
  }

  // -- Pause menu + exit --------------------------------------------------

  /// The pause menu (M2.6, FR-27/FR-28; D-10): Resume / Restart /
  /// Main Menu. Opening it freezes the match first
  /// ([OfflineGameController.pause] cancels the AI and dice
  /// timers, so nothing advances behind the menu), and every way
  /// out of it leaves the match in a defined state: Resume (or a
  /// plain dismissal) resumes it, Restart/Exit ask confirmation
  /// and resume it when cancelled, and a confirmed Restart/Exit
  /// acts and never resumes afterwards. The menu is a dialog, not
  /// a bottom sheet — the same [AlertDialog] shape as the
  /// confirmation dialogs, so the 48 dp action buttons and the
  /// back-button behaviour match the rest of the app.
  Future<void> _showPauseMenu() async {
    final controller = _controller;
    if (controller == null ||
        controller.isFinished ||
        controller.isPaused ||
        _pauseMenuOpen) {
      return;
    }
    _pauseMenuOpen = true;
    controller.pause();
    final choice = await showDialog<_PauseChoice>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('Paused'),
        content: const Text('Take a break — the match is frozen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_PauseChoice.exit),
            child: const Text('Main Menu'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_PauseChoice.restart),
            child: const Text('Restart'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_PauseChoice.resume),
            child: const Text('Resume'),
          ),
        ],
      ),
    );
    _pauseMenuOpen = false;
    if (!mounted) return;
    switch (choice) {
      case _PauseChoice.restart:
        // A cancelled restart resumes; a confirmed one restarts
        // (which clears the paused flag itself).
        if (!await _confirmRestart()) controller.resume();
      case _PauseChoice.exit:
        // A cancelled exit resumes; a confirmed one leaves for
        // Home and never resumes afterwards.
        if (!await _confirmExit()) controller.resume();
      case _PauseChoice.resume:
      case null:
        controller.resume();
    }
  }

  /// Restart, after confirmation (M2.6): the existing restart
  /// dialog, reused from the pause menu. Returns true only when
  /// the match was actually restarted.
  Future<bool> _confirmRestart() async {
    final controller = _controller!;
    final restart = await ConfirmationDialog.show(
      context,
      title: 'Restart match?',
      message: 'The current match will be discarded.',
      confirmLabel: 'Restart',
    );
    if (!restart || !mounted) return false;
    // Restart discards the current match (D-11/D-12): its snapshot
    // is deleted before the new match starts, and nothing is
    // recorded. The new match starts unpaused.
    await controller.restart();
    return mounted;
  }

  /// Leave for Home, after confirmation (M2.6, D-30): the existing
  /// exit dialog, reused from the pause menu. Returns true only
  /// when the match was actually left. The destination is always
  /// Home — one `pushNamedAndRemoveUntil`, whether this match was
  /// reached from setup (Home → Mode → Setup → Game) or from Play
  /// Again (Home → Game): the old AppBar-close pop landed on
  /// setup from a first match. A fresh Home is pushed (rather than
  /// popping to an existing one) so the landing is identical from
  /// every entry path, including a deep link straight to the game
  /// route; the fresh Home is safe because it re-checks snapshot
  /// existence before offering resume (M2.6), so it never re-offers
  /// the snapshot this exit just deleted.
  Future<bool> _confirmExit() async {
    final controller = _controller!;
    final leave = await ConfirmationDialog.show(
      context,
      title: 'Leave the match?',
      message: controller.isFinished
          ? 'This match is over.'
          : 'Your progress in this match will be lost.',
      confirmLabel: 'Leave',
    );
    if (!leave || !mounted) return false;
    // Clean exit (D-11/D-12): an unfinished match is deleted from
    // the snapshot store and records nothing — no history row, no
    // statistics, no saved match. A finished match's snapshot is
    // already gone, so nothing is deleted.
    if (!controller.isFinished) await controller.discardSnapshot();
    if (!mounted) return false;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
    return true;
  }

  // -- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // The subscription that keeps the `autoDispose` controller
    // provider alive while this screen is mounted: when the screen
    // leaves, the provider disposes the controller (timers
    // cancelled). This is the same instance [didChangeDependencies]
    // started the match on — the provider's dependencies are stable
    // while the screen lives — so the build renders exactly what
    // the provider-owned controller reports, with no second copy
    // of the game state anywhere in the screen.
    final controller = ref.watch(offlineGameControllerProvider);
    final state = controller.state;
    final current = state.currentPlayer;
    // Input stays locked while a hop renders (M2.7): the engine
    // state is already final, but a second move landing on top of
    // the hop would overlap two animations. The hop is ≤250 ms.
    final hopInFlight = _hopController.isAnimating;
    final isHumanTurn =
        current.isHuman &&
        state.phase != TurnPhase.finished &&
        !controller.rolling &&
        !controller.isPaused &&
        !hopInFlight;
    // A roll is available exactly when the Roll button is enabled
    // (M2.8): the dice shares this condition, so the two affordances
    // can never disagree about whether a tap rolls.
    final canRoll = isHumanTurn && state.phase == TurnPhase.awaitingRoll;
    final boardSide = _boardSide(context);
    // Semantics (M2.9, NFR-08): the board is one labelled node —
    // "Ludo board. <name>'s turn, N legal moves" — updated on every
    // build from the controller state, so a screen reader always
    // hears whose turn it is and how many moves are legal. A
    // finished match names the winner instead. Per-token semantics
    // nodes are out of scope this pass (remediation plan M2.9):
    // the tokens are canvas-painted, not widgets, and no overlay
    // nodes are faked — recorded as a follow-up, not claimed here.
    final boardLabel = controller.isFinished
        ? (controller.winner == null
              ? 'Ludo board. Match finished'
              : 'Ludo board. ${controller.winner!.name} won the match')
        : "Ludo board. ${current.name}'s turn, "
              '${controller.legalMoves.length} legal '
              '${controller.legalMoves.length == 1 ? 'move' : 'moves'}';

    // The baseline for hop detection (M2.7): the tokens and move
    // count this build renders. [_onControllerChanged] diffs
    // against these *before* this build runs, so it always sees
    // the pre-change list.
    _prevTokens = _boardTokens();
    _prevMoveCount = state.moveCount;

    // System back (M2.6, FR-28): while the match is unfinished the
    // back button opens the pause menu — the same flow as the
    // AppBar pause button — instead of popping. The pause menu's
    // Main Menu is the only way out, and it asks confirmation
    // first; a pop here used to delete the snapshot with no
    // confirmation at all. Once the match is finished the pop is
    // allowed (the results screen has already replaced this
    // screen by then in practice; the guard is belt-and-braces).
    // While the pause dialog itself is open, back dismisses the
    // dialog, which resumes the match — it never reaches this
    // scope, because the dialog route is on top.
    return PopScope(
      canPop: controller.isFinished,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_showPauseMenu());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('DiceUp'),
          leading: IconButton(
            icon: const Icon(Icons.pause),
            tooltip: 'Pause',
            onPressed: controller.isFinished ? null : _showPauseMenu,
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: DiceUpSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TurnBanner(
                  player: current,
                  status: controller.status,
                  rolling: controller.rolling,
                ),
                const SizedBox(height: DiceUpSpacing.md),
                Center(
                  child: Semantics(
                    label: boardLabel,
                    child: GestureDetector(
                      onTapDown: (details) => _onBoardTap(details, boardSide),
                      // The board repaints on its own (M2.7): the
                      // pulse and hop animate inside the
                      // [RepaintBoundary], so a pulse tick repaints
                      // the board and nothing else. The painted board
                      // itself contributes no semantics nodes
                      // (CustomPaint draws, it does not label) — the
                      // Semantics wrapper above is the board's only
                      // node, so nothing decorative leaks through.
                      child: RepaintBoundary(
                        child: SizedBox(
                          width: boardSide,
                          height: boardSide,
                          child: AnimatedBuilder(
                            animation: _boardAnimation,
                            builder: (context, _) => CustomPaint(
                              painter: LudoBoardPainter(
                                tokens: _boardTokens(),
                                legalTokenIds: controller.legalMoves
                                    .map(
                                      (m) => '${m.playerIndex}:${m.tokenIndex}',
                                    )
                                    .toSet(),
                                currentSeat: state.currentPlayerIndex,
                                pulse: _pulseValue,
                                hopTokenId: _hopTokenId,
                                hopCenter: _hopCenter,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: DiceUpSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The tumble face comes from the animation
                    // controller while rolling (M2.7); once the
                    // roll settles the dice shows the engine value.
                    // The dice is tappable (M2.8): tapping it rolls
                    // exactly as the Roll button does, under the
                    // same guards — and a tap that cannot roll gets
                    // brief feedback instead of silence.
                    AnimatedBuilder(
                      animation: _diceTumbleController,
                      builder: (context, _) => DiceWidget(
                        value: controller.rolling
                            ? _tumbleFace
                            : controller.displayedRoll,
                        rolling: controller.rolling,
                        enabled: canRoll,
                        onTap: _onDiceTap,
                      ),
                    ),
                    const SizedBox(width: DiceUpSpacing.lg),
                    PrimaryButton(
                      label: controller.rolling ? 'Rolling…' : 'Roll dice',
                      onPressed: canRoll ? controller.rollDice : null,
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
    final width =
        MediaQuery.of(context).size.width -
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
    // Semantics (M2.9, NFR-08): the banner is announced as
    // "<name>'s turn" — the plan's label. The name and status
    // texts stay readable as child nodes (the status line is the
    // illegal-tap feedback channel, so it must never be hidden),
    // and the avatar contributes its own name + shape + colour
    // node (see [PlayerAvatar]).
    return Semantics(
      label: "${player.name}'s turn",
      child: DiceUpCard(
        child: Row(
          children: [
            PlayerAvatar(
              name: player.name,
              seatIndex: player.index,
              // The ring follows the player's *chosen* colour (M2.2),
              // not the seat-order colour — after a swap they differ.
              colour: player.colour,
            ),
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
          // The chip identifies the player by avatar (white disc,
          // navy initial, colour ring, shape marker — M2.4, D-27),
          // never by a colour-only dot.
          PlayerAvatar(
            name: player.name,
            seatIndex: player.index,
            colour: player.colour,
            radius: 12,
          ),
          const SizedBox(width: DiceUpSpacing.xs),
          Flexible(
            child: Text(
              '${player.name} · Home ${player.tokensHome}/4',
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
