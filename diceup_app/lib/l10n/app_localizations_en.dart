// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get modeVsAiSemantics =>
      'Play vs AI. You against computer opponents (Easy, Medium, Hard).';

  @override
  String get modeLocalSemantics =>
      'Local multiplayer. 2–4 players sharing this device.';

  @override
  String get appName => 'DiceUp';

  @override
  String avatarLabel(String colour, String name, String shape) {
    return '$name, $shape token, $colour';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get colourBlue => 'blue';

  @override
  String get colourGreen => 'green';

  @override
  String get colourRed => 'red';

  @override
  String get colourYellow => 'yellow';

  @override
  String get diceNoRollYet => 'Dice, no roll yet';

  @override
  String get diceRolling => 'Dice, rolling';

  @override
  String diceShowing(int value) {
    return 'Dice, showing $value';
  }

  @override
  String diceShowingTap(int value) {
    return 'Dice, showing $value. Tap to roll';
  }

  @override
  String get diceTapToRoll => 'Tap to roll';

  @override
  String get diceTapToRollLabel => 'Dice, tap to roll';

  @override
  String get difficultyEasy => 'Easy';

  @override
  String get difficultyHard => 'Hard';

  @override
  String get difficultyMedium => 'Medium';

  @override
  String get gameBoardFinished => 'Ludo board. Match finished';

  @override
  String gameBoardTurnOne(String name) {
    return 'Ludo board. $name\'s turn, 1 legal move';
  }

  @override
  String gameBoardTurnOther(int count, String name) {
    return 'Ludo board. $name\'s turn, $count legal moves';
  }

  @override
  String gameBoardWinner(String name) {
    return 'Ludo board. $name won the match';
  }

  @override
  String get gameDiceChooseToken => 'Choose a token to move.';

  @override
  String get gameDiceNotYourTurn => 'It\'s not your turn yet.';

  @override
  String get gameDiceWaitMove => 'Wait for the move to finish.';

  @override
  String get gameDiceWaitSettle => 'Wait for the dice to settle.';

  @override
  String get gameIllegalTokenMove => 'That token can\'t move now';

  @override
  String get gameLeaveConfirm => 'Leave';

  @override
  String get gameLeaveFinishedMessage => 'This match is over.';

  @override
  String get gameLeaveTitle => 'Leave the match?';

  @override
  String get gameLeaveUnfinishedMessage =>
      'Your progress in this match will be lost.';

  @override
  String get gamePauseRestart => 'Restart';

  @override
  String get gamePauseResume => 'Resume';

  @override
  String get gamePauseTooltip => 'Pause';

  @override
  String get gamePausedMessage => 'Take a break — the match is frozen.';

  @override
  String get gamePausedTitle => 'Paused';

  @override
  String gamePlayerHome(int home, String name) {
    return '$name · Home $home/4';
  }

  @override
  String get gameRestartConfirm => 'Restart';

  @override
  String get gameRestartMessage => 'The current match will be discarded.';

  @override
  String get gameRestartTitle => 'Restart match?';

  @override
  String get gameRollDice => 'Roll dice';

  @override
  String get gameRolling => 'Rolling…';

  @override
  String get gameSafeCellsHint =>
      'Safe cells are marked with a star. Tokens on safe cells cannot be captured.';

  @override
  String gameTurnBanner(String name) {
    return '$name\'s turn';
  }

  @override
  String historyDurationMinutesSeconds(int minutes, int seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String historyDurationSeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get historyEmptyHint =>
      'Finished offline matches will appear here, newest first.';

  @override
  String get historyEmptyTitle => 'No matches yet';

  @override
  String get historyLoadFailedHint => 'Try again later.';

  @override
  String get historyLoadFailedTitle => 'Couldn\'t load match history';

  @override
  String get historyLocalBadge => 'Local';

  @override
  String get historyLocalNote =>
      'Local match — offline results never affect rankings.';

  @override
  String historyMatchFinished(String mode) {
    return '$mode · Finished';
  }

  @override
  String historyMatchLine(String date, String duration, String players) {
    return '$date · $duration · $players';
  }

  @override
  String historyMatchWon(String mode, String winner) {
    return '$mode · $winner won';
  }

  @override
  String get historyNoWinner => 'No winner recorded';

  @override
  String get historyUnavailableHint =>
      'Your saved data couldn\'t be loaded, so past matches cannot be shown right now.';

  @override
  String get historyUnavailableTitle => 'History unavailable';

  @override
  String get historyUnknownLength => 'Unknown length';

  @override
  String get homeDatabaseError =>
      'Your saved data couldn\'t be loaded. You can still play, but matches and settings will not be saved this time.';

  @override
  String get homeDatabaseRecovered =>
      'Your local history couldn\'t be read, so it was reset. You can keep playing.';

  @override
  String get homeMatchHistory => 'Match History';

  @override
  String get homeOfflineNote =>
      'Offline play works without an account or internet.';

  @override
  String get homeOnlineMessage =>
      'Log in to play online — online play arrives in Phase 5.';

  @override
  String get homePlayOffline => 'Play Offline';

  @override
  String get homePlayOnline => 'Play Online';

  @override
  String get homeReadySubtitle => 'Classic Ludo — offline, with friends.';

  @override
  String get homeReadyTitle => 'Ready to play?';

  @override
  String get homeResumeDiscard => 'Discard';

  @override
  String get homeResumeMessage =>
      'You have a match in progress. Resume where you left off, or discard it and start fresh.';

  @override
  String get homeResumeResume => 'Resume';

  @override
  String get homeResumeTitle => 'Resume your match?';

  @override
  String get homeSettingsTooltip => 'Settings';

  @override
  String get homeSnapshotCorrupt =>
      'Your saved match couldn\'t be read, so it was discarded. You can start a new match.';

  @override
  String get homeStatistics => 'Statistics';

  @override
  String get labelDuration => 'Duration';

  @override
  String get labelFinished => 'Finished';

  @override
  String get labelMode => 'Mode';

  @override
  String get labelMoves => 'Moves';

  @override
  String get labelPlayers => 'Players';

  @override
  String get labelRuleset => 'Ruleset';

  @override
  String get labelWinner => 'Winner';

  @override
  String get mainMenu => 'Main Menu';

  @override
  String get modeLocal => 'Local multiplayer';

  @override
  String get modeLocalDescription => '2–4 players sharing this device.';

  @override
  String get modeOnline => 'Online multiplayer';

  @override
  String get modeOnlineDescription =>
      'Rooms, friends and live matches — coming in Phase 5.';

  @override
  String get modeShortVsAi => 'vs AI';

  @override
  String get modeTitle => 'Choose a mode';

  @override
  String get modeVsAi => 'Play vs AI';

  @override
  String get modeVsAiDescription =>
      'You against computer opponents (Easy, Medium, Hard).';

  @override
  String get monthApr => 'Apr';

  @override
  String get monthAug => 'Aug';

  @override
  String get monthDec => 'Dec';

  @override
  String get monthFeb => 'Feb';

  @override
  String get monthJan => 'Jan';

  @override
  String get monthJul => 'Jul';

  @override
  String get monthJun => 'Jun';

  @override
  String get monthMar => 'Mar';

  @override
  String get monthMay => 'May';

  @override
  String get monthNov => 'Nov';

  @override
  String get monthOct => 'Oct';

  @override
  String get monthSep => 'Sep';

  @override
  String get ok => 'OK';

  @override
  String playerName(int number) {
    return 'Player $number';
  }

  @override
  String playerWithAi(String name) {
    return '$name (AI)';
  }

  @override
  String get playersCountOne => '1 player';

  @override
  String playersCountOther(int count) {
    return '$count players';
  }

  @override
  String get resultsEmpty => 'No match result to show.';

  @override
  String get resultsPlayAgain => 'Play Again';

  @override
  String get resultsRecordFailed =>
      'This match finished, but it couldn\'t be saved to your history.';

  @override
  String get resultsTitle => 'Results';

  @override
  String get resultsWinnerBadge => 'Winner';

  @override
  String resultsWinnerWins(String name) {
    return '$name wins!';
  }

  @override
  String settingsFooter(String version) {
    return 'DiceUp $version — offline-first Ludo. Online play, friends and leaderboards arrive in later phases.';
  }

  @override
  String get settingsLoadFailed => 'Couldn\'t load settings';

  @override
  String get settingsResetConfirm => 'Reset';

  @override
  String get settingsResetDefaults => 'Reset to defaults';

  @override
  String get settingsResetMessage =>
      'Sound, vibration and volume return to their defaults.';

  @override
  String get settingsResetTitle => 'Reset settings?';

  @override
  String get settingsSaveFailed => 'Couldn\'t save that setting. Try again.';

  @override
  String get settingsSound => 'Sound';

  @override
  String get settingsSoundComingSoon =>
      'Coming soon — sound does not play anything yet.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsUnavailableHint =>
      'Your saved data couldn\'t be loaded, so settings cannot be changed right now.';

  @override
  String get settingsUnavailableTitle => 'Settings unavailable';

  @override
  String get settingsVibration => 'Vibration';

  @override
  String get settingsVibrationDescription => 'Haptic feedback on moves';

  @override
  String settingsVolume(int volume) {
    return 'Sound volume: $volume';
  }

  @override
  String get settingsVolumeStored =>
      'Stored for when sound arrives — moving this slider plays nothing.';

  @override
  String get setupAi => 'AI';

  @override
  String get setupAiDifficultyLabel => 'AI difficulty';

  @override
  String get setupColourLabel => 'Colour';

  @override
  String setupColourPlain(String colour) {
    return 'Colour $colour';
  }

  @override
  String setupColourSelected(String colour) {
    return 'Colour $colour, selected';
  }

  @override
  String setupColourTaken(String name) {
    return 'That colour is already taken by $name.';
  }

  @override
  String setupColourTakenBy(String colour, String name) {
    return 'Colour $colour, taken by $name';
  }

  @override
  String get setupDistinctColour => 'Each player needs a distinct colour.';

  @override
  String get setupHuman => 'Human';

  @override
  String get setupLoadingLast => 'Loading your last setup…';

  @override
  String get setupNameLabel => 'Name';

  @override
  String get setupNeedHuman => 'At least one seat must be human.';

  @override
  String get setupPlayers => 'Players';

  @override
  String get setupRuleExactFinish => 'Exact finish';

  @override
  String get setupRuleExactFinishDescription =>
      'A token needs an exact roll to reach home.';

  @override
  String get setupRuleExtraCapture => 'Extra turn on capture';

  @override
  String get setupRuleExtraCaptureDescription =>
      'Capturing a token earns another roll.';

  @override
  String get setupRuleExtraHome => 'Extra turn on home';

  @override
  String get setupRuleExtraHomeDescription =>
      'Bringing a token home earns another roll.';

  @override
  String get setupRuleExtraSix => 'Extra turn on six';

  @override
  String get setupRuleExtraSixDescription => 'Rolling a 6 earns another roll.';

  @override
  String get setupRuleReleaseOnOne => 'Release on 1';

  @override
  String get setupRuleReleaseOnOneDescription =>
      'A roll of 1 also releases a token.';

  @override
  String get setupRuleThirdSix => 'Third-six limit';

  @override
  String get setupRuleThirdSixDescription =>
      'Three sixes in a row forfeits the roll.';

  @override
  String get setupRules => 'Rules';

  @override
  String get setupSeats => 'Seats';

  @override
  String get setupStartMatch => 'Start match';

  @override
  String get shapeCircle => 'circle';

  @override
  String get shapeDiamond => 'diamond';

  @override
  String get shapeSquare => 'square';

  @override
  String get shapeTriangle => 'triangle';

  @override
  String get splashTagline => 'Multiplayer Ludo';

  @override
  String get statisticsHumanWins => 'Human wins';

  @override
  String get statisticsLoadFailed => 'Couldn\'t load statistics';

  @override
  String get statisticsLocalMatches => 'Local matches';

  @override
  String get statisticsMatchesPlayed => 'Matches played';

  @override
  String get statisticsMatchesVsAi => 'Matches vs AI';

  @override
  String get statisticsNoHumanWins =>
      'No human wins in your latest 500 matches yet.';

  @override
  String get statisticsNoMatches =>
      'No matches yet — finish an offline match and your totals will appear here.';

  @override
  String get statisticsPerPlayerCaption =>
      'Per-player wins from your latest 500 matches.';

  @override
  String statisticsSeatWins(String colour, int seat) {
    return 'Seat $seat · $colour';
  }

  @override
  String get statisticsTitle => 'Statistics';

  @override
  String get statisticsUnavailableHint =>
      'Your saved data couldn\'t be loaded, so statistics cannot be shown right now.';

  @override
  String get statisticsUnavailableTitle => 'Statistics unavailable';

  @override
  String get statisticsWinsBySeat => 'Wins by seat';

  @override
  String get tryAgain => 'Try again';

  @override
  String get winnerSuffix => ' — winner';
}
