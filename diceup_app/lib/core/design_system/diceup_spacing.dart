import 'package:flutter/material.dart';

/// DiceUp spacing + radius system (SDD §11.1).
///
/// Spacing is always a multiple of 4. Nothing uses an ad-hoc padding value.
/// Touch targets are at least 48x48 dp (SRS NFR-08).
abstract final class DiceUpSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Minimum touch-target size (SRS NFR-08).
  static const double minTouchTarget = 48;

  // Border radii.
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;

  static const BorderRadius radiusSmBorder = BorderRadius.all(Radius.circular(radiusSm));
  static const BorderRadius radiusMdBorder = BorderRadius.all(Radius.circular(radiusMd));
  static const BorderRadius radiusLgBorder = BorderRadius.all(Radius.circular(radiusLg));

  // Common paddings.
  static const EdgeInsets screenPadding = EdgeInsets.all(md);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets buttonPadding =
      EdgeInsets.symmetric(horizontal: lg, vertical: sm);
}
