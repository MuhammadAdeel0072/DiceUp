import 'package:flutter/material.dart';

import 'diceup_colors.dart';
import 'diceup_spacing.dart';
import 'diceup_typography.dart';

/// DiceUp Material 3 theme (SDD §11.1).
///
/// Light theme is the Phase 2 baseline. A dark theme follows the same
/// tokens (navy surfaces, teal accents) and is added with the settings
/// screen; no widget hard-codes a light-only colour — widgets read the
/// theme or [DiceUpColors] tokens.
abstract final class DiceUpTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: DiceUpColors.teal,
      primary: DiceUpColors.teal,
      secondary: DiceUpColors.amber,
      surface: DiceUpColors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: DiceUpColors.background,
      textTheme: DiceUpTypography.textTheme(scheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: DiceUpColors.navy,
        foregroundColor: DiceUpColors.textOnDark,
        centerTitle: true,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DiceUpColors.teal,
          foregroundColor: Colors.white,
          // Finite minimum width: Size.fromHeight (infinite width) breaks
          // buttons placed in a Row, e.g. next to the dice.
          minimumSize:
              const Size(88, DiceUpSpacing.minTouchTarget),
          padding: DiceUpSpacing.buttonPadding,
          shape: const RoundedRectangleBorder(
            borderRadius: DiceUpSpacing.radiusMdBorder,
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DiceUpColors.teal,
          side: const BorderSide(color: DiceUpColors.teal, width: 1.5),
          // Finite minimum width — see the elevated button note above.
          minimumSize:
              const Size(88, DiceUpSpacing.minTouchTarget),
          padding: DiceUpSpacing.buttonPadding,
          shape: const RoundedRectangleBorder(
            borderRadius: DiceUpSpacing.radiusMdBorder,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DiceUpColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DiceUpSpacing.md,
          vertical: DiceUpSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: DiceUpSpacing.radiusMdBorder,
          borderSide: const BorderSide(color: DiceUpColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: DiceUpSpacing.radiusMdBorder,
          borderSide: const BorderSide(color: DiceUpColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: DiceUpSpacing.radiusMdBorder,
          borderSide: const BorderSide(color: DiceUpColors.teal, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: DiceUpSpacing.radiusMdBorder,
          borderSide: const BorderSide(color: DiceUpColors.error),
        ),
      ),
      cardTheme: const CardThemeData(
        color: DiceUpColors.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: DiceUpSpacing.radiusLgBorder,
        ),
        margin: EdgeInsets.zero,
      ),
    );
  }
}
