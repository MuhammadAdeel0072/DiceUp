import 'package:diceup/core/design_system/diceup_theme.dart';
import 'package:diceup/core/design_system/diceup_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Design-system font contract (M2.14, L-04).
///
/// No font family is named anywhere in the theme: every style in
/// [DiceUpTypography.textTheme] leaves `fontFamily` null, so text
/// renders in Flutter's platform default (Roboto on Android, the
/// system fallback font on iOS) instead of naming a Roboto that was
/// never bundled. (Note: `ThemeData` itself fills an unspecified
/// family from Flutter's own Material defaults — `'Roboto'` — so
/// the *applied* theme reports that family; that is the
/// framework's default, identical to a stock Material app, not a
/// choice made by this file.) This test pins that decision —
/// re-introducing a `fontFamily` in `DiceUpTypography` fails the
/// first test, and a font choice in the applied theme fails the
/// second; either change must then be justified against the M2.14
/// record in `docs/IMPLEMENTATION-PLAN.md` (bundling needs
/// binary font files; the `google_fonts` package needs runtime
/// network, which conflicts with the offline-by-construction
/// property, NFR-23).
void main() {
  group('M2.14 font family — platform default, no named font', () {
    test('typography textTheme names no font family', () {
      final theme = DiceUpTypography.textTheme(DiceUpTheme.light().colorScheme);
      final styles = <String, TextStyle?>{
        'displayLarge': theme.displayLarge,
        'headlineMedium': theme.headlineMedium,
        'titleLarge': theme.titleLarge,
        'titleMedium': theme.titleMedium,
        'bodyLarge': theme.bodyLarge,
        'bodyMedium': theme.bodyMedium,
        'labelLarge': theme.labelLarge,
        'bodySmall': theme.bodySmall,
      };
      for (final entry in styles.entries) {
        expect(
          entry.value,
          isNotNull,
          reason: '${entry.key} must be defined by the theme',
        );
        expect(
          entry.value!.fontFamily,
          isNull,
          reason:
              '${entry.key} must not name a font family — '
              'the platform default applies (M2.14, L-04)',
        );
      }
    });

    test('applied light theme adds no font choice of its own — '
        'its family is the framework default, as in a stock '
        'Material app', () {
      final applied = DiceUpTheme.light().textTheme;
      final stock = ThemeData.light().textTheme;
      // ThemeData fills an unspecified family from Flutter's own
      // Material defaults ('Roboto'); the app itself names none,
      // so the applied family must equal the stock default's.
      expect(applied.bodyLarge?.fontFamily, stock.bodyLarge?.fontFamily);
      expect(applied.bodyMedium?.fontFamily, stock.bodyMedium?.fontFamily);
      expect(applied.bodySmall?.fontFamily, stock.bodySmall?.fontFamily);
      // The app's own contribution is the sizes, not the family.
      expect(applied.bodySmall?.fontSize, 14);
    });
  });
}
