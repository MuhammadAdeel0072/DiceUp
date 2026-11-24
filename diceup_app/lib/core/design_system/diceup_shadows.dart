import 'package:flutter/material.dart';

/// Named shadow tokens (M3 premium, research §2.7.4).
///
/// The app already used the same shadow values ad hoc in several
/// places (dice `blur 6, offset (0, 3)`; card elevation 2). These
/// named values are the only shadows M3 polish may use, so a
/// third shadow is never invented per widget. No new colours:
/// shadows stay black at low alpha — no colour shadows, no glow.
abstract final class DiceUpShadows {
  /// Raised surfaces — the board and the dice at rest. The dice's
  /// original ad-hoc shadow, named.
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 3)),
  ];

  /// A token mid-hop / mid-capture, and the winner's avatar on the
  /// results screen: a slightly larger, softer shadow than
  /// [raised], so the lifted piece reads as above the board.
  static const List<BoxShadow> lifted = [
    BoxShadow(color: Color(0x26000000), blurRadius: 10, offset: Offset(0, 5)),
  ];

  /// The board as an object on the navy table field (redesign
  /// Stage 2, REDESIGN-PLAN.md §4): one soft, deep shadow under
  /// the framed board. Larger and softer than [lifted] so the
  /// board reads as sitting *on* the table; still black at low
  /// alpha, still no glow.
  static const List<BoxShadow> table = [
    BoxShadow(color: Color(0x40000000), blurRadius: 16, offset: Offset(0, 8)),
  ];

  // Premium redesign v2 additions. Same discipline as above: black
  // (or navy-black) at low alpha, never coloured glow. These are
  // additive tokens — existing call sites keep the shadows they had.

  /// Primary actions: a low, tight drop under the CTA so the button
  /// reads as a raised physical key rather than a flat rectangle.
  /// Pairs with the button's own press scale (see [PressableScale]).
  static const List<BoxShadow> button = [
    BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4)),
  ];

  /// Surfaces floating over scrolling content (dialogs, the dice
  /// tray on tall screens): a step above [raised], below [lifted].
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x24000000), blurRadius: 12, offset: Offset(0, 6)),
  ];

  /// The thin dark rim drawn around the board frame on the table
  /// field (premium v2, gameplay F2): a zero-blur spread shadow that
  /// reads as the board's edge, layered under [table].
  static const List<BoxShadow> boardRim = [
    BoxShadow(color: Color(0x59000000), blurRadius: 0, spreadRadius: 1.5),
  ];
}
