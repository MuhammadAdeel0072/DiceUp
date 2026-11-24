import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/engine/player_colour.dart';

/// DiceUp brand colours (SDD §11.1 — visual identity).
///
/// One palette for the whole app. No screen invents its own colours.
/// Player colours are the four Ludo colours; each player is also given a
/// distinct token *shape* (see [PlayerShape] in the board widgets) so game
/// information is never carried by colour alone (SRS NFR-08).
///
/// Environment (redesign Stage 2, REDESIGN-PLAN.md §2/§4): the app is
/// one calm room, not two themes. The game screen sits on the deep
/// navy/indigo [table] field so the ivory board and the four player
/// colours read as objects on a table; out-of-game screens use warm
/// ivory surfaces ([background], [surface]/[ivory], [surfaceMuted])
/// with navy text and a restrained [gold] accent. Teal stays the
/// action colour. There is no dark theme (M2.14): the navy game
/// field is an *environment*, not a dark theme — text on it must
/// still pass AA, verified per surface (see the contrast notes below
/// and `test/design_system_test.dart`).
///
/// Text-colour rules (F9 — measured with [contrastRatio], WCAG AA
/// 4.5:1 for normal text, 3:1 for large text and non-text markers):
/// * [textSecondary] passes 4.5:1 on [background], [surfaceMuted],
///   [surface] and white — it is the only secondary text colour.
/// * [amber] and player yellow are **never text colours**: amber on
///   white is 3.19:1, yellow on white is 2.38:1. Amber stays for
///   stars / the spinner only; yellow is a fill/ring only, always
///   paired with a shape + name (never colour alone).
/// * [gold] is the sparing accent (winner's mark, one highlight per
///   screen at most). It is distinct from amber — amber is orange
///   (#D97706), gold is yellow-gold (#B08D2E) — and, unlike amber,
///   it passes 3:1 on light surfaces (3.14:1 on white) and 4.5:1
///   on the navy field (5.39:1 on [table], 4.50:1 on [navy]).
/// * Player colours are fills/rings/borders, never text. Red, green
///   and blue pass 3:1 on ivory as rings; yellow does not (2.38:1
///   on white) and is therefore never a lone cue on a light surface.
///   On the navy field use [playerColorsOnDark] — the deepened
///   blue fails 3:1 on [table] (2.72:1) while its on-dark variant
///   passes comfortably (6.25:1).
abstract final class DiceUpColors {
  // Brand — taken from the SDD document palette.
  static const Color navy = Color(0xFF1B2A4E);
  static const Color teal = Color(0xFF0E7C7B);
  static const Color amber = Color(0xFFD97706);
  static const Color amberLight = Color(0xFFFEF3C7);

  /// Restrained gold accent (redesign Stage 2). Distinct from [amber]:
  /// amber is the orange of stars only; gold is the yellow-gold of the
  /// winner's mark and a single highlight per screen. Never a second
  /// primary, never body text (3.14:1 on white is below 4.5:1).
  /// On dark surfaces it is strong — 5.39:1 on [table], 4.50:1 on
  /// [navy] — so gold accents on the navy field are safe as large
  /// text / non-text markers, not as body text.
  static const Color gold = Color(0xFFB08D2E);

  // Game-table environment (redesign Stage 2).
  /// Deep navy/indigo field behind the board. White text on it is
  /// 16.91:1; [gold] on it is 5.39:1.
  static const Color table = Color(0xFF131C33);

  /// Warm ivory card surface (also [surface]).
  static const Color ivory = Color(0xFFFFFDF7);

  /// Warm ivory muted surface (also [surfaceMuted]): chips,
  /// inactive fills, muted panels.
  static const Color ivoryMuted = Color(0xFFEFE7D3);

  // Surfaces (light theme).
  /// Warm ivory page background. [textSecondary] on it is 6.79:1.
  static const Color background = Color(0xFFF7F2E7);

  /// Warm ivory card surface.
  static const Color surface = Color(0xFFFFFDF7);

  /// Warm ivory muted surface.
  static const Color surfaceMuted = Color(0xFFEFE7D3);

  /// The alternate ivory (premium v2): one step deeper than
  /// [surface], one step lighter than [surfaceMuted]. The board
  /// painter alternates regular track cells between [surface] and
  /// this for a quiet checker rhythm; the yard inner panels and
  /// pedestal sockets use it too. Never a text surface — it exists
  /// so cells and sockets read as inlays without inventing a colour
  /// per widget.
  static const Color ivoryAlt = Color(0xFFFAF5E9);

