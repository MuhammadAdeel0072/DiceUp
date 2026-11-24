import 'package:flutter/material.dart';

import '../accessibility/reduced_motion.dart';
import 'diceup_colors.dart';
import 'diceup_motion.dart';
import 'diceup_shadows.dart';

/// DiceUp presentation decor (premium redesign v2).
///
/// The environment layers the previous redesign introduced — the navy
/// game `table` field and the warm ivory out-of-game world — upgraded
/// from flat fills to quiet, layered washes. Everything here is
/// *static*: no tickers, no continuously repeating animations (the
/// test harness settles with `pumpAndSettle` throughout), no blur
/// layers, no extra semantics nodes — the backgrounds and the brand
/// mark are decoration, and screens keep labelling their content.
///
/// Contrast rules are unchanged: text never sits on the washes at a
/// lower ratio than the base fields it replaces ([DiceUpColors.table]
/// for dark, [DiceUpColors.background] for light), because every wash
/// colour is drawn at very low alpha over exactly those base colours.
/// The white-on-navy and slate-on-ivory assertions in
/// `test/design_system_test.dart` keep holding.

/// The navy table field with depth: a deep indigo vignette behind the
/// board, one faint teal wash upper-left and one faint gold wash
/// lower-right, so the game screen reads as a lit table rather than a
/// flat rectangle. Decorative — paint it behind content (as a
/// `Positioned.fill` in a Stack, or wrapping a hero panel); it draws
/// nothing interactive and adds no semantics.
class TableBackground extends StatelessWidget {
  const TableBackground({super.key, this.child});

  /// Optional content painted above the washes.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: DiceUpColors.table,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            DiceUpColors.table,
            DiceUpColors.navy,
          ],
          stops: [0.55, 1.0],
        ),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.7, -0.8),
            radius: 1.1,
            colors: [
              Color(0x1F0E7C7B), // teal at ~12% alpha
              Color(0x000E7C7B), // fading to nothing
            ],
            stops: [0.0, 1.0],
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.8, 0.9),
              radius: 1.0,
              colors: [
                Color(0x2EB08D2E), // gold at ~18% alpha
                Color(0x00B08D2E),
              ],
              stops: [0.0, 1.0],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The warm ivory world out of game: the page background with two
/// very quiet colour washes (teal upper-left, gold lower-right) so
/// home, history, statistics and settings stop reading as flat form
/// screens while every existing text/surface contrast keeps holding
/// (the washes never exceed ~10% alpha over [DiceUpColors.background]).
class IvoryBackground extends StatelessWidget {
  const IvoryBackground({super.key, this.child});

  /// Optional content painted above the washes.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: DiceUpColors.background),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.8, -0.9),
            radius: 1.2,
            colors: [
              Color(0x140E7C7B), // teal at ~8% alpha
              Color(0x000E7C7B),
            ],
            stops: [0.0, 1.0],
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.85, 0.95),
              radius: 1.1,
              colors: [
                Color(0x1AB08D2E), // gold at ~10% alpha
                Color(0x00B08D2E),
              ],
              stops: [0.0, 1.0],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The DiceUp brand mark (premium redesign v2): a rounded ivory die
/// with five navy pips, a gold ring and the lifted shadow — the one
/// logo moment of the app, used on the splash and the home hero.
///
/// Pure widgets (no image asset, no painter): sizes scale with
/// [size]. Decorative — callers keep labelling the screen themselves
/// (the app name next to it is the accessible name).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 64});

  /// Edge length of the die. Pips and radii derive from it, so the
  /// mark renders crisply from 40 dp (home) to 96 dp (splash).
  final double size;

  @override
  Widget build(BuildContext context) {
    final pip = size * 0.13;
    final pipGap = size * 0.62; // pip centre distance scale from mid
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: DiceUpColors.surface,
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: DiceUpColors.gold, width: size * 0.045),
        boxShadow: DiceUpShadows.lifted,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, DiceUpColors.ivory],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 5-pip face: four corners + centre, matching the dice
          // widget's five layout (no emoji, no asset).
          for (final offset in _pipOffsets)
            Transform.translate(
              offset: offset * pipGap,
              child: Container(
                width: pip,
                height: pip,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: DiceUpColors.navy,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0x331B2A4E),
                      blurRadius: pip * 0.35,
                      offset: Offset(0, pip * 0.14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The five-pip layout of the brand mark, in pip-gap units relative
/// to the die's centre (see [BrandMark]).
const List<Offset> _pipOffsets = [
  Offset(-0.62, -0.62),
  Offset(0.62, -0.62),
  Offset(0.0, 0.0),
  Offset(-0.62, 0.62),
  Offset(0.62, 0.62),
];

/// Press feedback wrapper (premium redesign v2, §6B): scales its
/// child down slightly while a pointer is down, back to full size on
/// release — every interactive surface acknowledges the touch even
/// where the child has no ink ripple of its own (mode cards, the
/// board frame, big CTAs).
///
/// Built on a raw [Listener], not a gesture recognizer: it observes
/// pointer down/up without ever entering the gesture arena, so the
/// child's own taps (InkWell, buttons, the board's tap-down
/// hit-testing) keep winning unchanged. The scale animates with
/// [DiceUpMotion.fast] via an implicit [AnimatedScale], which
/// schedules frames only while the value changes — at rest nothing
/// ticks, so `pumpAndSettle` stays safe.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  /// Set false for surfaces that must not respond (disabled actions,
  /// the inert online card) — the child renders at full size always.
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.enabled
          ? (_) {
              if (mounted) setState(() => _pressed = true);
            }
          : null,
      onPointerUp: (_) {
        if (mounted) setState(() => _pressed = false);
      },
      onPointerCancel: (_) {
        if (mounted) setState(() => _pressed = false);
      },
      child: AnimatedScale(
        scale: _pressed ? DiceUpMotion.pressedScale : 1.0,
        duration: isReducedMotion(context)
            ? DiceUpMotion.instant
            : DiceUpMotion.fast,
        curve: _pressed ? DiceUpMotion.settle : DiceUpMotion.pop,
        child: widget.child,
      ),
    );
  }
}
