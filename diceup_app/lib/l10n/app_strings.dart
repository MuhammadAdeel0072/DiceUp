import 'package:diceup/l10n/app_localizations.dart';
import 'package:diceup/l10n/app_localizations_en.dart';
import 'package:flutter/widgets.dart';

import '../core/design_system/diceup_components.dart';
import '../domain/ai/ai_player.dart';
import '../domain/engine/player_colour.dart';

/// Localised strings for the build context's locale (M3.10, NFR-38).
///
/// Falls back to the English localisations when no delegates are
/// registered above [context]: bare-`MaterialApp` widget tests pump
/// screens without `localizationsDelegates`, while production always
/// has them via [DiceUpApp]. English is the initial language, so the
/// fallback renders exactly the strings the existing tests assert —
/// no test needs a delegate setup to keep passing.
AppLocalizations stringsOf(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Localised lower-case display name of a player colour, for use
/// inside sentences and semantics labels (avatar, colour swatches).
String colourName(PlayerColour colour, AppLocalizations l10n) =>
    switch (colour) {
      PlayerColour.red => l10n.colourRed,
      PlayerColour.green => l10n.colourGreen,
      PlayerColour.yellow => l10n.colourYellow,
      PlayerColour.blue => l10n.colourBlue,
    };

/// Localised display name of a token shape, for the avatar semantics
/// label (M2.9: the shape is named, never colour alone).
String shapeName(PlayerShape shape, AppLocalizations l10n) => switch (shape) {
  PlayerShape.circle => l10n.shapeCircle,
  PlayerShape.square => l10n.shapeSquare,
  PlayerShape.diamond => l10n.shapeDiamond,
  PlayerShape.triangle => l10n.shapeTriangle,
};

/// Localised display name of an AI difficulty, for the setup screen's
/// difficulty dropdown.
String difficultyName(AiDifficulty difficulty, AppLocalizations l10n) =>
    switch (difficulty) {
      AiDifficulty.easy => l10n.difficultyEasy,
      AiDifficulty.medium => l10n.difficultyMedium,
      AiDifficulty.hard => l10n.difficultyHard,
    };

/// Localised short month names in calendar order, for the history and
/// results date formats (which avoid the intl package).
List<String> monthNames(AppLocalizations l10n) => [
  l10n.monthJan,
  l10n.monthFeb,
  l10n.monthMar,
  l10n.monthApr,
  l10n.monthMay,
  l10n.monthJun,
  l10n.monthJul,
  l10n.monthAug,
  l10n.monthSep,
  l10n.monthOct,
  l10n.monthNov,
  l10n.monthDec,
];
