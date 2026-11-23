import 'package:flutter/material.dart';

import '../../core/accessibility/reduced_motion.dart';
import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_shadows.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../l10n/app_strings.dart';

/// A dice face drawn with widgets — no image asset, no emoji.
///
/// [value] 1–6 renders the matching pip layout; null renders a blank
/// face (before the first roll). [rolling] shows a shimmer while the
/// roll animation runs. The tumble is AnimationController-driven
/// (M2.7, CON-01): the game screen owns a 540 ms tumble controller
/// and cycles the displayed face from its value while the engine's
/// decided value is pending; when the tumble ends the face is the
/// engine's value, never a random one. The domain controller keeps
/// its 6 x 90 ms timer as the state-timing authority (the domain
/// layer cannot own a Ticker), so the two run the same 540 ms and
/// settle together.
///
/// Tappable dice (M2.8, FR-21/UC-01 step 4): when [onTap] is given
/// the dice is wrapped in a [GestureDetector] and taps the dice the
/// same as the Roll button — the screen's handler applies the same
/// guards (human turn, awaiting a roll, not rolling, not paused)
/// and the controller's own guards are the second line of defence,
/// so a tap racing the tumble start is ignored, never queued.
/// [enabled] is visual only (full opacity + a 'Tap to roll' tooltip
/// when a roll is available, dimmed when it is not — AI turn,
/// rolling, paused, finished); it never decides whether a tap
/// rolls — the handler does that, so a tap on the dimmed dice still
/// gets the brief illegal-tap feedback instead of silence. The dice
/// stays 64 dp (D-09: already above the 48 dp control minimum).
///
/// Semantics (M2.9, NFR-08; the M2.8 row's deferred item): the dice
/// always carries one semantics node — 'Dice, tap to roll' before
/// the first roll, 'Dice, showing X. Tap to roll' while a roll is
/// available, 'Dice, showing X' when it is not, 'Dice, rolling'
/// mid-tumble — with a button role + tap action exactly when
/// [onTap] is given, so a screen reader can roll from the dice.
/// The pips are decorative (no semantics of their own) and are
/// excluded: the label is the node's whole content, never the
/// tooltip text plus a pip count.
class DiceWidget extends StatelessWidget {
  const DiceWidget({
    super.key,
    required this.value,
    this.size = 64,
    this.rolling = false,
    this.enabled = true,
    this.onTap,
    this.showRollableBorder = false,
  });

  final int? value;
  final double size;
  final bool rolling;

  /// Whether a roll is available right now (visual state only —
  /// see the class doc). Defaults to true so a bare dice renders
  /// at full opacity.
  final bool enabled;

  /// Tap handler (the screen's roll-or-feedback handler, M2.8).
  /// Null renders a plain, untappable dice.
  final VoidCallback? onTap;

  /// Rollable affordance (M3 premium, research §2.4.4; restyled
  /// in the Stage 2 redesign, F4): when a roll is available the
  /// dice carries a 2.5 dp teal border and the lifted shadow, so
  /// the dice has a visible "your turn" state that does not depend
  /// on reading the banner. It is a steady border, not an
  /// oscillating one: an oscillating border needs a continuously
  /// repeating ticker, and a running ticker makes `pumpAndSettle`
  /// (which the game-screen suite uses throughout) never
  /// terminate — the same reason the legal-move pulse is one-shot
  /// (see game_screen). A slow repeating border is the named
  /// revisit if the harness ever moves off `pumpAndSettle`.
  final bool showRollableBorder;

  static const _pipLayouts = <int, List<Alignment>>{
    1: [Alignment.center],
    2: [Alignment.topLeft, Alignment.bottomRight],
    3: [Alignment.topLeft, Alignment.center, Alignment.bottomRight],
    4: [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ],
    5: [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.center,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ],
    6: [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.centerLeft,
      Alignment.centerRight,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ],
  };

  @override
  Widget build(BuildContext context) {
    final pips = value == null ? const <Alignment>[] : _pipLayouts[value]!;
    // Dice states (Stage 2 redesign, F4): the dice must feel
    // rollable from its rest state alone — no looping pulse is
    // allowed (a repeating ticker breaks `pumpAndSettle`, see the
    // [showRollableBorder] doc), so the states themselves carry
    // the meaning. Rollable: white face, lifted shadow, 2.5 dp
    // teal border. Rolling: the same lifted treatment at 0.6
    // opacity while the tumble runs. Inert: a muted ivory face,
    // the raised shadow and a thin border at 0.45 opacity — flat
    // and clearly not tappable, never a dimmed teal that could
    // read as "almost rollable".
    final rollable = showRollableBorder && !rolling;
    final dice = AnimatedOpacity(
      // Rolling dims the dice while the tumble runs; a dice that
      // cannot be rolled right now (AI turn, paused, finished) is
      // dimmed further so it reads as disabled, not tappable.
      opacity: rolling ? 0.6 : (enabled ? 1.0 : 0.45),
      duration: const Duration(milliseconds: 120),
      // Stage 4 polish: the face itself crossfades between its
      // states (border width/colour, shadow, face colour) instead
      // of snapping when the turn changes — the dice visibly
      // settles into "your turn" or "not yours". 150 ms, inside
      // the 100–250 ms UI-feedback budget; instant under reduced
      // motion. The 540 ms tumble budget and the steady (never
      // oscillating) rollable border are untouched.
      child: AnimatedContainer(
        duration: isReducedMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: enabled || rolling ? Colors.white : DiceUpColors.surfaceMuted,
          borderRadius: DiceUpSpacing.radiusMdBorder,
          border: Border.all(
            color: rollable || rolling
                ? DiceUpColors.teal
                : DiceUpColors.border,
            width: rollable ? 2.5 : 1.5,
          ),
          boxShadow: rollable || rolling
              ? DiceUpShadows.lifted
              : DiceUpShadows.raised,
        ),
        child: Stack(
          children: pips
              .map(
                (alignment) => Align(
                  alignment: alignment,
                  child: Padding(
                    padding: EdgeInsets.all(size * 0.14),
                    child: Container(
                      width: size * 0.16,
                      height: size * 0.16,
                      decoration: const BoxDecoration(
                        color: DiceUpColors.navy,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
    final onTap = this.onTap;
    final l10n = stringsOf(context);
    final tappable = onTap == null
        ? dice
        : GestureDetector(
            onTap: onTap,
            // The tooltip names the affordance only while a roll is
            // available — a dimmed dice must not promise a tap that
            // cannot roll. The handler (not this widget) decides whether
            // the tap rolls or gets illegal-tap feedback.
            child: enabled
                ? Tooltip(message: l10n.diceTapToRoll, child: dice)
                : dice,
          );
    // Semantics (M2.9): one labelled node for the whole dice. The
    // label names the state — a mid-tumble face is a passing frame,
    // never the decided value, so it reads 'rolling', not a number;
    // before the first roll there is no value to show. The button
    // role + tap action exist exactly when the dice is tappable, so
    // a screen-reader activation rolls (or gets the same brief
    // feedback a sighted tap gets) through the same handler.
    final label = rolling
        ? l10n.diceRolling
        : value == null
        ? (enabled ? l10n.diceTapToRollLabel : l10n.diceNoRollYet)
        : (enabled ? l10n.diceShowingTap(value!) : l10n.diceShowing(value!));
    return Semantics(
      label: label,
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: tappable,
    );
  }
}
