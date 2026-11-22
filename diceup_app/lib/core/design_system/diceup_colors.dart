import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/engine/player_colour.dart';

/// DiceUp brand colours (SDD §11.1 — visual identity).
///
/// One palette for the whole app. No screen invents its own colours.
/// Player colours are the four Ludo colours; each player is also given a
/// distinct token *shape* (see [PlayerShape] in the board widgets) so game
/// information is never carried by colour alone (SRS NFR-08).
abstract final class DiceUpColors {
  // Brand — taken from the SDD document palette.
  static const Color navy = Color(0xFF1B2A4E);
  static const Color teal = Color(0xFF0E7C7B);
  static const Color amber = Color(0xFFD97706);
  static const Color amberLight = Color(0xFFFEF3C7);

  // Surfaces (light theme).
  static const Color background = Color(0xFFF6F7F9);
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF1F5F9);
  static const Color border = Color(0xFFE2E8F0);

  // Text.
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textOnDark = Colors.white;

  // Feedback.
  static const Color error = Color(0xFFB91C1C);

  // Ludo player colours (order: Red, Green, Yellow, Blue).
  static const List<Color> playerColors = [
    Color(0xFFE5484D), // red
    Color(0xFF2FA866), // green
    Color(0xFFF5B301), // yellow
    Color(0xFF2F6FED), // blue
  ];

  static Color playerColor(int seatIndex) =>
      playerColors[seatIndex % playerColors.length];

  /// WCAG 2.x contrast ratio between two opaque colours (1.0–21.0).
  ///
  /// Used by the D-27 avatar tests (M2.4): the avatar initial is navy
  /// on white for every seat, so the ratio is the same whatever the
  /// player's ring colour is — navy on white is 14.11:1, comfortably
  /// above the AA 4.5:1 floor. Alpha is ignored: callers pass opaque
  /// colours (the avatar disc is opaque white, the initial opaque navy).
  static double contrastRatio(Color a, Color b) {
    final l1 = _relativeLuminance(a);
    final l2 = _relativeLuminance(b);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _relativeLuminance(Color color) {
    double channel(double c) => c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  /// The display colour for a chosen [PlayerColour] (M2.2).
  ///
  /// [playerColors] is ordered to match [PlayerColour.values] (red,
  /// green, yellow, blue), so the mapping is by index. Use this —
  /// never [playerColor] — when the colour comes from a player's
  /// chosen colour rather than their seat: after a colour swap the
  /// seat and the colour no longer agree.
  static Color forColour(PlayerColour colour) =>
      playerColors[colour.index % playerColors.length];
}
