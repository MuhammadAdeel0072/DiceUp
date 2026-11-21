import 'package:flutter/material.dart';

/// DiceUp brand colours (SDD §11.1 — visual identity).
///
/// One palette for the whole app. No screen invents its own colours.
/// Player colours are the four Ludo colours; each player is also given a
/// distinct token *shape* (see [PlayerShape] in the board widgets) so game
/// information is never carried by colour alone (SRS NFR-08).
abstract final class DiceUpColors {
  // Brand — taken from the SDD document palette.
  static const Color navy = Color(0xFF1B2A4E);
  static const Color navyDark = Color(0xFF121D36);
  static const Color teal = Color(0xFF0E7C7B);
  static const Color tealDark = Color(0xFF0A5E5D);
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
  static const Color success = Color(0xFF15803D);
  static const Color error = Color(0xFFB91C1C);
  static const Color errorBackground = Color(0xFFFEE2E2);

  // Ludo player colours (order: Red, Green, Yellow, Blue).
  static const List<Color> playerColors = [
    Color(0xFFE5484D), // red
    Color(0xFF2FA866), // green
    Color(0xFFF5B301), // yellow
    Color(0xFF2F6FED), // blue
  ];

  static Color playerColor(int seatIndex) =>
      playerColors[seatIndex % playerColors.length];
}
