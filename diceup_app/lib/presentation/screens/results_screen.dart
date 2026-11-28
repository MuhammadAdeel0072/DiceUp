import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:diceup/l10n/app_localizations.dart';

import '../../core/accessibility/reduced_motion.dart';
import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_shadows.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../l10n/app_strings.dart';
import '../navigation/app_routes.dart';

/// Shown on the results screen when the completed match could not be
/// recorded (M1.6). The match is still shown — the win happened — but
/// never presented as if recording had succeeded. Moved here from
/// `game_screen.dart` in M2.5, when the win dialog (its only reader)
/// was replaced by this screen.
const String kMatchRecordFailedMessage =
    "This match finished, but it couldn't be saved to your history.";

/// Dedicated results screen (M2.5, FR-26; D-02, D-30).
///
/// Shown exactly once per finished match, as a *route* — the M1.6 win
/// dialog is gone. The game screen navigates here with
/// `pushNamedAndRemoveUntil` keeping only Home below, so the stack is
/// Home → Results: the system back button lands on Home, and there is
/// no finished game screen underneath to pop back to. The two actions
/// are both single, stack-shape-aware navigations — never a counted
/// pair of pops (the old double-pop: dialog, then game screen):
///
/// * **Play Again** — a fresh match with the exact settings of the
///   finished match ([MatchResult.setup]: same players, names,
///   colours, difficulties, ruleset), via the game route. The new
///   match starts immediately; the stack becomes Home → Game.
/// * **Main Menu** — Home, exactly once (D-30): a single `pop()` to
///   the Home route below Results (see [_goHome] for why a fresh
///   Home is pushed only when nothing is below).
///
/// What is shown is exactly what FR-26 / SDD §11.1 require: the
/// winner (name + avatar with colour ring + shape + initial — never
/// colour alone, M2.4/D-27), the duration (`mm:ss`), the move count,
/// the mode, the players and the date. "Finishing order where
/// applicable" is winner-only under the default ruleset: the match
/// ends at the first finisher (BR-11) and continue-to-rank is
/// DEFERRED (D-02), so no 2nd/3rd order is shown or invented. No
/// lifetime statistics live here (M1.7 owns those) and no ranking or
/// placement features exist.
///
/// M3 premium (§2.6, Q5/Q8): the winner gets DiceUp's own winner's
/// mark — an enlarged per-seat shape marker in a teal ring around
/// the avatar (no crown: Ludo King's crown is its brand) — the
/// entrance is staggered (headline, then avatar scaling in with an
/// `outBack` overshoot, then the cards), each player's tokens-home
/// count ("Home n/4") is shown next to their name, and a short
/// one-shot hand-drawn confetti burst falls once on entry. All of
/// it collapses under reduced motion (§2.7.1): the entrance jumps
/// to its end state and the confetti never fires.
///
/// The screen takes its data as a frozen [MatchResult] (constructor
/// parameter in tests, route arguments in production — see
/// [AppRoutes.matchResultOf]). It never reads the game controller:
/// the controller is disposed when the results route replaces the
/// game route, and the screen must never re-record the completion
/// (exactly-once, M1.6). A route opened without a result shows an
/// honest empty state with a Main Menu button, never an invented
/// result.
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key, this.result});

  /// The finished match to show. When null, the route arguments
  /// supply it (see [AppRoutes.matchResultOf]).
  final MatchResult? result;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// The entrance choreography (M3 premium, §2.6.1): ~500 ms,
  /// headline → avatar → cards, staggered via [Interval]s in
  /// [build]. Finite, so `pumpAndSettle` terminates.
  late final AnimationController _entranceController;
  bool _entranceStarted = false;
  bool _confettiSuppressed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceStarted) return;
    _entranceStarted = true;
    final reducedMotion = isReducedMotion(context);
    _confettiSuppressed = reducedMotion;
    // Reduced motion (§2.7.1): the entrance jumps to its end state
    // instead of animating in.
    if (reducedMotion) {
      _entranceController.value = 1.0;
    } else {
      _entranceController.forward();
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (!mounted) return;
    if (isReducedMotion(context)) {
      _confettiSuppressed = true;
      _entranceController.value = 1.0;
    }
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    final result = widget.result ?? AppRoutes.matchResultOf(context);
    if (result == null) {
      assert(() {
        debugPrint(
          'DiceUp: results route opened without a MatchResult; '
          'showing the empty state.',
        );
        return true;
      }());
      return Scaffold(
        appBar: AppBar(title: Text(l10n.resultsTitle)),
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
                    Text(l10n.resultsEmpty, textAlign: TextAlign.center),
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
    final reduced = isReducedMotion(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.resultsTitle)),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: DiceUpSpacing.maxContentWidth,
                ),
                child: SingleChildScrollView(
                  padding: DiceUpSpacing.screenPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Entrance(
                        controller: _entranceController,
                        interval: const Interval(0.0, 0.6),
                        slideUp: true,
                        child: Text(
                          l10n.resultsWinnerWins(result.winnerName),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      const SizedBox(height: DiceUpSpacing.md),
                      // Winner's stage (REDESIGN-PLAN.md §3.6): the
                      // mark sits on the navy table field so the
                      // white-disc avatar reads as an object on the
                      // table, not as another card on ivory.
                      Container(
                        padding: DiceUpSpacing.screenPadding,
                        decoration: const BoxDecoration(
                          color: DiceUpColors.table,
                          borderRadius: DiceUpSpacing.radiusLgBorder,
                          boxShadow: DiceUpShadows.table,
                        ),
                        child: Center(
                          child: _WinnerAvatar(
                            result: result,
                            entrance: _entranceController,
                          ),
                        ),
                      ),
                      const SizedBox(height: DiceUpSpacing.lg),
                      _Entrance(
                        controller: _entranceController,
                        interval: const Interval(0.4, 1.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: StatTile(
                                label: l10n.labelDuration,
                                value: _formatDuration(result.duration),
                              ),
                            ),
                            const SizedBox(width: DiceUpSpacing.sm),
                            Expanded(
                              child: StatTile(
                                label: l10n.labelMoves,
                                value: '${result.moveCount}',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: DiceUpSpacing.md),
                      _Entrance(
                        controller: _entranceController,
                        interval: const Interval(0.4, 1.0),
                        child: DiceUpCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _InfoRow(
                                label: l10n.labelMode,
                                value: result.isOnline
                                    ? l10n.modeOnline
                                    : result.isVsAi
                                    ? l10n.modeShortVsAi
                                    : l10n.modeLocal,
                              ),
                              _InfoRow(
                                label: l10n.labelPlayers,
                                value: result.players.length == 1
                                    ? l10n.playersCountOne
                                    : l10n.playersCountOther(
                                        result.players.length,
                                      ),
                              ),
                              _InfoRow(
                                label: l10n.labelFinished,
                                value: _formatDate(result.finishedAt, l10n),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: DiceUpSpacing.md),
                      _Entrance(
                        controller: _entranceController,
                        interval: const Interval(0.4, 1.0),
                        child: DiceUpCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final player in result.players) ...[
                                _PlayerRow(
                                  player: player,
                                  isWinner: player.seat == result.winnerSeat,
                                ),
                                if (player != result.players.last)
                                  const SizedBox(height: DiceUpSpacing.sm),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (result.completionFailed) ...[
                        const SizedBox(height: DiceUpSpacing.md),
                        DiceUpCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: DiceUpColors.error,
                              ),
                              const SizedBox(width: DiceUpSpacing.sm),
                              Expanded(
                                child: Text(
                                  l10n.resultsRecordFailed,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: DiceUpColors.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: DiceUpSpacing.lg),
                      // Online matches (Phase 5, Stage 7) have no
                      // Play Again here: a rematch starts from the
                      // lobby, never by replaying an offline setup.
                      if (!result.isOnline) ...[
                        PrimaryButton(
                          label: l10n.resultsPlayAgain,
                          onPressed: () => _playAgain(context, result.setup),
                        ),
                        const SizedBox(height: DiceUpSpacing.sm),
                      ],
                      SecondaryButton(
                        label: l10n.mainMenu,
                        onPressed: () => _goHome(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // One-shot hand-drawn confetti (M3 premium, §2.6.3/Q5):
            // ~1.2 s, fires once on entry, never loops, no package.
            // Skipped entirely under reduced motion (§2.7.1).
            if (!reduced && !_confettiSuppressed)
              const Positioned.fill(
                child: IgnorePointer(child: _ConfettiOverlay()),
              ),
          ],
        ),
      ),
    );
  }

  /// Play Again (D-02): a fresh match with the exact settings of the
  /// finished match. Removes everything above Home and opens the
  /// game route with those settings, so the stack becomes
  /// Home → Game and back from the new match lands on Home.
  void _playAgain(BuildContext context, GameSetup setup) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.game,
      ModalRoute.withName(AppRoutes.home),
      arguments: setup,
    );
  }

  /// Main Menu (D-30): Home, exactly once. When a Home route is
  /// below Results — the normal shape, because the game screen
  /// navigates here with `pushNamedAndRemoveUntil` keeping Home —
  /// a single `pop()` returns to that existing Home. That matters
  /// beyond the pop count: Home offers the resume dialog exactly
  /// once per Home lifetime from the frozen startup snapshot
  /// outcome, so returning to the existing Home never re-offers
  /// resume for the match that just finished (its snapshot was
  /// deleted at completion). Pushing a fresh Home instead would
  /// re-offer that stale snapshot, and resuming it would record
  /// the finished match a second time. Only when nothing is below
  /// Results (a deep link straight to the game route) is a fresh
  /// Home pushed instead, so Main Menu can never strand the user
  /// on an empty stack.
  void _goHome(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
    }
  }

  /// Total-minutes `mm:ss` ("01:35", "65:00"): the duration the
  /// remediation plan's M2.5 criterion requires, and > 00:00 for any
  /// real match.
  static String _formatDuration(Duration duration) {
    final totalSeconds = duration.isNegative ? 0 : duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  /// Short date without the intl package ("21 Nov 2026, 12:00") —
  /// the same format the history screen uses.
  static String _formatDate(DateTime date, AppLocalizations l10n) {
    final months = monthNames(l10n);
    final local = date.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, '
        '$hour:$minute';
  }
}

/// One slice of the entrance choreography (M3 premium, §2.6.1):
/// fades [child] in over [interval] of the parent controller, with
/// an optional 12 dp rise. Reading the controller value directly
/// (rather than a [Tween]) keeps the stagger explicit and the
/// reduced-motion jump (value 1.0) correct.
class _Entrance extends StatelessWidget {
  const _Entrance({
    required this.controller,
    required this.interval,
    required this.child,
    this.slideUp = false,
  });

  final AnimationController controller;
  final Interval interval;
  final Widget child;
  final bool slideUp;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = interval.transform(controller.value);
        return Opacity(
          opacity: t,
          child: slideUp
              ? Transform.translate(
                  offset: Offset(0, 12 * (1 - t)),
                  child: child,
                )
              : child,
        );
      },
      child: child,
    );
  }
}

