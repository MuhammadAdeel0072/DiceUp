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
}
