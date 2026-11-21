import 'package:flutter/material.dart';

import 'diceup_colors.dart';

/// DiceUp typography hierarchy (SDD §11.1).
///
/// Body text is never below 14sp (SRS NFR-08). The app uses the platform
/// default font family deliberately: no custom font files are bundled in
/// Phase 2, so there is no asset to go missing. A display font can be
/// introduced later through this file alone.
abstract final class DiceUpTypography {
  static const String _fontFamily = 'Roboto';

  static TextTheme textTheme(ColorScheme scheme) {
    return TextTheme(
      displayLarge: const TextStyle(
        fontFamily: _fontFamily,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: DiceUpColors.textPrimary,
        height: 1.2,
      ),
      headlineMedium: const TextStyle(
        fontFamily: _fontFamily,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: DiceUpColors.textPrimary,
        height: 1.25,
      ),
      titleLarge: const TextStyle(
        fontFamily: _fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: DiceUpColors.textPrimary,
      ),
      titleMedium: const TextStyle(
        fontFamily: _fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: DiceUpColors.textPrimary,
      ),
      bodyLarge: const TextStyle(
        fontFamily: _fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: DiceUpColors.textPrimary,
        height: 1.5,
      ),
      bodyMedium: const TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: DiceUpColors.textPrimary,
        height: 1.5,
      ),
      labelLarge: const TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: DiceUpColors.textPrimary,
      ),
      bodySmall: const TextStyle(
        fontFamily: _fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: DiceUpColors.textSecondary,
      ),
    );
  }
}