  /// Warm neutral border, harmonised with the ivory surfaces.
  static const Color border = Color(0xFFE5DFCC);

  // Text.
  static const Color textPrimary = Color(0xFF1E293B);

  /// Secondary text (subtitles, hints, captions). Darkened from
  /// #64748B in Stage 2: the old value measured 4.44:1 on the old
  /// background and 4.34:1 on the old muted surface (both below AA
  /// 4.5:1), and would have been worse on ivory (4.26:1 /
  /// 3.86:1). The new value measures 6.79:1 on [background],
  /// 6.15:1 on [surfaceMuted], 7.45:1 on [surface] and 7.58:1 on
  /// white — AA on every surface in the app.
  static const Color textSecondary = Color(0xFF475569);

  static const Color textOnDark = Colors.white;

  // Feedback.
  static const Color error = Color(0xFFB91C1C);

  /// Disabled-control greys. The old #64748B survives only here:
  /// a disabled control is exempt from the text-contrast rule, and
  /// keeping the old secondary grey for the disabled state makes a
  /// disabled button unmistakable against the teal enabled state
  /// (F8). Never use these for body text.
  static const Color disabledForeground = Color(0xFF64748B);
  static const Color disabledBackground = Color(0xFFE2E8F0);

  // Ludo player colours (order: Red, Green, Yellow, Blue).
  //
  // Deepened and harmonised in Stage 2 so they read on ivory *and*
  // on navy: red #E5484D -> #C92A2E (5.45:1 on white, 3.10:1 on
  // [table]), green #2FA866 -> #1F7A4A (5.33:1 on white, 3.17:1 on
  // [table]), yellow #F5B301 -> #D99E00 (2.38:1 on white — fill/ring
  // only, never text, never a lone cue on a light surface; 7.12:1
  // on [table]), blue #2F6FED -> #2456D6 (6.22:1 on white, 2.72:1
  // on [table] — use [playerColorsOnDark] on the navy field).
  static const List<Color> playerColors = [
    Color(0xFFC92A2E), // red
    Color(0xFF1F7A4A), // green
    Color(0xFFD99E00), // yellow
    Color(0xFF2456D6), // blue
  ];

  /// Player colours for use on the navy [table] field, in the same
  /// seat order. Every entry passes 4.5:1 on [table] (red 6.09:1,
  /// green 7.64:1, yellow 10.46:1, blue 6.25:1). Use these — never
  /// [playerColors] — for rings, markers or text-adjacent accents
  /// drawn on navy.
  static const List<Color> playerColorsOnDark = [
    Color(0xFFFF6B6B), // red
    Color(0xFF4CC38A), // green
    Color(0xFFFFC21A), // yellow
    Color(0xFF6B9BFF), // blue
  ];

  static Color playerColor(int seatIndex) =>
      playerColors[seatIndex % playerColors.length];

  /// The on-dark variant of [playerColor] for the seat, for use on
  /// the navy [table] field (see [playerColorsOnDark]).
  static Color playerColorOnDark(int seatIndex) =>
      playerColorsOnDark[seatIndex % playerColorsOnDark.length];

  /// WCAG 2.x contrast ratio between two opaque colours (1.0–21.0).
  ///
  /// Used by the D-27 avatar tests (M2.4): the avatar initial is navy
  /// on white for every seat, so the ratio is the same whatever the
  /// player's ring colour is — navy on white is 14.11:1, comfortably
  /// above the AA 4.5:1 floor. Alpha is ignored: callers pass opaque
  /// colours (the avatar disc is opaque white, the initial opaque navy).
  static double contrastRatio(Color a, Color b) {
    final l1 = _relativeLuminance(a);
    final l2 = _relativeLuminance(b);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _relativeLuminance(Color color) {
    double channel(double c) => c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  /// The display colour for a chosen [PlayerColour] (M2.2).
  ///
  /// [playerColors] is ordered to match [PlayerColour.values] (red,
  /// green, yellow, blue), so the mapping is by index. Use this —
  /// never [playerColor] — when the colour comes from a player's
  /// chosen colour rather than their seat: after a colour swap the
  /// seat and the colour no longer agree.
  static Color forColour(PlayerColour colour) =>
      playerColors[colour.index % playerColors.length];

  /// The on-dark variant of [forColour] for the navy [table] field
  /// (see [playerColorsOnDark]).
  static Color forColourOnDark(PlayerColour colour) =>
      playerColorsOnDark[colour.index % playerColorsOnDark.length];
}