/// DiceUp's winner's mark (M3 premium, §2.6.2/Q5): the winner's
/// avatar in a teal ring, with the per-seat shape marker enlarged
/// (30 dp, vs the avatar's own 27 dp badge) overlapping the ring's
/// lower-right edge. No crown — Ludo King's crown is its brand;
/// the shape system (D-27) is DiceUp's own mark. The whole mark
/// scales in from 0.8 → 1.0 with an `outBack` overshoot over the
/// entrance controller's 0.15–0.75 slice.
class _WinnerAvatar extends StatelessWidget {
  const _WinnerAvatar({required this.result, required this.entrance});

  final MatchResult result;

  /// The results screen's entrance controller: the avatar scales
  /// in over its 0.15–0.75 slice.
  final AnimationController entrance;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: entrance,
      builder: (context, child) {
        final t = const Interval(
          0.15,
          0.75,
          curve: Curves.easeOutBack,
        ).transform(entrance.value);
        return Transform.scale(scale: 0.8 + 0.2 * t, child: child);
      },
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: DiceUpColors.teal, width: 3),
                boxShadow: DiceUpShadows.lifted,
              ),
            ),
            PlayerAvatar(
              name: result.winnerName,
              seatIndex: result.winnerSeat,
              colour: result.winnerColour,
              radius: 36,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: PlayerShapeMarker(
                key: const ValueKey('winner-shape-marker'),
                shape: PlayerShape.forSeat(result.winnerSeat),
                color: DiceUpColors.forColour(result.winnerColour),
                size: 30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-shot hand-drawn confetti (M3 premium, §2.6.3/Q5): ~36 small
/// navy/teal/amber/player-colour rectangles falling from the top of
/// the results screen over ~1.2 s, drawn by a [CustomPainter] — no
/// `confetti` / Lottie package (§3). Deterministic (seeded random),
/// so the same entry always renders the same burst. Fires once on
/// entry, never loops; the controller is finite, so `pumpAndSettle`
/// terminates.
class _ConfettiOverlay extends StatefulWidget {
  const _ConfettiOverlay();

  @override
  State<_ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<_ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiPiece> _pieces;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    final random = math.Random(20261122);
    _pieces = List.generate(36, (_) => _ConfettiPiece.random(random));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) =>
          CustomPaint(painter: _ConfettiPainter(_pieces, _controller.value)),
    );
  }
}

