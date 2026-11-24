import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accessibility/reduced_motion.dart';
import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_decor.dart';
import '../../core/design_system/diceup_shadows.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../domain/engine/game_state.dart';
import '../../domain/engine/player.dart';
import '../../domain/offline_game_controller.dart';
import '../../domain/usecases/match_setup.dart';
import '../../l10n/app_strings.dart';
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
/// Animations (M2.7 foundation, M3 premium §4): this state is the
/// [TickerProviderStateMixin] host for six [AnimationController]s.
/// The dice tumble runs ~540 ms and cycles the displayed face from
/// the controller's value while the engine's decided value is
/// pending; it ends on the engine value, never a random one. The
/// domain controller keeps its 6 x 90 ms timer as the state-timing
/// authority — the domain layer cannot own a Ticker, and the M2.6
/// pause/settle semantics plus the fake-timer controller tests
/// depend on it — so the two run the same 540 ms and settle
/// together; the timer is no longer what the user *sees*. The
/// tumble is finished in M3: a ~120 ms wind-up dip, a shake while
/// cycling, and one damped settle wobble, all inside the 540 ms
/// budget; a rollable teal border marks the dice while a roll is
/// available. A move steps its token one cell at a time (~110 ms
/// per cell, ~250 ms minimum, ~600 ms cap — Q1), each step a small
/// hop with a lift, corners turning naturally because the path
/// follows cells; a capture is sequenced after the mover settles
/// (lift → shrink/fade → arc to the yard → pop-in, ~600 ms) and
/// the mover settles slightly larger on a capturing move. The
/// moved token then carries a fading teal ring (~1.5 s, §2.2.6).
/// Legal tokens pulse once per legal-move appearance via a 1,200 ms
/// controller feeding [pulse] into the painter (not a continuous
/// repeat — see [_pulseController]); the same one-shot pulse drives
/// the three-dot AI-thinking indicator in the current player's chip
/// (Q10 — the banner spinner is gone). An illegal tap shakes the
/// tapped token (or the dice) for ~150 ms. All six freeze on pause
/// and resume from where they froze (Q2 — pause is a freeze, D-10;
/// the M2.7 hop used to cancel on pause, superseded here), and are
/// disposed with the screen; input is locked while the tumble or a
/// move/capture sequence is in flight. With reduced motion
/// (Android's `disableAnimations` or iOS's Reduce Motion feature)
/// every sequence collapses to an instant settle: the engine state
/// is already final, so nothing breaks. The engine decides, the
/// animation performs — an animation can never change the game.
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

