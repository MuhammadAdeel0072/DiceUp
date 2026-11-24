import 'package:flutter/animation.dart';

/// DiceUp motion tokens (premium redesign v2).
///
/// One place for every *UI-only* duration and curve: screen-to-screen
/// transitions, press feedback and turn-handover crossfades read from
/// here, so the app never improvises a duration per widget.
///
/// Gameplay animation budgets are deliberately NOT tokens: the game
/// screen's controllers (540 ms dice tumble, ~110 ms per-cell steps with
/// the 250–600 ms cap, 600 ms capture return, 1,500 ms last-moved ring,
/// 1,200 ms one-shot legal-move pulse, 150 ms illegal-tap shake) are
/// pinned by `test/animation_test.dart` and
/// `test/premium_animation_test.dart`, and the premium redesign does not
/// touch them. Those controllers stay in `game_screen.dart`, unchanged.
///
/// Reduced motion (Android "Remove animations" / iOS Reduce Motion): a
/// token never decides by itself. Every consumer collapses its duration
/// to zero through `isReducedMotion(context)` — the same rule the M3
/// premium work established (`core/accessibility/reduced_motion.dart`).
abstract final class DiceUpMotion {
  /// Instant state swap: reduced-motion crossfades collapse to this.
  static const Duration instant = Duration.zero;

  /// Micro feedback — border/colour crossfades on the dice face, the
  /// banner accent handover, chip state handovers.
  static const Duration fast = Duration(milliseconds: 150);

  /// Standard UI transition — press feedback, small fades.
  static const Duration base = Duration(milliseconds: 200);

  /// Emphasis transitions — screen entrances, card rises.
  static const Duration smooth = Duration(milliseconds: 300);

  /// The standard ease-out for enters and handovers.
  static const Curve enter = Curves.easeOutCubic;

  /// Gentle ease-out for settle-down states (pressed release).
  static const Curve settle = Curves.easeOut;

  /// The overshoot for playful pops (winner mark, brand mark entrance).
  static const Curve pop = Curves.easeOutBack;

  /// The scale a card or button settles to while pressed
  /// ([PressableScale]). Subtle by design: a press must feel
  /// acknowledged, never like the control moved away from the finger.
  static const double pressedScale = 0.97;
}