/// One confetti piece: a fixed horizontal slot, a start delay and a
/// fall length (fractions of the 1.2 s burst), a size, a colour, a
/// spin and a sway phase. All fixed at construction (seeded random),
/// so the burst is deterministic.
class _ConfettiPiece {
  _ConfettiPiece({
    required this.x,
    required this.delay,
    required this.fall,
    required this.size,
    required this.color,
    required this.spin,
    required this.phase,
  });

  factory _ConfettiPiece.random(math.Random random) {
    const colors = [
      DiceUpColors.navy,
      DiceUpColors.teal,
      DiceUpColors.amber,
      ...DiceUpColors.playerColors,
    ];
    return _ConfettiPiece(
      x: random.nextDouble(),
      delay: random.nextDouble() * 0.25,
      fall: 0.6 + random.nextDouble() * 0.35,
      size: 5 + random.nextDouble() * 4,
      color: colors[random.nextInt(colors.length)],
      spin: (random.nextDouble() - 0.5) * 12,
      phase: random.nextDouble() * 2 * math.pi,
    );
  }

  final double x;
  final double delay;
  final double fall;
  final double size;
  final Color color;
  final double spin;
  final double phase;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.progress);

  final List<_ConfettiPiece> pieces;

  /// 0.0 → 1.0 over the ~1.2 s burst.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      final local = ((progress - piece.delay) / piece.fall).clamp(0.0, 1.0);
      if (local <= 0.0) continue;
      final y = -12 + local * (size.height + 24);
      final x =
          piece.x * size.width +
          math.sin(local * math.pi * 2 + piece.phase) * 8;
      final opacity = local > 0.8 ? (1.0 - local) / 0.2 : 1.0;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(piece.phase + local * piece.spin);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: piece.size,
          height: piece.size * 0.6,
        ),
        Paint()..color = piece.color.withValues(alpha: opacity),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.pieces != pieces;
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DiceUpSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: DiceUpColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.isWinner});

  final MatchResultPlayer player;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    return Row(
      children: [
        PlayerAvatar(
          name: player.name,
          seatIndex: player.seat,
          colour: player.colour,
          radius: 16,
        ),
        const SizedBox(width: DiceUpSpacing.sm),
        Expanded(
          child: Text(
            player.isAi ? l10n.playerWithAi(player.name) : player.name,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        // Tokens-home count (M3 premium, §2.6.4/Q8): the only
        // record on the results screen of how close the losers
        // were — the game screen's chips already show it, and the
        // game screen derives it from the final state.
        Text(
          l10n.resultsPlayerHome(player.tokensHome),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: DiceUpColors.textSecondary),
        ),
        if (isWinner) ...[
          const SizedBox(width: DiceUpSpacing.sm),
          Text(
            l10n.resultsWinnerBadge,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: DiceUpColors.teal),
          ),
        ],
      ],
    );
  }
}