/// Layout (M2.12, NFR-09; Stage 2 redesign, F8): on short screens (viewport height
/// < 600 dp — the 320x568 worst case) the chrome around the board
/// compacts so the board + dice row + Roll button are visible at
/// first paint without scrolling: the turn banner uses tighter
/// card padding and a smaller avatar (its status then wraps to two
/// lines instead of three), the gaps above/below the board shrink
/// from 16 to 4 dp, and the dice renders at 56 dp instead of 64 dp
/// (still above the 48 dp control minimum). Nothing else changes
/// — the board side keeps its width rule ([_boardSide]: 280 dp at
/// 320 dp wide, the plan §6.1 criterion) and the column padding is
/// untouched. Taller screens render the full layout exactly as
/// before, dice at 64 dp. Since Stage 2 the board + dice row are
/// pinned at the top of a fixed column (only the player chips +
/// safe-cells hint below them scroll), and the board side is also
/// height-aware so the dice row stays above the fold on short/wide
/// viewports.
class _GameScreenState extends ConsumerState<GameScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// The provider-owned controller this screen observes. Set in
  /// [didChangeDependencies] from
  /// [offlineGameControllerProvider]; the screen removes its
  /// listener on dispose but never disposes the controller — the
  /// `autoDispose` provider does that when this screen's watch
  /// ends.
  OfflineGameController? _controller;

  /// The dice tumble (M2.7, finished in M3): ~540 ms, started when
  /// the controller reports a roll in flight, driving the displayed
  /// face from its value ([_tumbleFace]) until the engine value
  /// settles. The same controller drives the wind-up, shake and
  /// settle wobble (see [_diceMotion]).
  late final AnimationController _diceTumbleController;

  /// The per-cell move sequence (M3 premium, §2.2/Q1): ONE
  /// controller for the whole sequence, whose value maps onto the
  /// step polyline ([_stepCenter]/[_stepScale] derive the segment
  /// and the within-segment progress from it). A per-segment
  /// restart was tried first and dropped: when a controller
  /// completes its ticker stops, so `forward(from: 0.0)` from the
  /// status listener only ticks on the NEXT frame — each segment
  /// boundary slipped a frame (a 6-step move read one segment
  /// behind at every 100 ms boundary in tests). The whole sequence
  /// is ~110 ms per cell, ~250 ms minimum, ~600 ms cap.
  late final AnimationController _stepController;

  /// The capture return (M3 premium, §2.3/Q6): ~600 ms, lift →
  /// shrink/fade → arc to the yard → pop-in, sequenced after the
  /// mover's steps finish.
  late final AnimationController _captureController;

  /// The last-moved ring fade (M3 premium, §2.2.6): ~1,500 ms,
  /// 1.0 → 0.0 opacity after a move settles.
  late final AnimationController _lastMovedController;

  /// The illegal-tap shake (M3 premium, §2.5.4): ~150 ms, two
  /// oscillations of ±1.5 dp on the tapped token or the dice.
  late final AnimationController _shakeController;

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
  /// moves off `pumpAndSettle`. The same one-shot cycle drives the
  /// AI-thinking dots (M3, Q10): while an AI turn is pending the
  /// pulse is (re)started, so the dots animate for the ~700–1,199 ms
  /// the AI takes to act.
  late final AnimationController _pulseController;

  /// The board's per-frame animation source: all five board
  /// controllers merged, so one [AnimatedBuilder] rebuilds the
  /// [CustomPaint] on any tick. The dice has its own merged source
  /// ([_diceAnimation]) so a tumble tick never rebuilds the board
  /// (M3.8, NFR-02).
  late final Listenable _boardAnimation;

  /// The dice's per-frame animation source: tumble + shake only.
  late final Listenable _diceAnimation;

  /// The token currently stepping ([BoardToken.id]), or null when no
  /// step sequence is in flight. [_stepPath] is the full path of
  /// rendered centres — the pre-move cell, then one centre per
  /// intermediate step, ending at the post-move cell. The segment
  /// in flight is derived from [_stepController]'s value
  /// ([_stepSegmentIndex]/[_stepSegmentFraction]), never stored:
  /// storing it per segment cost a frame per restart (see the
  /// [_stepController] doc). [_stepIsCapture] marks a capturing
  /// move, whose final step settles slightly larger.
  String? _stepTokenId;
  List<Offset> _stepPath = const [];
  bool _stepIsCapture = false;
  Duration _stepTotalDuration = const Duration(milliseconds: 110);

  /// The mover's id for the last-moved ring: [_stepTokenId] is
  /// cleared when the steps settle (before a capture runs), so the
  /// ring id is carried here until [_finishSequence] consumes it.
  String? _sequenceMoverId;

  /// The capture in flight, if any: the captured token's id and the
  /// arc endpoints (its pre-move cell centre and its yard-slot
  /// centre), captured when the move was detected. [_captureActive]
  /// is true from the mover's settle until the pop-in finishes;
  /// [_captureArcHeight] is the arc's peak lift in dp.
  bool _captureActive = false;
  String? _captureTokenId;
  Offset? _captureFromCentre;
  Offset? _captureToCentre;
  double _captureArcHeight = 0.0;
  BoardToken? _captureFromToken;
  BoardToken? _captureToToken;

  /// A move or capture sequence is in flight (steps and/or capture),
  /// including while frozen by pause. This — not any single
  /// controller's `isAnimating` — is the input lock: a controller
  /// stopped by pause reports `isAnimating == false` while its
  /// sequence is still unfinished.
  bool _sequenceActive = false;

  /// The id of the token whose move just settled, for the
  /// last-moved ring, or null when no ring is shown. Set when a
  /// sequence finishes (or immediately, with reduced motion) and
  /// cleared when the ring fades out or the next sequence starts.
  String? _lastMovedTokenId;

  /// The illegally tapped token's id while its shake runs, or null.
  String? _shakeTokenId;

  /// The dice is shaking (an illegal dice tap) while true.
  bool _shakeDice = false;

  /// The dice face shown while a roll is tumbling under reduced
  /// motion: the last settled face, frozen — the tumble is skipped,
  /// so no face cycles. Updated on every controller notification
  /// while not rolling.
  int? _preRollFace;

  /// The tokens and move count the last build rendered — the
  /// pre-change baseline for move detection (see
  /// [_maybeStartSequence]). Updated at the end of every build;
  /// null until the first build.
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
    WidgetsBinding.instance.addObserver(this);
    _diceTumbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 540),
    );
    _stepController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 110),
          )
          ..addStatusListener(_onStepStatus)
          ..addListener(_onStepValue);
    _captureController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addStatusListener(_onCaptureStatus);
    _lastMovedController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..addStatusListener(_onLastMovedStatus);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addStatusListener(_onShakeStatus);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addStatusListener(_onPulseStatus);
    _boardAnimation = Listenable.merge([
      _pulseController,
      _stepController,
      _captureController,
      _lastMovedController,
      _shakeController,
    ]);
    _diceAnimation = Listenable.merge([
      _diceTumbleController,
      _shakeController,
    ]);
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
    _cancelSequence();
    _diceTumbleController.reset();
    _pulseController.stop();
    _preRollFace = null;
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
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    _diceTumbleController.dispose();
    _stepController.dispose();
    _captureController.dispose();
    _lastMovedController.dispose();
    _shakeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (!mounted) return;
    if (isReducedMotion(context)) {
      _cancelSequence();
      _diceTumbleController.stop();
    }
    setState(() {});
  }

  /// The controller changed (a roll settled, a move applied, a
  /// completion record decided, an AI step ran): detect a move to
  /// animate, sync the animations to the new state, rebuild, and
  /// navigate to the results screen once the finished match's
  /// record is decided.
  void _onControllerChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller != null) {
      if (!controller.rolling) _preRollFace = controller.displayedRoll;
      _maybeStartSequence(controller);
      _syncAnimationState(controller);
    }
    setState(() {});
    _maybeShowResults();
  }

  /// Starts a per-cell step sequence (and, after it, a capture
  /// return) when exactly one move was just applied (M3 premium,
  /// §2.2/Q1, §2.3/Q6): the move count rose by exactly one since
  /// the last build, and one token's progress increased. Start,
  /// restore and restart reset (or jump) the count, so they never
  /// animate; a capture is detected by diff, not by engine data —
  /// a token that was on the board and is now in the yard, other
  /// than the mover, was captured by this move. The engine state is
  /// already final, so the sequence can never change the game.
  ///
  /// With reduced motion the sequence is skipped entirely: the
  /// token is already at its engine position, and only the
  /// last-moved ring is set (static, no fade).
  void _maybeStartSequence(OfflineGameController controller) {
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
    BoardToken? capturedFrom;
    BoardToken? capturedTo;
    for (final token in tokens) {
      final old = prevById[token.id];
      if (old != null &&
          old.stepsTaken > 0 &&
          token.stepsTaken == 0 &&
          token.id != to.id) {
        capturedFrom = old;
        capturedTo = token;
        break;
      }
    }
    // A sequence already in flight (a move landing while the
    // previous sequence still renders) is finished instantly and
    // replaced, not overlapped: the old token snaps to its engine
    // position, which is where it already is.
    _finishSequenceInstantly();
    final side = _boardSide(context);
    final size = Size(side, side);
    // The path: the pre-move centre, then one centre per
    // intermediate step, ending at the post-move cell. Corners turn
    // naturally because the path follows cells. Each intermediate
    // centre is computed with the moving token at that step, so
    // stacking offsets match the painter's.
    final path = <Offset>[boardTokenCenter(from, size, prevTokens)];
    for (var step = from.stepsTaken + 1; step <= to.stepsTaken; step++) {
      final probe = BoardToken(
        id: to.id,
        seatIndex: to.seatIndex,
        stepsTaken: step,
        colour: to.colour,
      );
      final atStep = [
        for (final token in tokens) token.id == to.id ? probe : token,
      ];
      path.add(boardTokenCenter(probe, size, atStep));
    }
    if (capturedFrom != null && capturedTo != null) {
      _captureFromCentre = boardTokenCenter(capturedFrom, size, prevTokens);
      _captureToCentre = boardTokenCenter(capturedTo, size, tokens);
      _captureArcHeight = side / 15 * 1.5;
    }
    _captureFromToken = capturedFrom;
    _captureToToken = capturedTo;
    if (isReducedMotion(context)) {
      _lastMovedController.stop();
      _lastMovedTokenId = to.id;
      return;
    }
    _stepTokenId = to.id;
    _sequenceMoverId = to.id;
    _stepPath = path;
    _stepIsCapture = capturedFrom != null;
    _sequenceActive = true;
    _lastMovedTokenId = null;
    // ~110 ms per cell, ~250 ms minimum, ~600 ms cap (Q1). The
    // controller runs the whole sequence at once; the segment
    // boundaries fall at value = segment / steps, so a segment
    // boundary is hit exactly at its pump time.
    final steps = to.stepsTaken - from.stepsTaken;
    final totalMs = (steps * 110).clamp(250, 600);
    _stepTotalDuration = Duration(milliseconds: totalMs);
    _stepController.duration = _stepTotalDuration;
    _stepController.forward(from: 0.0);
  }

  /// The step phase finished: the token reached the end of the
  /// polyline — start the capture return if this move captured,
  /// else finish the sequence. Guarded on [_stepTokenId]: the
  /// value listener ([_onStepValue]) and the status listener
  /// ([_onStepStatus]) can both observe the same finish, and the
  /// second must be a no-op, never a second capture start.
  void _finishStepPhase() {
    if (_stepTokenId == null) return;
    _stepTokenId = null;
    if (_captureFromToken != null && _captureToToken != null) {
      _startCapture();
      return;
    }
    _finishSequence();
  }

  /// The step controller's value reached the end of the polyline
  /// (M3 premium, §2.2): finish the step phase now. The
  /// `completed` status alone is NOT enough — an
  /// [AnimationController] reports it only once elapsed strictly
  /// exceeds the duration (its simulation's `isDone` is
  /// `time > duration`), so a sequence pumped to exactly its total
  /// sits at value 1.0 with no status event until the next frame
  /// advances past it. The rendered position IS the destination
  /// at value 1.0, so the finish belongs here; the late `completed`
  /// status is then a no-op via [_finishStepPhase]'s guard.
  void _onStepValue() {
    if (_stepController.value >= 1.0) _finishStepPhase();
  }

  /// The step sequence finished (the single controller reached
  /// 1.0): start the capture return if this move captured, else
  /// finish the sequence. A controller stopped by pause never
  /// reports completed, so a frozen sequence resumes on
  /// [_syncAnimationState]'s `forward()`, not from a spurious
  /// completion. Usually a no-op — [_onStepValue] already finished
  /// the phase at value 1.0 — except when the clock jumps past the
  /// total between frames (long pumps, real-time frames).
  void _onStepStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _finishStepPhase();
  }

  /// Starts the capture return (M3 premium, §2.3): ~150 ms beat is
  /// inherent — the capture only starts once the mover's steps have
  /// settled, so the eye registers cause → effect.
  void _startCapture() {
    _captureActive = true;
    _captureTokenId = _captureToToken!.id;
    _captureController.duration = const Duration(milliseconds: 600);
    _captureController.forward(from: 0.0);
    if (mounted) setState(() {});
  }

  /// The capture return finished: the captured token is drawn at
  /// its yard slot from here on (the painter's computed centre is
  /// the same point), and the sequence finishes.
  void _onCaptureStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _captureActive = false;
    _captureTokenId = null;
    _finishSequence();
  }

  /// A sequence finished: the mover carries the last-moved ring
  /// (fading over ~1.5 s) and input unlocks.
  void _finishSequence() {
    _sequenceActive = false;
    _stepTokenId = null;
    _captureActive = false;
    _captureTokenId = null;
    _captureFromToken = null;
    _captureToToken = null;
    // The mover id is carried in [_sequenceMoverId]: [_stepTokenId]
    // is already null by the time a capture finishes, so the ring
    // id cannot be read from it here.
    _lastMovedTokenId = _sequenceMoverId;
    _sequenceMoverId = null;
    if (_lastMovedTokenId != null && !isReducedMotion(context)) {
      _lastMovedController.forward(from: 0.0);
    }
    if (mounted) setState(() {});
  }

  /// Finishes a sequence in flight instantly, leaving every token
  /// drawn at its engine position. Used when a new move replaces a
  /// running sequence; the last-moved ring is not set here — the
  /// replacing sequence sets it when it finishes.
  void _finishSequenceInstantly() {
    if (!_sequenceActive) return;
    _stepController.stop();
    _captureController.stop();
    _sequenceActive = false;
    _stepTokenId = null;
    _captureActive = false;
    _captureTokenId = null;
    _captureFromToken = null;
    _captureToToken = null;
    _sequenceMoverId = null;
  }

  /// The last-moved ring faded out: the ring is gone until the next
  /// move settles.
  void _onLastMovedStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _lastMovedTokenId = null;
    if (mounted) setState(() {});
  }

  /// The illegal-tap shake finished: the shake clears.
  void _onShakeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _shakeTokenId = null;
    _shakeDice = false;
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

  /// Cancels any sequence in flight, leaving every token drawn at
  /// its engine position. Used on controller swaps (a new match
  /// must never animate the old match's state).
  void _cancelSequence() {
    _finishSequenceInstantly();
    _lastMovedController.stop();
    _lastMovedTokenId = null;
    _shakeController.stop();
    _shakeTokenId = null;
    _shakeDice = false;
  }

  /// Syncs the animation controllers to the controller's state
  /// after every notification (M2.7, M3 premium). Pause is a freeze
  /// (D-10, Q2): every controller stops where it is — the tumble's
  /// engine value is kept in the controller and settles on resume,
  /// and a step/capture sequence resumes from the stopped value
  /// instead of snapping to its destination (the M2.7 hop used to
  /// cancel on pause; that behaviour is superseded here). Resume
  /// re-runs each in-flight controller from its current value.
  void _syncAnimationState(OfflineGameController controller) {
    if (controller.isPaused) {
      _diceTumbleController.stop();
      _pulseController.stop();
      _stepController.stop();
      _captureController.stop();
      _lastMovedController.stop();
      _shakeController.stop();
      return;
    }
    final reduced = isReducedMotion(context);
    if (controller.rolling) {
      // Reduced motion: no wind-up, tumble or shake — the dice
      // face stays frozen at the pre-roll value (see [_diceFace])
      // until the roll settles on the engine value.
      if (!reduced && !_diceTumbleController.isAnimating) {
        if (_diceTumbleController.value > 0.0 &&
            _diceTumbleController.value < 1.0) {
          // Resuming a tumble frozen by pause: continue from the
          // stopped value, not from the start.
          _diceTumbleController.forward();
        } else {
          _diceTumbleController.forward(from: 0.0);
        }
      }
    } else {
      _diceTumbleController.reset();
    }
    // Resume a step/capture sequence frozen by pause, from the
    // stopped value. `forward()` without `from:` continues where
    // the controller stopped; the step/capture status listeners
    // advance the sequence from there.
    if (_sequenceActive) {
      if (_captureActive) {
        if (!_captureController.isAnimating) _captureController.forward();
      } else if (_stepTokenId != null) {
        if (!_stepController.isAnimating) _stepController.forward();
      }
    }
    if (_lastMovedTokenId != null &&
        !reduced &&
        !_lastMovedController.isAnimating &&
        _lastMovedController.value < 1.0) {
      _lastMovedController.forward();
    }
    // Stopping the pulse when nothing is legal also stops the
    // board repainting every frame while the match waits for a roll.
    // A cycle plays once per legal-move appearance (see
    // [_pulseController]): while it runs, no new cycle starts; once
    // it completes and resets, the next notification restarts it —
    // and no notification arrives while a human simply thinks, so
    // the ring rests static between turns. The same one-shot cycle
    // is the AI-thinking indicator (Q10): while an AI turn is
    // pending the pulse runs, driving the three dots in the
    // current player's chip.
    if ((controller.legalMoves.isNotEmpty && !controller.isFinished) ||
        _isAiThinking(controller)) {
      if (!_pulseController.isAnimating) {
        _pulseController.forward(from: 0.0);
      }
    } else {
      _pulseController.stop();
    }
  }

  /// True while an AI turn is pending action (M3 premium, Q10):
  /// the current player is AI, the match is neither rolling,
  /// paused nor finished. The AI pacing timer (700–1,199 ms,
  /// D-31) is running in this window, so the three-dot pulse in
  /// the player's chip is the proof the game has not stalled.
  bool _isAiThinking(OfflineGameController controller) {
    if (controller.isFinished || controller.isPaused || controller.rolling) {
      return false;
    }
    return controller.state.currentPlayer.isAi &&
        controller.state.phase != TurnPhase.finished;
  }

  /// The dice face shown mid-tumble (M2.7): the tumble value cycles
  /// 1..6 as the 540 ms controller runs. Only read while rolling —
  /// once the roll settles the screen shows the engine value.
  int get _tumbleFace => ((_diceTumbleController.value * 6).floor() % 6) + 1;

  /// The dice face to render (M3 premium, §2.7.1): while rolling
  /// the tumble face cycles, except under reduced motion, where the
  /// face stays frozen at the pre-roll value until the roll settles
  /// on the engine value. Once settled, always the engine value.
  int? get _diceFace {
    final controller = _controller;
    if (controller == null) return null;
    if (controller.rolling) {
      return isReducedMotion(context) ? _preRollFace : _tumbleFace;
    }
    return controller.displayedRoll;
  }

  /// The legal-move pulse (M2.7): a smooth 0..1..0 oscillation
  /// over each 1,200 ms repeat, or 0 when the pulse is stopped.
  double get _pulseValue {
    if (!_pulseController.isAnimating) return 0.0;
    return (math.sin(_pulseController.value * 2 * math.pi) + 1) / 2;
  }

  /// The step polyline position right now (M3 premium, §2.2):
  /// [_stepController]'s value (0..1 over the whole sequence)
  /// scaled by the segment count. At a segment boundary the
  /// fraction is exactly 0, so the token sits exactly on the cell.
  double get _stepSegmentFloat =>
      _stepController.value * (_stepPath.length - 1);

  /// The segment in flight: the polyline position's whole part,
  /// clamped so value 1.0 still names the last segment.
  int get _stepSegmentIndex =>
      _stepSegmentFloat.floor().clamp(0, _stepPath.length - 2);

  /// Progress within the segment in flight, 0..1.
  double get _stepSegmentFraction =>
      (_stepSegmentFloat - _stepSegmentIndex).clamp(0.0, 1.0);

  /// The stepping token's rendered centre right now (M3 premium,
  /// §2.2): the eased interpolation between the current segment's
  /// cells, or null when no step is in flight.
  Offset? get _stepCenter {
    if (_stepTokenId == null || _stepPath.length < 2) return null;
    final from = _stepPath[_stepSegmentIndex];
    final to = _stepPath[_stepSegmentIndex + 1];
    return Offset.lerp(
      from,
      to,
      Curves.easeOutCubic.transform(_stepSegmentFraction),
    )!;
  }

  /// The stepping token's lift right now (M3 premium, §2.2.3): a
  /// small hop per step — scale 1.0 at each cell, peaking mid-step
  /// (~1.12, or ~1.18 on the final step of a capturing move).
  double get _stepScale {
    if (_stepTokenId == null) return 1.0;
    final isFinalStep = _stepSegmentIndex == _stepPath.length - 2;
    final peak = _stepIsCapture && isFinalStep ? 0.18 : 0.12;
    return 1.0 + peak * math.sin(_stepSegmentFraction * math.pi);
  }

  /// The captured token's rendered centre right now (M3 premium,
  /// §2.3): a gentle arc from its cell to its yard slot — the
  /// horizontal travel eases in-out over the first 80% of the
  /// ~600 ms, with a sinusoidal lift peaking mid-arc — or null
  /// when no capture is in flight.
  Offset? get _captureCenter {
    if (!_captureActive) return null;
    final from = _captureFromCentre;
    final to = _captureToCentre;
    if (from == null || to == null) return null;
    final p = _captureController.value;
    final travel = Curves.easeInOut.transform((p / 0.8).clamp(0.0, 1.0));
    final lift = math.sin(travel * math.pi) * _captureArcHeight;
    return Offset.lerp(from, to, travel)! + Offset(0, -lift);
  }

  /// The captured token's scale right now (M3 premium, §2.3): 1.0 →
  /// 0.7 while it lifts and travels, then a pop-in (0.7 → 1.08 →
  /// 1.0) over the last quarter.
  double get _captureScale {
    if (!_captureActive) return 1.0;
    final p = _captureController.value;
    if (p < 0.75) return 1.0 - 0.3 * (p / 0.75);
    final q = (p - 0.75) / 0.25;
    if (q < 0.5) return 0.7 + 0.38 * Curves.easeOut.transform(q / 0.5);
    return 1.08 - 0.08 * Curves.easeInOut.transform((q - 0.5) / 0.5);
  }

  /// The captured token's opacity right now (M3 premium, §2.3):
  /// 1.0 → 0.4 while it lifts and travels, back to 1.0 as it pops
  /// into its yard slot.
  double get _captureOpacity {
    if (!_captureActive) return 1.0;
    final p = _captureController.value;
    if (p < 0.6) return 1.0 - 0.6 * (p / 0.6);
    if (p < 0.85) return 0.4 + 0.6 * ((p - 0.6) / 0.25);
    return 1.0;
  }

  /// The last-moved ring's opacity right now (M3 premium, §2.2.6):
  /// 1.0 → 0.0 over the ~1.5 s fade, or a steady 1.0 under reduced
  /// motion (the ring is information, not motion, so it stays).
  double get _lastMovedOpacity {
    if (_lastMovedTokenId == null) return 0.0;
    if (isReducedMotion(context)) return 1.0;
    return 1.0 - _lastMovedController.value;
  }

  /// The illegal-tap shake offset right now (M3 premium, §2.5.4):
  /// ±1.5 dp, two oscillations over the ~150 ms shake. Zero at
  /// rest (the sine is 0 at both ends of the controller).
  Offset get _shakeOffset =>
      Offset(math.sin(_shakeController.value * 4 * math.pi) * 1.5, 0);

  /// The dice's wind-up / tumble / settle motion right now (M3
  /// premium, §2.4), as scale, rotation and translation of the
  /// [DiceWidget] — all inside the 540 ms tumble budget. Wind-up
  /// (first ~22%): a quick anticipatory dip (scale → 0.92, ~−6°).
  /// Tumble (to 85%): rotation jitter ±8° and translate jitter
  /// ±2 dp, damped toward rest, deterministic in the controller
  /// value so the same pump sequence always renders the same
  /// frames. Settle (last 15%): one damped wobble, scale 1.06 →
  /// 1.0 — deliberately not a bounce (R12). At rest, identity.
  ({double scale, double rotation, Offset translate}) _diceMotion() {
    final v = _diceTumbleController.value;
    if (v == 0.0) {
      return (scale: 1.0, rotation: 0.0, translate: Offset.zero);
    }
    if (v < 0.22) {
      final q = Curves.easeIn.transform(v / 0.22);
      return (
        scale: 1.0 - 0.08 * q,
        rotation: -0.105 * q,
        translate: Offset.zero,
      );
    }
    if (v < 0.85) {
      final q = (v - 0.22) / 0.63;
      final damp = 1.0 - q * 0.6;
      return (
        scale: 0.92 + 0.08 * q,
        rotation: math.sin(v * 28.0) * 0.14 * damp,
        translate: Offset(
          math.sin(v * 47.0) * 2.0 * damp,
          math.cos(v * 39.0) * 2.0 * damp,
        ),
      );
    }
    final q = (v - 0.85) / 0.15;
    return (
      scale: 1.0 + 0.06 * (1.0 - q) * math.cos(q * math.pi * 2.0),
      rotation: 0.0,
      translate: Offset.zero,
    );
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
              tokensHome: player.tokensHome,
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
        !_sequenceActive &&
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
    // only. M3 premium (§2.5.4) adds a visual echo: the tapped
    // token shakes ~150 ms (two ±1.5 dp oscillations).
    final tappedToken = _tokenAt(details.localPosition, boardSide, tokens);
    if (tappedToken != null) {
      _shakeTokenId = tappedToken.id;
      _shakeController.forward(from: 0.0);
      _showIllegalTapFeedback(stringsOf(context).gameIllegalTokenMove);
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
  /// a roll, not rolling, not paused, no sequence in flight — and the
  /// controller's own guards are the second line of defence, so a
  /// tap racing the tumble start (a rapid double-tap, or a dice tap
  /// right after the button) is ignored, never queued, and rolls
  /// exactly once. A tap that cannot roll gets the same brief
  /// feedback as an illegal board tap, with the reason named, and
  /// the game state is untouched. M3 premium (§2.5.4) adds a visual
  /// echo: the dice shakes ~150 ms. Finished / paused taps are
  /// silent: the results screen (finished) and the pause dialog
  /// (paused) already own the screen, so no feedback path exists.
  void _onDiceTap() {
    final controller = _controller;
    if (controller == null || controller.isFinished || controller.isPaused) {
      return;
    }
    final l10n = stringsOf(context);
    final state = controller.state;
    // Shakes the dice for any tap that cannot roll (below): a
    // visual echo on the thing that was tapped, never a state
    // change. Declared here so every feedback branch shares it.
    void shakeDice(String message) {
      _shakeDice = true;
      _shakeController.forward(from: 0.0);
      _showIllegalTapFeedback(message);
    }

    if (!state.currentPlayer.isHuman) {
      shakeDice(l10n.gameDiceNotYourTurn);
      return;
    }
    if (controller.rolling) {
      shakeDice(l10n.gameDiceWaitSettle);
      return;
    }
    if (_sequenceActive) {
      shakeDice(l10n.gameDiceWaitMove);
      return;
    }
    if (state.phase != TurnPhase.awaitingRoll) {
      // Already rolled: the next action is a token move, not a roll.
      shakeDice(l10n.gameDiceChooseToken);
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
  /// a bottom sheet — the [DiceUpDialog] shell (Stage 2 redesign,
  /// §3.5: ivory surface, 16 dp radius, Resume as the single
  /// primary action, Restart/Main Menu as quiet secondary actions)
  /// — so the 48 dp action buttons and the back-button behaviour
  /// match the rest of the app. The menu also shows the current
  /// standings (display of existing state only, no new data) — the
  /// one place a player can read without time pressure.
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
    final l10n = stringsOf(context);
    final players = controller.state.players;
    final currentIndex = controller.state.currentPlayerIndex;
    final choice = await DiceUpDialog.show<_PauseChoice>(
      context,
      title: l10n.gamePausedTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.gamePausedMessage),
          const SizedBox(height: DiceUpSpacing.md),
          for (final player in players)
            Padding(
              padding: const EdgeInsets.only(bottom: DiceUpSpacing.xs),
              child: Row(
                children: [
                  PlayerAvatar(
                    name: player.name,
                    seatIndex: player.index,
                    colour: player.colour,
                    radius: 12,
                  ),
                  const SizedBox(width: DiceUpSpacing.xs),
                  Expanded(
                    child: Text(
                      // gen-l10n orders the positional parameters
                      // alphabetically (home, name), not in message
                      // order.
                      stringsOf(context)
                          .gamePlayerHome(player.tokensHome, player.name),
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // The current player's shape marker: the turn
                  // cue in the standings, shape + colour, never
                  // colour alone.
                  if (player.index == currentIndex)
                    PlayerShapeMarker(
                      shape: PlayerShape.forSeat(player.index),
                      color: DiceUpColors.forColour(player.colour),
                      size: 14,
                    ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_PauseChoice.exit),
          child: Text(l10n.mainMenu),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_PauseChoice.restart),
          child: Text(l10n.gamePauseRestart),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_PauseChoice.resume),
          child: Text(l10n.gamePauseResume),
        ),
      ],
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
    final l10n = stringsOf(context);
    final restart = await ConfirmationDialog.show(
      context,
      title: l10n.gameRestartTitle,
      message: l10n.gameRestartMessage,
      confirmLabel: l10n.gameRestartConfirm,
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
    final l10n = stringsOf(context);
    final leave = await ConfirmationDialog.show(
      context,
      title: l10n.gameLeaveTitle,
      message: controller.isFinished
          ? l10n.gameLeaveFinishedMessage
          : l10n.gameLeaveUnfinishedMessage,
      confirmLabel: l10n.gameLeaveConfirm,
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
    final l10n = stringsOf(context);
    // Input stays locked while a move/capture sequence renders
    // (M3 premium): the engine state is already final, but a second
    // move landing on top of the sequence would overlap two
    // animations. A sequence is at most ~600 ms of steps plus a
    // ~600 ms capture return.
    final sequenceInFlight = _sequenceActive;
    final isHumanTurn =
        current.isHuman &&
        state.phase != TurnPhase.finished &&
        !controller.rolling &&
        !controller.isPaused &&
        !sequenceInFlight;
    // A roll is available exactly when the Roll button is enabled
    // (M2.8): the dice shares this condition, so the two affordances
    // can never disagree about whether a tap rolls.
    final canRoll = isHumanTurn && state.phase == TurnPhase.awaitingRoll;
    final boardSide = _boardSide(context);
    // Short-screen compaction (M2.12, NFR-09): the 320x568 worst
    // case is 568 tall, so the gate is height < 600 dp — the
    // 800x600 default test viewport and every taller phone keep
    // the full layout.
    final isShortScreen = MediaQuery.of(context).size.height < 600;
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
              ? l10n.gameBoardFinished
              : l10n.gameBoardWinner(controller.winner!.name))
        : controller.legalMoves.length == 1
        ? l10n.gameBoardTurnOne(current.name)
        : l10n.gameBoardTurnOther(
            // gen-l10n orders the positional parameters
            // alphabetically (count, name), not in message order.
            controller.legalMoves.length,
            current.name,
          );

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
        // Stage 2 redesign (§3.4, F1/F2): the game screen sits on
        // the deep navy `table` field, so the ivory board and the
        // four player colours read as objects on a table. The
        // AppBar keeps the theme navy; the field is an
        // environment, not a dark theme.
        backgroundColor: DiceUpColors.table,
        appBar: AppBar(
          title: Text(l10n.appName),
          leading: IconButton(
            icon: const Icon(Icons.pause),
            tooltip: l10n.gamePauseTooltip,
            onPressed: controller.isFinished ? null : _showPauseMenu,
          ),
        ),
        body: SafeArea(
          // Pinned first paint (Stage 2, F8): the board + dice
          // row are the stable top of a fixed column — the whole
          // column no longer scrolls the board away. Only the
          // player chips + safe-cells hint below the dice row
          // scroll, in their own [Expanded] area. The column is
          // centred in a [DiceUpSpacing.maxContentWidth] column
          // on wide screens, and the board side is height-aware
          // ([_boardSide]) so the dice row stays above the fold
          // even on short/wide viewports (e.g. 800x600).
          // Premium v2: the navy field gains the layered table
          // washes ([TableBackground]) behind the content — the
          // board column, its sizes, the pinned first paint and
          // all semantics are untouched.
          child: Stack(
            children: [
              const Positioned.fill(child: TableBackground()),
              LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = constraints.maxWidth > 560
                  ? 560.0
                  : constraints.maxWidth;
              return Center(
                child: SizedBox(
                  width: contentWidth,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: DiceUpSpacing.md,
                      vertical: isShortScreen
                          ? DiceUpSpacing.xxs
                          : DiceUpSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TurnBanner(
                          player: current,
                          status: controller.status,
                          compact: isShortScreen,
                        ),
                        SizedBox(
                          height: isShortScreen
                              ? DiceUpSpacing.xxs
                              : DiceUpSpacing.sm,
                        ),
                        Center(
                          child: Semantics(
                            label: boardLabel,
                            child: GestureDetector(
                              onTapDown: (details) =>
                                  _onBoardTap(details, boardSide),
                              // The board repaints on its own (M2.7): the
                              // pulse, steps, capture, ring fade and shake
                              // animate inside the [RepaintBoundary], so a
                              // tick repaints the board and nothing else.
                              // The painted board itself contributes no
                              // semantics nodes (CustomPaint draws, it does
                              // not label) — the Semantics wrapper above is
                              // the board's only node, so nothing decorative
                              // leaks through. The board sits in an ivory
                              // frame (Stage 2, F2: radiusBoard + the
                              // `table` shadow) so it reads as a physical
                              // object on the navy field.
                              child: RepaintBoundary(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        DiceUpSpacing.radiusBoardBorder,
                                    border: Border.all(
                                      color: DiceUpColors.ivory,
                                      width: 2,
                                    ),
                                    // Premium v2: a thin dark rim
                                    // under the ivory border (a
                                    // zero-blur spread shadow), so
                                    // the frame reads as the board's
                                    // physical edge on the table field.
                                    boxShadow: [
                                      ...DiceUpShadows.boardRim,
                                      ...DiceUpShadows.table,
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: DiceUpSpacing.radiusLgBorder,
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
                                                  (m) =>
                                                      '${m.playerIndex}:${m.tokenIndex}',
                                                )
                                                .toSet(),
                                            currentSeat:
                                                state.currentPlayerIndex,
                                            pulse: _pulseValue,
                                            hopTokenId: _stepTokenId,
                                            hopCenter: _stepCenter,
                                            hopScale: _stepScale,
                                            captureTokenId: _captureActive
                                                ? _captureTokenId
                                                : null,
                                            captureCenter: _captureCenter,
                                            captureScale: _captureScale,
                                            captureOpacity: _captureOpacity,
                                            lastMovedTokenId: _lastMovedTokenId,
                                            lastMovedOpacity: _lastMovedOpacity,
                                            shakeTokenId: _shakeTokenId,
                                            shakeOffset: _shakeOffset,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: isShortScreen
                              ? DiceUpSpacing.xxs
                              : DiceUpSpacing.sm,
                        ),
                        // The dice row is the action zone (Stage 2,
                        // F4): the dice and the single primary Roll
                        // action sit together on an ivory tray, so
                        // the rollable dice + Roll button read as
                        // one action, not two equal affordances.
                        Center(
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isShortScreen
                                  ? DiceUpSpacing.xs
                                  : DiceUpSpacing.md,
                              vertical: DiceUpSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  DiceUpColors.surface,
                                  DiceUpColors.ivoryAlt,
                                ],
                              ),
                              borderRadius: DiceUpSpacing.radiusLgBorder,
                              border: Border.all(color: DiceUpColors.border),
                              boxShadow: DiceUpShadows.floating,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // The dice face comes from the tumble while
                                // rolling (M2.7) — or stays frozen at the
                                // pre-roll face under reduced motion (M3,
                                // §2.7.1); once the roll settles the dice
                                // shows the engine value. The dice is
                                // tappable (M2.8): tapping it rolls exactly
                                // as the Roll button does, under the same
                                // guards — and a tap that cannot roll gets
                                // brief feedback instead of silence. The
                                // wind-up / shake / settle motion (M3,
                                // §2.4) and the illegal-tap shake (M3,
                                // §2.5.4) are transforms around the dice
                                // widget itself, so the widget is untouched.
                                AnimatedBuilder(
                                  animation: _diceAnimation,
                                  builder: (context, _) {
                                    final reduced = isReducedMotion(context);
                                    final motion = reduced
                                        ? (
                                            scale: 1.0,
                                            rotation: 0.0,
                                            translate: Offset.zero,
                                          )
                                        : _diceMotion();
                                    final shake = _shakeDice
                                        ? _shakeOffset
                                        : Offset.zero;
                                    return Transform.translate(
                                      offset: motion.translate + shake,
                                      child: Transform.rotate(
                                        angle: motion.rotation,
                                        child: Transform.scale(
                                          scale: motion.scale,
                                          child: DiceWidget(
                                            value: _diceFace,
                                            // Short screens (M2.12): 56 dp dice, still
                                            // above the 48 dp control minimum.
                                            size: isShortScreen ? 56 : 64,
                                            rolling:
                                                controller.rolling && !reduced,
                                            enabled: canRoll,
                                            onTap: _onDiceTap,
                                            showRollableBorder: canRoll,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                SizedBox(
                                  width: isShortScreen
                                      ? DiceUpSpacing.sm
                                      : DiceUpSpacing.md,
                                ),
                                PrimaryButton(
                                  label: controller.rolling
                                      ? l10n.gameRolling
                                      : l10n.gameRollDice,
                                  onPressed: canRoll
                                      ? controller.rollDice
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          height: isShortScreen
                              ? DiceUpSpacing.xxs
                              : DiceUpSpacing.xs,
                        ),
                        // Player chips + hint scroll below the dice
                        // row when they cannot fit (Stage 2, F8):
                        // the board and dice row never scroll away.
                        // The safe-cells hint lives here, below the
                        // fold on short screens — reference text,
                        // not first-paint gameplay. White text on
                        // the navy field (the theme's bodySmall is
                        // slate-on-light and would be unreadable
                        // here).
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Wrap(
                                  spacing: DiceUpSpacing.sm,
                                  runSpacing: DiceUpSpacing.sm,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    for (final player in state.players)
                                      _PlayerChip(
                                        player: player,
                                        isCurrent:
                                            player.index ==
                                            state.currentPlayerIndex,
                                        // AI thinking (M3 premium, Q10): the
                                        // three-dot pulse in the current AI
                                        // player's chip is the primary "the game
                                        // has not stalled" indicator — the banner
                                        // spinner is gone.
                                        thinking:
                                            player.index ==
                                                state.currentPlayerIndex &&
                                            _isAiThinking(controller),
                                        thinkingPulse: _pulseValue,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: DiceUpSpacing.sm),
                                Text(
                                  l10n.gameSafeCellsHint,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.white,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: DiceUpSpacing.xs),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            ), // LayoutBuilder
            ], // Stack children
          ), // Stack
        ), // SafeArea
      ),
    );
  }

  double _boardSide(BuildContext context) {
    final media = MediaQuery.of(context);
    final width =
        media.size.width -
        DiceUpSpacing.md * 2 -
        DiceUpSpacing.md; // screen + safe-area padding
    final widthSide = width.clamp(280.0, 480.0);
    // Height-aware (Stage 2, F8): on short or wide viewports the
    // width rule alone would push the dice row below the fold
    // (e.g. a 480 dp board at 800x600). The reserve covers the
    // AppBar + banner + dice tray + gaps/padding, so the board
    // shrinks instead of the dice row scrolling away; on phones
    // the width rule still binds, so the pinned sizes in
    // `test/layout_320_test.dart` are unchanged. The reserve is
    // smaller on short screens (compact banner/tray/gaps, 272)
    // than on tall ones (328): at 360x640 the tall reserve still
    // leaves the pinned 312 dp board, while at 800x600 it leaves
    // a 272 dp board and the dice row above the fold.
    final isShort = media.size.height < 600;
    final heightSide = media.size.height - (isShort ? 272 : 328);
    return math.min(widthSide, heightSide).clamp(240.0, 480.0).toDouble();
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({
    required this.player,
    required this.status,
    this.compact = false,
  });

  final Player player;
  final String status;

  /// Short-screen form (M2.12, NFR-09): tighter card padding and
  /// a smaller avatar, so the status wraps to two lines instead of
  /// three at 320 dp wide and the dice row stays above the fold.
  /// The avatar keeps name + colour ring + shape + initial (M2.4,
  /// D-27) — only its size changes — and the full status text is
  /// still shown, never ellipsised.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Semantics (M2.9, NFR-08): the banner is announced as
    // "<name>'s turn" — the plan's label. The name and status
    // texts stay readable as child nodes (the status line is the
    // illegal-tap feedback channel, so it must never be hidden),
    // and the avatar contributes its own name + shape + colour
    // node (see [PlayerAvatar]).
    //
    // No spinner lives here anymore (M3 premium, Q10): the
    // three-dot pulse in the current player's chip is the primary
    // AI-thinking indicator, and the status line narrates AI
    // actions ("Green (AI) rolled 4, …"). A spinner that outlives
    // its turn reads as a bug; the dots stop the moment the AI acts.
    final l10n = stringsOf(context);
    // Stage 2 turn system (F3): the banner is the turn banner,
    // not a generic card. A 6 dp accent bar in the current
    // player's full colour runs down its left edge — the same
    // colour as the avatar ring — so the banner, the yard glow
    // and the chip turn badge all answer "whose turn" together.
    // The bar is never the lone cue: the avatar (white disc, navy
    // initial, colour ring, shape marker — D-27) and the name
    // carry the identity with it.
    final accent = DiceUpColors.forColour(player.colour);
    return Semantics(
      label: l10n.gameTurnBanner(player.name),
      // M2.9: the children stay separate nodes (see the note
      // above). Without `explicitChildNodes` the framework merges
      // the avatar label, name and status into this node's label
      // ("<name>'s turn\n<avatar label>\n<name>\n<status>"), so the
      // exact "<name>'s turn" node the banner is announced as
      // disappears.
      explicitChildNodes: true,
      // Stage 4 polish: the accent bar crossfades to the new
      // player's colour on a turn change (200 ms, instant under
      // reduced motion) instead of snapping — the banner visibly
      // hands over. The avatar, name and status still carry the
      // identity with it; the bar is never the lone cue.
      child: AnimatedContainer(
        duration: isReducedMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: DiceUpColors.surface,
          borderRadius: DiceUpSpacing.radiusLgBorder,
          border: Border(left: BorderSide(color: accent, width: 6)),
          boxShadow: DiceUpShadows.raised,
        ),
        child: Padding(
          padding: compact
              ? const EdgeInsets.symmetric(
                  horizontal: DiceUpSpacing.md,
                  vertical: DiceUpSpacing.xxs,
                )
              : DiceUpSpacing.cardPadding,
          child: Row(
            children: [
              PlayerAvatar(
                name: player.name,
                seatIndex: player.index,
                // The ring follows the player's *chosen* colour (M2.2),
                // not the seat-order colour — after a swap they differ.
                colour: player.colour,
                radius: compact ? 16 : 20,
              ),
              SizedBox(width: compact ? DiceUpSpacing.sm : DiceUpSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.isAi
                          ? l10n.playerWithAi(player.name)
                          : player.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(status, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  const _PlayerChip({
    required this.player,
    required this.isCurrent,
    this.thinking = false,
    this.thinkingPulse = 0.0,
  });

  final Player player;
  final bool isCurrent;

  /// The AI-thinking indicator (M3 premium, Q10): while this
  /// (current, AI) player's turn is pending, three dots pulse in
  /// the chip. [thinkingPulse] is the 0..1 one-shot pulse value
  /// (0 when the pulse is stopped — the dots then sit static, still
  /// visible, so the indicator never vanishes mid-thought).
  final bool thinking;
  final double thinkingPulse;

  @override
  Widget build(BuildContext context) {
    // Stage 2 turn system (F3): the current chip is unmistakable
    // at a glance. It sits on the ivory surface with a 2.5 dp
    // border in the player's full colour, a raised shadow, and a
    // teal turn badge carrying the player's shape in white — so
    // the current seat is marked by border + badge + shape, never
    // by colour alone (yellow's border is 2.38:1 on ivory and
    // would fail as a lone cue). Other chips stay on the muted
    // ivory surface with a thin neutral border.
    final playerColour = DiceUpColors.forColour(player.colour);
    // Stage 4 polish: the current-state treatment (player-colour
    // border, raised shadow, ivory surface) crossfades in/out on
    // a turn change (200 ms, instant under reduced motion)
    // instead of snapping — the strip visibly hands the turn over.
    // Border + badge + shape still mark the current seat together,
    // never colour alone.
    return AnimatedContainer(
      duration: isReducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(
        horizontal: DiceUpSpacing.sm,
        vertical: DiceUpSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isCurrent ? DiceUpColors.surface : DiceUpColors.surfaceMuted,
        borderRadius: DiceUpSpacing.radiusMdBorder,
        border: Border.all(
          color: isCurrent ? playerColour : DiceUpColors.border,
          width: isCurrent ? 2.5 : 1,
        ),
        boxShadow: isCurrent ? DiceUpShadows.raised : null,
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
              // gen-l10n orders the positional parameters
              // alphabetically (home, name), not in message order.
              stringsOf(context).gamePlayerHome(player.tokensHome, player.name),
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(width: DiceUpSpacing.xs),
            // Turn badge: the player's shape in white on teal —
            // the action colour, shared with the banner accent,
            // the yard glow and the on-board token ring.
            ExcludeSemantics(
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DiceUpColors.teal,
                  borderRadius: DiceUpSpacing.radiusSmBorder,
                ),
                child: PlayerShapeMarker(
                  shape: PlayerShape.forSeat(player.index),
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ),
          ],
          if (thinking) ...[
            const SizedBox(width: DiceUpSpacing.xs),
            // Decorative only: the status line already narrates the
            // AI's action, and the turn banner already names the
            // player — the dots add no semantics node.
            ExcludeSemantics(child: _ThinkingDots(pulse: thinkingPulse)),
          ],
        ],
      ),
    );
  }
}

/// Three-dot "thinking" pulse (M3 premium, §2.5.2/Q10): three 4 dp
/// teal dots whose opacities chase each other around the 0..1
/// [pulse] cycle. Static (pulse 0) they sit at staggered opacities,
/// so the indicator reads even between cycles.
class _ThinkingDots extends StatelessWidget {
  const _ThinkingDots({required this.pulse});

  final double pulse;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DiceUpColors.teal.withValues(
                alpha:
                    0.4 +
                    0.6 * (0.5 + 0.5 * math.sin((pulse + i / 3) * 2 * math.pi)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
