import 'package:flutter/material.dart';

import 'diceup_colors.dart';

/// DiceUp typography hierarchy (SDD §11.1).
///
/// Body text is never below 14sp (SRS NFR-08, confirmed binding by
/// D-21): 14sp is the floor — [TextTheme.bodySmall] is 14sp, and no
/// style in this theme is smaller.
///
/// Font family (M2.14, L-04): no font family is named anywhere in
/// the theme. Text therefore renders in Flutter's platform default —
/// Roboto on Android (the system font there) and the system fallback
/// font on iOS. An earlier version of this file named `'Roboto'`
/// explicitly, but no Roboto file was ever bundled (`pubspec.yaml`
/// has no `fonts:` section), so on iOS the name resolved to the
/// fallback anyway and the name promised more than the app shipped.
/// Bundling Roboto was not done instead: it would need binary
/// `.ttf` files in the repo, which the snapshot-push route cannot
/// carry (UTF-8 text only), and the `google_fonts` package was
/// rejected because it downloads fonts at runtime — a network
/// dependency at first run, which conflicts with the offline-by-
/// construction property (NFR-23). If a bundled display font is
/// ever wanted, it is introduced through this file alone, with the
/// font files declared in `pubspec.yaml`. (Note: `ThemeData` fills
/// an unspecified family from Flutter's own Material defaults
/// (`'Roboto'`), so the *applied* theme reports that family — the
/// framework's default, identical to a stock Material app, not a
/// choice made here; see `test/design_system_test.dart`.)
abstract final class DiceUpTypography {
  static TextTheme textTheme(ColorScheme scheme) {
    return TextTheme(
      displayLarge: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: DiceUpColors.textPrimary,
        height: 1.2,
      ),
      headlineMedium: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: DiceUpColors.textPrimary,
        height: 1.25,
      ),
      titleLarge: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: DiceUpColors.textPrimary,
      ),
      titleMedium: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: DiceUpColors.textPrimary,
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: DiceUpColors.textPrimary,
        height: 1.5,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: DiceUpColors.textPrimary,
        height: 1.5,
      ),
      labelLarge: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: DiceUpColors.textPrimary,
      ),
      bodySmall: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: DiceUpColors.textSecondary,
      ),
    );
  }
}
