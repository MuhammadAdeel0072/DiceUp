import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';

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
class DiceWidget extends StatelessWidget {
  const DiceWidget({
    super.key,
    required this.value,
    this.size = 64,
    this.rolling = false,
    this.enabled = true,
    this.onTap,
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
    final dice = AnimatedOpacity(
      // Rolling dims the dice while the tumble runs; a dice that
      // cannot be rolled right now (AI turn, paused, finished) is
      // dimmed further so it reads as disabled, not tappable.
      opacity: rolling ? 0.6 : (enabled ? 1.0 : 0.45),
      duration: const Duration(milliseconds: 120),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.18),
          border: Border.all(color: DiceUpColors.border, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
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
    if (onTap == null) return dice;
    // The tooltip names the affordance only while a roll is
    // available — a dimmed dice must not promise a tap that
    // cannot roll. The handler (not this widget) decides whether
    // the tap rolls or gets illegal-tap feedback.
    final tappable = enabled
        ? Tooltip(message: 'Tap to roll', child: dice)
        : dice;
    return GestureDetector(onTap: onTap, child: tappable);
  }
}
