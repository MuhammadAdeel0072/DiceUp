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
///
/// Premium redesign v2: the same tokens, finished to a game-quality
/// sheen — buttons carry depth (elevation + shadow, transparent
/// surface tint), switches/sliders/progress/dividers/tooltips speak
/// the palette instead of the Material defaults, and every named
/// route moves with one finite fade-and-rise transition (the
/// [_FadeThroughTransitionsBuilder], which also honours reduced
/// motion). Nothing asserted by `test/design_system_test.dart`
/// changed: the pinned surfaces (dialog ivory/16, snackbar navy,
/// scaffold ivory, teal/disabled button colours, 48 dp minimums)
/// are identical — v2 only adds field-level polish the tests do not
/// pin.
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
          // v2 depth: a raised key, not a flat rectangle. The
          // background colours above are unchanged (the design
          // system test pins them); only elevation/shadow/tint are
          // added. [PrimaryButton] layers the press scale on top.
          elevation: 2,
          shadowColor: const Color(0x33000000),
          surfaceTintColor: Colors.transparent,
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
        // v2: the M3 surface tint (a primary-coloured overlay that
        // Material 3 layers on elevated cards) washed the ivory
        // cards teal; transparent keeps the surfaces exactly the
        // ivory the design system promises.
        surfaceTintColor: Colors.transparent,
      ),
      // v2 form-control polish: the sliders, switches, spinners,
      // dividers and tooltips speak the palette instead of the
      // Material defaults. None of these carry text, so no contrast
      // contract moves; the switch/slider act in the action colour.
      sliderTheme: const SliderThemeData(
        activeTrackColor: DiceUpColors.teal,
        inactiveTrackColor: DiceUpColors.surfaceMuted,
        thumbColor: Colors.white,
        overlayColor: Color(0x1F0E7C7B),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return DiceUpColors.disabledForeground;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return DiceUpColors.disabledBackground;
          }
          if (states.contains(WidgetState.selected)) {
            return DiceUpColors.teal;
          }
          return DiceUpColors.surfaceMuted;
        }),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(
          DiceUpColors.border,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: DiceUpColors.teal,
        linearTrackColor: DiceUpColors.surfaceMuted,
      ),
      dividerTheme: const DividerThemeData(
        color: DiceUpColors.border,
        thickness: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: DiceUpColors.navy,
          borderRadius: DiceUpSpacing.radiusSmBorder,
        ),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      // v2 navigation motion: every named route enters with one
      // finite fade-and-rise (see [_FadeThroughTransitionsBuilder]),
      // replacing the platform's horizontal slide with the same
      // language the results route already uses. Finite by design —
      // the harness's `pumpAndSettle` keeps terminating — and it
      // collapses to an instant handover under reduced motion.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeThroughTransitionsBuilder(),
          TargetPlatform.iOS: _FadeThroughTransitionsBuilder(),
          TargetPlatform.macOS: _FadeThroughTransitionsBuilder(),
          TargetPlatform.windows: _FadeThroughTransitionsBuilder(),
          TargetPlatform.linux: _FadeThroughTransitionsBuilder(),
        },
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

/// The v2 page transition: the incoming route fades in over ~a
/// platform-standard duration while rising 3% of its height, the
/// same language the results route's custom transition established
/// (M3 premium §2.7.2), applied to every named route.
///
/// Finite: the transition runs exactly as long as the route
/// animation, so `pumpAndSettle` terminates. Reduced motion: the
/// builder checks [MediaQuery.disableAnimationsOf] (plus the iOS
/// Reduce Motion feature, same as everywhere else in the app) and
/// hands back the child with no transition at all.
class _FadeThroughTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeThroughTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final disabled =
        MediaQuery.disableAnimationsOf(context) ||
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .reduceMotion;
    if (disabled) return child;
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    );
  }
}
