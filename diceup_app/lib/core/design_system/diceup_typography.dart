import 'package:flutter/material.dart';

import 'diceup_colors.dart';

/// DiceUp typography hierarchy (SDD §11.1).
///
/// Body text is never below 14sp (SRS NFR-08, confirmed binding by
/// D-21): 14sp is the floor — [TextTheme.bodySmall] is 14sp, and no
/// style in this theme is smaller.
///
/// Hierarchy (redesign Stage 2, REDESIGN-PLAN.md §4) comes from
/// scale, weight, tracking and colour — not from a font. [bodyMedium]
/// and [TextTheme.bodySmall] are no longer identical: bodyMedium is
/// 14sp w500 in the primary colour, bodySmall is 14sp w400 in the
/// secondary colour with tighter leading, so the two tiers read
/// differently at the same size. [caption] is the small-text tier —
/// "caption" means secondary colour + medium weight + tracking, not
/// a smaller size, because nothing goes below 14sp. [displayNumeral]
/// (28sp w800) is the large-numeral style for statistics and results
/// totals; [sectionHeading] is the section-label style used by
/// [SectionHeading] (see `diceup_components.dart`).
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
  /// Small-text tier: footnotes, hints, stat labels. 14sp — the
  /// floor, not smaller — distinguished from body text by the
  /// secondary colour, medium weight and slight tracking.
  static const TextStyle caption = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: DiceUpColors.textSecondary,
    letterSpacing: 0.2,
    height: 1.4,
  );

  /// Large numerals for statistics totals and results figures
  /// (e.g. "12" wins, "04:32" duration). 28sp w800 — the one
  /// addition to the 32/24/20/16/14 scale, added because the
  /// statistics/results screens need it (REDESIGN-PLAN.md §4).
  static const TextStyle displayNumeral = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: DiceUpColors.textPrimary,
    height: 1.2,
  );

  /// Section labels ("Players", "Seats", "House rules"): 16sp w700
  /// with slight tracking, so a section heading reads above a card
  /// title (titleMedium, 16sp w600, no tracking) at the same size.
  static const TextStyle sectionHeading = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: DiceUpColors.textPrimary,
    letterSpacing: 0.2,
    height: 1.3,
  );

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
        fontWeight: FontWeight.w500,
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
        height: 1.4,
      ),
    );
  }
}
