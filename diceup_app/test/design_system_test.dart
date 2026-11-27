import 'package:diceup/core/design_system/diceup_colors.dart';
import 'package:diceup/core/design_system/diceup_components.dart';
import 'package:diceup/core/design_system/diceup_shadows.dart';
import 'package:diceup/core/design_system/diceup_spacing.dart';
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

  group('Stage 2 contrast pins (REDESIGN-PLAN.md §4/§5, F9)', () {
    test('textSecondary passes AA 4.5:1 on every light surface', () {
      expect(
        DiceUpColors.contrastRatio(
          DiceUpColors.textSecondary,
          DiceUpColors.background,
        ),
        closeTo(6.79, 0.05),
      );
      expect(
        DiceUpColors.contrastRatio(
          DiceUpColors.textSecondary,
          DiceUpColors.surfaceMuted,
        ),
        closeTo(6.15, 0.05),
      );
      expect(
        DiceUpColors.contrastRatio(
          DiceUpColors.textSecondary,
          DiceUpColors.surface,
        ),
        closeTo(7.45, 0.05),
      );
      expect(
        DiceUpColors.contrastRatio(DiceUpColors.textSecondary, Colors.white),
        closeTo(7.58, 0.05),
      );
      // The old #64748B failed on the old surfaces (4.44:1 /
      // 4.34:1) and would be worse on ivory (4.26:1 / 3.86:1) —
      // the darkened value is the fix, pinned above.
    });

    test('textPrimary passes AA on the ivory surfaces', () {
      expect(
        DiceUpColors.contrastRatio(
          DiceUpColors.textPrimary,
          DiceUpColors.background,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        DiceUpColors.contrastRatio(
          DiceUpColors.textPrimary,
          DiceUpColors.surfaceMuted,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('white text passes AA on the navy table field and AppBar', () {
      expect(
        DiceUpColors.contrastRatio(Colors.white, DiceUpColors.table),
        closeTo(16.91, 0.05),
      );
      expect(
        DiceUpColors.contrastRatio(Colors.white, DiceUpColors.navy),
        closeTo(14.11, 0.05),
      );
    });

    test('gold is distinct from amber and safe as an accent', () {
      expect(DiceUpColors.gold, isNot(DiceUpColors.amber));
      // Gold passes 3:1 on light surfaces (non-text marker) and
      // 4.5:1 on the navy field.
      expect(
        DiceUpColors.contrastRatio(DiceUpColors.gold, Colors.white),
        closeTo(3.14, 0.05),
      );
      expect(
        DiceUpColors.contrastRatio(DiceUpColors.gold, DiceUpColors.table),
        closeTo(5.39, 0.05),
      );
      // Amber fails AA as text (3.19:1 on white) — the reason it
      // is never a text colour, only stars / the spinner.
      expect(
        DiceUpColors.contrastRatio(DiceUpColors.amber, Colors.white),
        closeTo(3.19, 0.05),
      );
    });

    test('player colours on ivory: red/green/blue pass 3:1 as rings; '
        'yellow is the documented exception', () {
      // Yellow on ivory is 2.34:1 — below the 3:1 non-text bar —
      // so yellow is never a lone cue on a light surface: it is
      // always paired with a shape + name (D-27, NFR-08). Pin the
      // measured value so a future deepening is visible, not silent.
      expect(
        DiceUpColors.contrastRatio(
          DiceUpColors.playerColor(2),
          DiceUpColors.surface,
        ),
        closeTo(2.34, 0.05),
      );
      for (final seat in [0, 1, 3]) {
        expect(
          DiceUpColors.contrastRatio(
            DiceUpColors.playerColor(seat),
            DiceUpColors.surface,
          ),
          greaterThanOrEqualTo(3.0),
          reason: 'seat $seat ring must pass 3:1 on ivory',
        );
      }
    });

    test('player colours on dark pass 4.5:1 on the table field', () {
      for (var seat = 0; seat < 4; seat++) {
        expect(
          DiceUpColors.contrastRatio(
            DiceUpColors.playerColorOnDark(seat),
            DiceUpColors.table,
          ),
          greaterThanOrEqualTo(4.5),
          reason: 'seat $seat on-dark colour must pass 4.5:1 on table',
        );
      }
      // The deepened blue is the reason the mapping exists: it
      // fails 3:1 on the table (2.72:1) while its on-dark variant
      // passes (6.25:1).
      expect(
        DiceUpColors.contrastRatio(
          DiceUpColors.playerColor(3),
          DiceUpColors.table,
        ),
        closeTo(2.72, 0.05),
      );
      expect(
        DiceUpColors.contrastRatio(
          DiceUpColors.playerColorOnDark(3),
          DiceUpColors.table,
        ),
        closeTo(6.25, 0.05),
      );
    });
  });

  group('Stage 2 typography tiers (REDESIGN-PLAN.md §4, F6)', () {
    test('bodyMedium and bodySmall are no longer identical', () {
      final theme = DiceUpTypography.textTheme(DiceUpTheme.light().colorScheme);
      expect(theme.bodyMedium!.fontSize, 14);
      expect(theme.bodySmall!.fontSize, 14);
      expect(theme.bodyMedium!.fontWeight, FontWeight.w500);
      expect(theme.bodySmall!.fontWeight, FontWeight.w400);
      expect(theme.bodyMedium!.color, DiceUpColors.textPrimary);
      expect(theme.bodySmall!.color, DiceUpColors.textSecondary);
    });

    test('caption, displayNumeral and sectionHeading are defined, '
        '>= 14 sp, and name no font family', () {
      final styles = <String, TextStyle>{
        'caption': DiceUpTypography.caption,
        'displayNumeral': DiceUpTypography.displayNumeral,
        'sectionHeading': DiceUpTypography.sectionHeading,
      };
      for (final entry in styles.entries) {
        expect(
          entry.value.fontSize,
          greaterThanOrEqualTo(14),
          reason: '${entry.key} is below the 14 sp floor',
        );
        expect(
          entry.value.fontFamily,
          isNull,
          reason: '${entry.key} must not name a font family (M2.14)',
        );
      }
      expect(DiceUpTypography.caption.fontSize, 14);
      expect(DiceUpTypography.displayNumeral.fontSize, 28);
      expect(DiceUpTypography.displayNumeral.fontWeight, FontWeight.w800);
      expect(DiceUpTypography.sectionHeading.fontSize, 16);
      expect(DiceUpTypography.sectionHeading.fontWeight, FontWeight.w700);
    });
  });

  group('Stage 2 spacing / radius / shadow tokens', () {
    test('radius steps are 8/12/16 with dialog 16 and board 20', () {
      expect(DiceUpSpacing.radiusSm, 8);
      expect(DiceUpSpacing.radiusMd, 12);
      expect(DiceUpSpacing.radiusLg, 16);
      expect(DiceUpSpacing.radiusDialog, 16);
      expect(DiceUpSpacing.radiusBoard, 20);
      expect(DiceUpSpacing.radiusDialogBorder, BorderRadius.circular(16));
      expect(DiceUpSpacing.radiusBoardBorder, BorderRadius.circular(20));
    });

    test('maxContentWidth is 560 dp for tablet layouts', () {
      expect(DiceUpSpacing.maxContentWidth, 560);
    });

    test('table shadow is one soft black shadow, no glow', () {
      expect(DiceUpShadows.table, hasLength(1));
      final shadow = DiceUpShadows.table.single;
      expect(shadow.color, const Color(0x40000000));
      expect(shadow.blurRadius, 16);
      expect(shadow.offset, const Offset(0, 8));
      expect(DiceUpShadows.raised, hasLength(1));
      expect(DiceUpShadows.lifted, hasLength(1));
    });
  });

  group('Stage 2 theme rebuild (REDESIGN-PLAN.md §4, F7/F8)', () {
    test('Card uses the ivory surface and 16 dp radius', () {
      final theme = DiceUpTheme.light();
      expect(theme.cardTheme.color, DiceUpColors.surface);
      final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16));
    });

    test('dialog uses the ivory surface, 16 dp radius, navy title', () {
      final theme = DiceUpTheme.light();
      expect(theme.dialogTheme.backgroundColor, DiceUpColors.surface);
      final shape = theme.dialogTheme.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16));
      expect(theme.dialogTheme.titleTextStyle?.color, DiceUpColors.navy);
    });

    test('SnackBar uses the navy surface, floating, white text', () {
      final theme = DiceUpTheme.light();
      expect(theme.snackBarTheme.backgroundColor, DiceUpColors.navy);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.snackBarTheme.contentTextStyle?.color, Colors.white);
    });

    test('disabled primary button is unmistakably not teal', () {
      final theme = DiceUpTheme.light();
      final style = theme.elevatedButtonTheme.style!;
      // styleFrom's disabled* params fold into the state-resolved
      // foreground/background colors — read them back that way.
      expect(
        style.backgroundColor?.resolve({WidgetState.disabled}),
        DiceUpColors.disabledBackground,
      );
      expect(
        style.foregroundColor?.resolve({WidgetState.disabled}),
        DiceUpColors.disabledForeground,
      );
      expect(style.backgroundColor?.resolve({}), DiceUpColors.teal);
    });

    test('scaffold background is warm ivory', () {
      expect(
        DiceUpTheme.light().scaffoldBackgroundColor,
        DiceUpColors.background,
      );
    });
  });

  group('Stage 2 components (REDESIGN-PLAN.md §4)', () {
    testWidgets('SectionHeading renders title and subtitle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: DiceUpTheme.light(),
          home: const Scaffold(
            body: SectionHeading(
              title: 'Players',
              subtitle: 'Who is at the table',
            ),
          ),
        ),
      );
      expect(find.text('Players'), findsOneWidget);
      expect(find.text('Who is at the table'), findsOneWidget);
    });

    testWidgets('StatTile renders the numeral and label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: DiceUpTheme.light(),
          home: const Scaffold(
            body: StatTile(label: 'Wins', value: '12'),
          ),
        ),
      );
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Wins'), findsOneWidget);
      final numeral = tester.widget<Text>(find.text('12'));
      expect(numeral.style?.fontSize, 28);
    });

    testWidgets('DiceUpDialog.show renders title/content and pops a '
        'value', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: DiceUpTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await DiceUpDialog.show<String>(
                    context,
                    title: 'Pause',
                    content: const Text('Take a break.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop('resume'),
                        child: const Text('Resume'),
                      ),
                    ],
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Take a break.'), findsOneWidget);
      // The shared dialog shell carries the ivory surface + 16 dp
      // radius from the theme, not the stock Material look.
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.backgroundColor, isNull);
      final theme = DiceUpTheme.light();
      expect(theme.dialogTheme.backgroundColor, DiceUpColors.surface);
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      expect(result, 'resume');
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
