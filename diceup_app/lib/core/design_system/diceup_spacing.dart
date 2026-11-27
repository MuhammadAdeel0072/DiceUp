import 'package:flutter/material.dart';

/// DiceUp spacing + radius system (SDD §11.1).
///
/// Spacing is always a multiple of 4. Nothing uses an ad-hoc padding value.
///
/// [minTouchTarget] is the NFR-08 minimum touch-target size (48x48 dp,
/// confirmed binding by D-21). [DiceUpTheme] enforces it for buttons
/// through the button themes, and interactive components are built to
/// it — but it is a token for *controls*, not a blanket guarantee about
/// every tappable thing: board tokens are game pieces, exempt from the
/// 48 dp rule by D-09 (they are ~22 dp on the minimum 280 dp board;
/// their mitigation is the full-cell hit area in `game_screen.dart`).
abstract final class DiceUpSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Minimum touch-target size (SRS NFR-08).
  static const double minTouchTarget = 48;

  /// Maximum content width for centred-column layouts at >= 600 dp
  /// widths (tablets portrait, REDESIGN-PLAN.md §4/§5): cards and
  /// the board column centre inside this width instead of stretching
  /// full-width. The board itself still caps at 480 dp.
  static const double maxContentWidth = 560;

  // Border radii (redesign Stage 2: the full 8/12/16 steps, so
  // dialogs, chips and the board frame stop improvising).
  /// Small radius: chips, small controls.
  static const double radiusSm = 8;

  static const double radiusMd = 12;
  static const double radiusLg = 16;

  /// Dialog radius: matches the card system (16 dp), so dialogs stop
  /// looking stock next to 16 dp cards (F7).
  static const double radiusDialog = 16;

  /// Board-frame radius: the rounded outer edge of the board as an
  /// object on the table field.
  static const double radiusBoard = 20;

  static const BorderRadius radiusSmBorder = BorderRadius.all(
    Radius.circular(radiusSm),
  );
  static const BorderRadius radiusMdBorder = BorderRadius.all(
    Radius.circular(radiusMd),
  );
  static const BorderRadius radiusLgBorder = BorderRadius.all(
    Radius.circular(radiusLg),
  );
  static const BorderRadius radiusDialogBorder = BorderRadius.all(
    Radius.circular(radiusDialog),
  );
  static const BorderRadius radiusBoardBorder = BorderRadius.all(
    Radius.circular(radiusBoard),
  );

  // Common paddings.
  static const EdgeInsets screenPadding = EdgeInsets.all(md);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: lg,
    vertical: sm,
  );
}
