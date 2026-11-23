import 'package:flutter/material.dart';

import 'diceup_colors.dart';
import 'diceup_spacing.dart';
import 'diceup_typography.dart';

/// DiceUp Material 3 theme (SDD §11.1).
///
/// Light theme is the Phase 2 baseline. There is no dark theme:
/// the earlier comment promising one ("added with the settings
/// screen") was removed in M2.14 (L-04) — implementing a dark theme
/// is more than a small fix and is not approved M2.14 scope, so the
/// comment was deleted rather than left promising work that does
/// not exist. No widget hard-codes a light-only colour — widgets
/// read the theme or [DiceUpColors] tokens.
///
/// Redesign Stage 2 (REDESIGN-PLAN.md §4): the theme is rebuilt
/// from the new tokens so dialogs and SnackBars stop looking stock.
/// The navy game field is an *environment*, not a dark theme —
/// [DiceUpColors.table] is used by the game screen directly, never
/// as a theme surface, so this theme stays a light theme throughout.
abstract final class DiceUpTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: DiceUpColors.teal,
      primary: DiceUpColors.teal,
      secondary: DiceUpColors.gold,
      surface: DiceUpColors.surface,
      onSurface: DiceUpColors.textPrimary,
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
          // Disabled must be unmistakable (F8): a disabled primary
          // action is flat grey on grey, never a dimmed teal that
          // could read as "almost rollable". The disabled greys are
          // the only use of the old #64748B (see DiceUpColors).
          disabledBackgroundColor: DiceUpColors.disabledBackground,
          disabledForegroundColor: DiceUpColors.disabledForeground,
          // Finite minimum width: Size.fromHeight (infinite width) breaks
          // buttons placed in a Row, e.g. next to the dice.
          minimumSize: const Size(88, DiceUpSpacing.minTouchTarget),
          padding: DiceUpSpacing.buttonPadding,
          shape: const RoundedRectangleBorder(
            borderRadius: DiceUpSpacing.radiusMdBorder,
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DiceUpColors.teal,
          disabledForegroundColor: DiceUpColors.disabledForeground,
          side: const BorderSide(color: DiceUpColors.teal, width: 1.5),
          // Finite minimum width — see the elevated button note above.
          minimumSize: const Size(88, DiceUpSpacing.minTouchTarget),
          padding: DiceUpSpacing.buttonPadding,
          shape: const RoundedRectangleBorder(
            borderRadius: DiceUpSpacing.radiusMdBorder,
          ),
        ),
      ),
      // M2.3 (NFR-08, D-21): the remaining button kinds get the same
      // 48 dp minimum explicitly, as theme tokens — not left to the
      // framework default. Measured under Flutter 3.50.1 the rendered
      // heights already met 48 dp, so these entries pin the
      // requirement rather than fixing a currently failing size;
      // `test/accessibility_test.dart` asserts the token as well as
      // the rendered size. SegmentedButton's minimum applies per
      // segment (each segment is its own tap target).
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(48, DiceUpSpacing.minTouchTarget),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          disabledForegroundColor: DiceUpColors.disabledForeground,
          // 64 dp is Material's default minimum width for a text
          // button; only the height is raised to the NFR-08 floor.
          minimumSize: const Size(64, DiceUpSpacing.minTouchTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DiceUpColors.surface,
        hintStyle: const TextStyle(color: DiceUpColors.textSecondary),
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
      // Dialogs (redesign Stage 2, F7): ivory surface and the 16 dp
      // card radius, so a dialog reads as part of the app instead of
      // a stock Material popup. The navy title comes from
      // [DiceUpTypography.titleLarge] recoloured here; content uses
      // bodyMedium.
      dialogTheme: const DialogThemeData(
        backgroundColor: DiceUpColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: DiceUpSpacing.radiusDialogBorder,
        ),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: DiceUpColors.navy,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: DiceUpColors.textPrimary,
          height: 1.5,
        ),
      ),
      // SnackBars (redesign Stage 2, F8): the app's navy surface
      // instead of the stock dark-grey bar, floating with the card
      // radius, white content text and a white action (14.11:1 on
      // navy, AA) so an error is not bare text. Gold is not used
      // for the action: at 4.50:1 on navy it sits exactly on the AA
      // line, too marginal for interactive text.
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: DiceUpColors.navy,
        contentTextStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Colors.white,
        ),
        actionTextColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: DiceUpSpacing.radiusMdBorder,
        ),
      ),
    );
  }
}
