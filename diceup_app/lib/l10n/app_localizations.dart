import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Semantics label of the Play vs AI mode card: title plus subtitle as one sentence, so a screen reader hears the mode and what it means.
  ///
  /// In en, this message translates to:
  /// **'Play vs AI. You against computer opponents (Easy, Medium, Hard).'**
  String get modeVsAiSemantics;

  /// Semantics label of the Local multiplayer mode card: title plus subtitle as one sentence.
  ///
  /// In en, this message translates to:
  /// **'Local multiplayer. 2–4 players sharing this device.'**
  String get modeLocalSemantics;

  /// The app name, shown in app bars and the splash screen. A proper noun, the same in every language.
  ///
  /// In en, this message translates to:
  /// **'DiceUp'**
  String get appName;

  /// Semantics label of a player avatar: name, seat shape and colour name (M2.9, NFR-08, D-27).
  ///
  /// In en, this message translates to:
  /// **'{name}, {shape} token, {colour}'**
  String avatarLabel(String colour, String name, String shape);

  /// Default dismiss action of confirmation dialogs.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Closes the match-detail dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Lower-case colour name, used inside sentences and semantics labels.
  ///
  /// In en, this message translates to:
  /// **'blue'**
  String get colourBlue;

  /// Lower-case colour name, used inside sentences and semantics labels.
  ///
  /// In en, this message translates to:
  /// **'green'**
  String get colourGreen;

  /// Lower-case colour name, used inside sentences and semantics labels (avatar, swatches, statistics).
  ///
  /// In en, this message translates to:
  /// **'red'**
  String get colourRed;

  /// Lower-case colour name, used inside sentences and semantics labels.
  ///
  /// In en, this message translates to:
  /// **'yellow'**
  String get colourYellow;

  /// Dice semantics label when no roll has happened and none is available.
  ///
  /// In en, this message translates to:
  /// **'Dice, no roll yet'**
  String get diceNoRollYet;

  /// Dice semantics label while a roll is in flight.
  ///
  /// In en, this message translates to:
  /// **'Dice, rolling'**
  String get diceRolling;

  /// Dice semantics label after a roll, when no roll is available.
  ///
  /// In en, this message translates to:
  /// **'Dice, showing {value}'**
  String diceShowing(int value);

  /// Dice semantics label after a roll, when another roll is available.
  ///
  /// In en, this message translates to:
  /// **'Dice, showing {value}. Tap to roll'**
  String diceShowingTap(int value);

  /// Tooltip of the dice when a roll is available.
  ///
  /// In en, this message translates to:
  /// **'Tap to roll'**
  String get diceTapToRoll;

  /// Dice semantics label before the first roll.
  ///
  /// In en, this message translates to:
  /// **'Dice, tap to roll'**
  String get diceTapToRollLabel;

  /// AI difficulty name in the setup difficulty dropdown.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get difficultyEasy;

  /// AI difficulty name in the setup difficulty dropdown.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get difficultyHard;

  /// AI difficulty name in the setup difficulty dropdown.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get difficultyMedium;

  /// Board semantics label when the match is finished and there is no winner (defensive case).
  ///
  /// In en, this message translates to:
  /// **'Ludo board. Match finished'**
  String get gameBoardFinished;

  /// Board semantics label during a turn with exactly one legal move.
  ///
  /// In en, this message translates to:
  /// **'Ludo board. {name}\'s turn, 1 legal move'**
  String gameBoardTurnOne(String name);

  /// Board semantics label during a turn with any number of legal moves other than one.
  ///
  /// In en, this message translates to:
  /// **'Ludo board. {name}\'s turn, {count} legal moves'**
  String gameBoardTurnOther(int count, String name);

  /// Board semantics label when the match is finished.
  ///
  /// In en, this message translates to:
  /// **'Ludo board. {name} won the match'**
  String gameBoardWinner(String name);

  /// Feedback for tapping the dice after rolling, when a token move is due.
  ///
  /// In en, this message translates to:
  /// **'Choose a token to move.'**
  String get gameDiceChooseToken;

  /// Feedback for tapping the dice during another player's turn.
  ///
  /// In en, this message translates to:
  /// **'It\'s not your turn yet.'**
  String get gameDiceNotYourTurn;

  /// Feedback for tapping the dice while a token hop is in flight.
  ///
  /// In en, this message translates to:
  /// **'Wait for the move to finish.'**
  String get gameDiceWaitMove;

  /// Feedback for tapping the dice while a roll is in flight.
  ///
  /// In en, this message translates to:
  /// **'Wait for the dice to settle.'**
  String get gameDiceWaitSettle;

  /// SnackBar + status feedback for a tap on a token that cannot move (M2.8, FR-21).
  ///
  /// In en, this message translates to:
  /// **'That token can\'t move now'**
  String get gameIllegalTokenMove;

  /// Confirm action of the leave-match confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get gameLeaveConfirm;

  /// Body of the leave-match confirmation dialog when the match is already finished.
  ///
  /// In en, this message translates to:
  /// **'This match is over.'**
  String get gameLeaveFinishedMessage;

  /// Title of the leave-match confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Leave the match?'**
  String get gameLeaveTitle;

  /// Body of the leave-match confirmation dialog when the match is unfinished.
  ///
  /// In en, this message translates to:
  /// **'Your progress in this match will be lost.'**
  String get gameLeaveUnfinishedMessage;

  /// Pause menu action: restart the match (asks confirmation).
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get gamePauseRestart;

  /// Pause menu action: resume the frozen match.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get gamePauseResume;

  /// Tooltip of the AppBar pause button on the game screen.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get gamePauseTooltip;

  /// Body of the pause menu dialog.
  ///
  /// In en, this message translates to:
  /// **'Take a break — the match is frozen.'**
  String get gamePausedMessage;

  /// Title of the pause menu dialog.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get gamePausedTitle;

  /// Player chip label: name and tokens home out of four.
  ///
  /// In en, this message translates to:
  /// **'{name} · Home {home}/4'**
  String gamePlayerHome(int home, String name);

  /// Confirm action of the restart confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get gameRestartConfirm;

  /// Body of the restart confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'The current match will be discarded.'**
  String get gameRestartMessage;

  /// Title of the restart confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Restart match?'**
  String get gameRestartTitle;

  /// Label of the Roll button on the game screen.
  ///
  /// In en, this message translates to:
  /// **'Roll dice'**
  String get gameRollDice;

  /// Label of the Roll button while a roll is in flight.
  ///
  /// In en, this message translates to:
  /// **'Rolling…'**
  String get gameRolling;

  /// Hint under the player chips on the game screen.
  ///
  /// In en, this message translates to:
  /// **'Safe cells are marked with a star. Tokens on safe cells cannot be captured.'**
  String get gameSafeCellsHint;

  /// Semantics label of the turn banner (M2.9).
  ///
  /// In en, this message translates to:
  /// **'{name}\'s turn'**
  String gameTurnBanner(String name);

  /// Duration of one minute or more in the history list.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String historyDurationMinutesSeconds(int minutes, int seconds);

  /// Duration under one minute in the history list.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String historyDurationSeconds(int seconds);

  /// History empty-state hint when no matches are stored.
  ///
  /// In en, this message translates to:
  /// **'Finished offline matches will appear here, newest first.'**
  String get historyEmptyHint;

  /// History empty-state title when no matches are stored.
  ///
  /// In en, this message translates to:
  /// **'No matches yet'**
  String get historyEmptyTitle;

  /// History empty-state hint when loading the stored matches failed.
  ///
  /// In en, this message translates to:
  /// **'Try again later.'**
  String get historyLoadFailedHint;

  /// History empty-state title when loading the stored matches failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load match history'**
  String get historyLoadFailedTitle;

  /// Badge on each history row: offline results never affect rankings (BR-18).
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get historyLocalBadge;

  /// Note at the bottom of the match-detail dialog (BR-18).
  ///
  /// In en, this message translates to:
  /// **'Local match — offline results never affect rankings.'**
  String get historyLocalNote;

  /// History row title for a match with no winner recorded.
  ///
  /// In en, this message translates to:
  /// **'{mode} · Finished'**
  String historyMatchFinished(String mode);

  /// History row subtitle: date, duration and player count.
  ///
  /// In en, this message translates to:
  /// **'{date} · {duration} · {players}'**
  String historyMatchLine(String date, String duration, String players);

  /// History row title naming the winner.
  ///
  /// In en, this message translates to:
  /// **'{mode} · {winner} won'**
  String historyMatchWon(String mode, String winner);

  /// Winner value in the match-detail dialog when no winner is recorded.
  ///
  /// In en, this message translates to:
  /// **'No winner recorded'**
  String get historyNoWinner;

  /// History empty-state hint when no dependencies are available.
  ///
  /// In en, this message translates to:
  /// **'Your saved data couldn\'t be loaded, so past matches cannot be shown right now.'**
  String get historyUnavailableHint;

  /// History empty-state title when no dependencies are available.
  ///
  /// In en, this message translates to:
  /// **'History unavailable'**
  String get historyUnavailableTitle;

  /// Duration shown when a stored match has no duration.
  ///
  /// In en, this message translates to:
  /// **'Unknown length'**
  String get historyUnknownLength;

  /// Snackbar shown once when the database could not be opened even after recovery. Same text as the data layer's kStartupDatabaseErrorMessage, which stays the data-layer source of truth.
  ///
  /// In en, this message translates to:
  /// **'Your saved data couldn\'t be loaded. You can still play, but matches and settings will not be saved this time.'**
  String get homeDatabaseError;

  /// Snackbar shown once when the database was unreadable and was recreated. Same text as the data layer's kDatabaseRecoveryMessage, which stays the data-layer source of truth.
  ///
  /// In en, this message translates to:
  /// **'Your local history couldn\'t be read, so it was reset. You can keep playing.'**
  String get homeDatabaseRecovered;

  /// Home button and history screen title.
  ///
  /// In en, this message translates to:
  /// **'Match History'**
  String get homeMatchHistory;

  /// Footnote at the bottom of the home screen.
  ///
  /// In en, this message translates to:
  /// **'Offline play works without an account or internet.'**
  String get homeOfflineNote;

  /// Body of the Play Online login-prompt dialog (M2.10, M-13).
  ///
  /// In en, this message translates to:
  /// **'Log in to play online — online play arrives in Phase 5.'**
  String get homeOnlineMessage;

  /// Home button: offline play.
  ///
  /// In en, this message translates to:
  /// **'Play Offline'**
  String get homePlayOffline;

  /// Home button and login-prompt dialog title: online play (Phase 5).
  ///
  /// In en, this message translates to:
  /// **'Play Online'**
  String get homePlayOnline;

  /// Home screen sub-headline.
  ///
  /// In en, this message translates to:
  /// **'Classic Ludo — offline, with friends.'**
  String get homeReadySubtitle;

  /// Home screen headline.
  ///
  /// In en, this message translates to:
  /// **'Ready to play?'**
  String get homeReadyTitle;

  /// Resume dialog action: delete the saved match.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get homeResumeDiscard;

  /// Body of the resume dialog.
  ///
  /// In en, this message translates to:
  /// **'You have a match in progress. Resume where you left off, or discard it and start fresh.'**
  String get homeResumeMessage;

  /// Resume dialog action: continue the saved match.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get homeResumeResume;

  /// Title of the resume dialog offered on Home when a saved match exists.
  ///
  /// In en, this message translates to:
  /// **'Resume your match?'**
  String get homeResumeTitle;

  /// Tooltip of the settings icon button on Home.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get homeSettingsTooltip;

  /// Snackbar shown once when a stored snapshot was corrupt and was discarded. Same text as the data layer's kCorruptSnapshotMessage, which stays the data-layer source of truth.
  ///
  /// In en, this message translates to:
  /// **'Your saved match couldn\'t be read, so it was discarded. You can start a new match.'**
  String get homeSnapshotCorrupt;

  /// Home button and statistics screen title.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get homeStatistics;

  /// Info-row label for the match length (results screen, history detail).
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get labelDuration;

  /// Info-row label for the finish date (results screen).
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get labelFinished;

  /// Info-row label for the match mode (results screen, history detail).
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get labelMode;

  /// Info-row label for the move count (results screen).
  ///
  /// In en, this message translates to:
  /// **'Moves'**
  String get labelMoves;

  /// Info-row label for the participants (results screen, history detail).
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get labelPlayers;

  /// Detail-row label for the ruleset version (history detail).
  ///
  /// In en, this message translates to:
  /// **'Ruleset'**
  String get labelRuleset;

  /// Detail-row label for the winner (history detail).
  ///
  /// In en, this message translates to:
  /// **'Winner'**
  String get labelWinner;

  /// Button that returns to the home screen (pause menu, results screen).
  ///
  /// In en, this message translates to:
  /// **'Main Menu'**
  String get mainMenu;

  /// Mode label for a local-multiplayer match (history, results, mode-selection card, setup screen title).
  ///
  /// In en, this message translates to:
  /// **'Local multiplayer'**
  String get modeLocal;

  /// Subtitle of the Local multiplayer mode card.
  ///
  /// In en, this message translates to:
  /// **'2–4 players sharing this device.'**
  String get modeLocalDescription;

  /// Title of the online mode card (not tappable until Phase 5).
  ///
  /// In en, this message translates to:
  /// **'Online multiplayer'**
  String get modeOnline;

  /// Subtitle of the online mode card.
  ///
  /// In en, this message translates to:
  /// **'Rooms, friends and live matches — coming in Phase 5.'**
  String get modeOnlineDescription;

  /// Short mode label used in the results screen and the history list/detail (as opposed to the 'Play vs AI' card title).
  ///
  /// In en, this message translates to:
  /// **'vs AI'**
  String get modeShortVsAi;

  /// Mode-selection screen title.
  ///
  /// In en, this message translates to:
  /// **'Choose a mode'**
  String get modeTitle;

  /// Mode card title and setup screen title for the vs-AI mode.
  ///
  /// In en, this message translates to:
  /// **'Play vs AI'**
  String get modeVsAi;

  /// Subtitle of the Play vs AI mode card.
  ///
  /// In en, this message translates to:
  /// **'You against computer opponents (Easy, Medium, Hard).'**
  String get modeVsAiDescription;

  /// Short month name used by the history and results date formats.
  ///
  /// In en, this message translates to:
  /// **'Apr'**
  String get monthApr;

  /// Short month name used by the history and results date formats.
  ///
  /// In en, this message translates to:
  /// **'Aug'**
  String get monthAug;

  /// Short month name used by the history and results date formats.
  ///
  /// In en, this message translates to:
  /// **'Dec'**
  String get monthDec;

  /// Short month name used by the history and results date formats.
  ///
  /// In en, this message translates to:
  /// **'Feb'**
  String get monthFeb;

  /// Short month name used by the history and results date formats.
  ///
  /// In en, this message translates to:
  /// **'Jan'**
  String get monthJan;

  /// Short month name used by the history and results date formats.
  ///
  /// In en, this message translates to:
  /// **'Jul'**
  String get monthJul;

  /// Short month name used by the history and results date formats.
  ///
  /// In en, this message translates to:
  /// **'Jun'**
  String get monthJun;

  /// Short month name used by the history and results date formats.
  ///
  /// In en, this message translates to:
  /// **'Mar'**
  String get monthMar;

  /// Short month name used by the history and results date formats.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get monthMay;

  /// Short month name used by the history and results date formats.
  ///
  /// In en, this message translates to:
  /// **'Nov'**
  String get monthNov;

  /// Short month name used by the history and results date formats.
  ///
  /// In en, this message translates to:
  /// **'Oct'**
  String get monthOct;

  /// Short month name used by the history and results date formats.
  ///
  /// In en, this message translates to:
  /// **'Sep'**
  String get monthSep;

  /// Acknowledges the Play Online login-prompt dialog.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// Default display name for a seat whose name field was left empty (D-28).
  ///
  /// In en, this message translates to:
  /// **'Player {number}'**
  String playerName(int number);

  /// A player's display name with the AI marker appended.
  ///
  /// In en, this message translates to:
  /// **'{name} (AI)'**
  String playerWithAi(String name);

  /// Player count when exactly one player is listed (results info row, history list line).
  ///
  /// In en, this message translates to:
  /// **'1 player'**
  String get playersCountOne;

  /// Player count for any number of players other than one.
  ///
  /// In en, this message translates to:
  /// **'{count} players'**
  String playersCountOther(int count);

  /// Empty state when the results route opens without a match result.
  ///
  /// In en, this message translates to:
  /// **'No match result to show.'**
  String get resultsEmpty;

  /// Results button: a fresh match with the same settings.
  ///
  /// In en, this message translates to:
  /// **'Play Again'**
  String get resultsPlayAgain;

  /// Notice on the results screen when the completed match could not be recorded. Same text as the presentation constant kMatchRecordFailedMessage, which stays the single source the tests assert against.
  ///
  /// In en, this message translates to:
  /// **'This match finished, but it couldn\'t be saved to your history.'**
  String get resultsRecordFailed;

  /// Results screen title.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get resultsTitle;

  /// Badge next to the winning player in the results player list.
  ///
  /// In en, this message translates to:
  /// **'Winner'**
  String get resultsWinnerBadge;

  /// Results headline naming the winner.
  ///
  /// In en, this message translates to:
  /// **'{name} wins!'**
  String resultsWinnerWins(String name);

  /// Version footer at the bottom of the settings screen. The version is kept in sync with pubspec.yaml by the footer test (M2.10).
  ///
  /// In en, this message translates to:
  /// **'DiceUp {version} — offline-first Ludo. Online play, friends and leaderboards arrive in later phases.'**
  String settingsFooter(String version);

  /// Error message when loading the stored settings failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load settings'**
  String get settingsLoadFailed;

  /// Confirm action of the reset-to-defaults confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get settingsResetConfirm;

  /// Settings button: restore the default settings.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get settingsResetDefaults;

  /// Body of the reset-to-defaults confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Sound, vibration and volume return to their defaults.'**
  String get settingsResetMessage;

  /// Title of the reset-to-defaults confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Reset settings?'**
  String get settingsResetTitle;

  /// Snackbar when persisting a setting change failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that setting. Try again.'**
  String get settingsSaveFailed;

  /// Sound toggle title (disabled until sound lands, D-32).
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get settingsSound;

  /// Subtitle of the disabled sound toggle.
  ///
  /// In en, this message translates to:
  /// **'Coming soon — sound does not play anything yet.'**
  String get settingsSoundComingSoon;

  /// Settings screen title and Home settings-button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings empty-state hint when no dependencies are available.
  ///
  /// In en, this message translates to:
  /// **'Your saved data couldn\'t be loaded, so settings cannot be changed right now.'**
  String get settingsUnavailableHint;

  /// Settings empty-state title when no dependencies are available.
  ///
  /// In en, this message translates to:
  /// **'Settings unavailable'**
  String get settingsUnavailableTitle;

  /// Vibration toggle title.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get settingsVibration;

  /// Subtitle of the vibration toggle.
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback on moves'**
  String get settingsVibrationDescription;

  /// Label above the sound volume slider.
  ///
  /// In en, this message translates to:
  /// **'Sound volume: {volume}'**
  String settingsVolume(int volume);

  /// Note under the sound volume slider.
  ///
  /// In en, this message translates to:
  /// **'Stored for when sound arrives — moving this slider plays nothing.'**
  String get settingsVolumeStored;

  /// Seat-type segment: an AI plays this seat.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get setupAi;

  /// Label of the AI difficulty dropdown.
  ///
  /// In en, this message translates to:
  /// **'AI difficulty'**
  String get setupAiDifficultyLabel;

  /// Label above a seat's colour swatches.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get setupColourLabel;

  /// Semantics label and tooltip of a colour swatch that is free to pick.
  ///
  /// In en, this message translates to:
  /// **'Colour {colour}'**
  String setupColourPlain(String colour);

  /// Semantics label of a colour swatch that is the seat's current colour.
  ///
  /// In en, this message translates to:
  /// **'Colour {colour}, selected'**
  String setupColourSelected(String colour);

  /// Visible error when a colour taken by another seat in the match is picked.
  ///
  /// In en, this message translates to:
  /// **'That colour is already taken by {name}.'**
  String setupColourTaken(String name);

  /// Semantics label of a colour swatch held by another seat in the match.
  ///
  /// In en, this message translates to:
  /// **'Colour {colour}, taken by {name}'**
  String setupColourTakenBy(String colour, String name);

  /// Validation error: two seats share a colour (defence-in-depth; the picker prevents it).
  ///
  /// In en, this message translates to:
  /// **'Each player needs a distinct colour.'**
  String get setupDistinctColour;

  /// Seat-type segment: a human plays this seat.
  ///
  /// In en, this message translates to:
  /// **'Human'**
  String get setupHuman;

  /// Loading state while the last-used setup options load.
  ///
  /// In en, this message translates to:
  /// **'Loading your last setup…'**
  String get setupLoadingLast;

  /// Label of a seat's name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get setupNameLabel;

  /// Validation error and inline warning when no seat is human (FR-14).
  ///
  /// In en, this message translates to:
  /// **'At least one seat must be human.'**
  String get setupNeedHuman;

  /// Setup section heading for the player count.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get setupPlayers;

  /// Ruleset switch title: an exact roll is needed to reach home.
  ///
  /// In en, this message translates to:
  /// **'Exact finish'**
  String get setupRuleExactFinish;

  /// Ruleset switch subtitle for exact finish.
  ///
  /// In en, this message translates to:
  /// **'A token needs an exact roll to reach home.'**
  String get setupRuleExactFinishDescription;

  /// Ruleset switch title: capturing a token earns another roll.
  ///
  /// In en, this message translates to:
  /// **'Extra turn on capture'**
  String get setupRuleExtraCapture;

  /// Ruleset switch subtitle for extra turn on capture.
  ///
  /// In en, this message translates to:
  /// **'Capturing a token earns another roll.'**
  String get setupRuleExtraCaptureDescription;

  /// Ruleset switch title: bringing a token home earns another roll.
  ///
  /// In en, this message translates to:
  /// **'Extra turn on home'**
  String get setupRuleExtraHome;

  /// Ruleset switch subtitle for extra turn on home.
  ///
  /// In en, this message translates to:
  /// **'Bringing a token home earns another roll.'**
  String get setupRuleExtraHomeDescription;

  /// Ruleset switch title: rolling a 6 earns another roll.
  ///
  /// In en, this message translates to:
  /// **'Extra turn on six'**
  String get setupRuleExtraSix;

  /// Ruleset switch subtitle for extra turn on six.
  ///
  /// In en, this message translates to:
  /// **'Rolling a 6 earns another roll.'**
  String get setupRuleExtraSixDescription;

  /// Ruleset switch title: a roll of 1 releases a token.
  ///
  /// In en, this message translates to:
  /// **'Release on 1'**
  String get setupRuleReleaseOnOne;

  /// Ruleset switch subtitle for release-on-1.
  ///
  /// In en, this message translates to:
  /// **'A roll of 1 also releases a token.'**
  String get setupRuleReleaseOnOneDescription;

  /// Ruleset switch title: three sixes in a row forfeit the roll.
  ///
  /// In en, this message translates to:
  /// **'Third-six limit'**
  String get setupRuleThirdSix;

  /// Ruleset switch subtitle for the third-six limit.
  ///
  /// In en, this message translates to:
  /// **'Three sixes in a row forfeits the roll.'**
  String get setupRuleThirdSixDescription;

  /// Setup section heading for the ruleset switches.
  ///
  /// In en, this message translates to:
  /// **'Rules'**
  String get setupRules;

  /// Setup section heading for the per-seat cards.
  ///
  /// In en, this message translates to:
  /// **'Seats'**
  String get setupSeats;

  /// Setup button: start the match with the chosen options.
  ///
  /// In en, this message translates to:
  /// **'Start match'**
  String get setupStartMatch;

  /// Token shape name, used in the avatar semantics label.
  ///
  /// In en, this message translates to:
  /// **'circle'**
  String get shapeCircle;

  /// Token shape name, used in the avatar semantics label.
  ///
  /// In en, this message translates to:
  /// **'diamond'**
  String get shapeDiamond;

  /// Token shape name, used in the avatar semantics label.
  ///
  /// In en, this message translates to:
  /// **'square'**
  String get shapeSquare;

  /// Token shape name, used in the avatar semantics label.
  ///
  /// In en, this message translates to:
  /// **'triangle'**
  String get shapeTriangle;

  /// Tagline under the DiceUp mark on the splash screen.
  ///
  /// In en, this message translates to:
  /// **'Multiplayer Ludo'**
  String get splashTagline;

  /// Statistics row label: lifetime matches won by a human seat (D-24).
  ///
  /// In en, this message translates to:
  /// **'Human wins'**
  String get statisticsHumanWins;

  /// Error message when loading the statistics failed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load statistics'**
  String get statisticsLoadFailed;

  /// Statistics row label: lifetime local-multiplayer matches.
  ///
  /// In en, this message translates to:
  /// **'Local matches'**
  String get statisticsLocalMatches;

  /// Statistics row label: lifetime matches played.
  ///
  /// In en, this message translates to:
  /// **'Matches played'**
  String get statisticsMatchesPlayed;

  /// Statistics row label: lifetime matches against AI seats.
  ///
  /// In en, this message translates to:
  /// **'Matches vs AI'**
  String get statisticsMatchesVsAi;

  /// Shown when no human seat has won in the retained history.
  ///
  /// In en, this message translates to:
  /// **'No human wins in your latest 500 matches yet.'**
  String get statisticsNoHumanWins;

  /// Note shown when no match has been played yet.
  ///
  /// In en, this message translates to:
  /// **'No matches yet — finish an offline match and your totals will appear here.'**
  String get statisticsNoMatches;

  /// Caption for the per-player breakdown, which is computed from retained history only (M1.7, D-24). Same text as the presentation constant kPerPlayerWinsCaption, which stays the single source the tests assert against.
  ///
  /// In en, this message translates to:
  /// **'Per-player wins from your latest 500 matches.'**
  String get statisticsPerPlayerCaption;

  /// Per-seat win row label: seat number and colour name.
  ///
  /// In en, this message translates to:
  /// **'Seat {seat} · {colour}'**
  String statisticsSeatWins(String colour, int seat);

  /// Statistics screen title.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statisticsTitle;

  /// Statistics empty-state hint when no dependencies are available.
  ///
  /// In en, this message translates to:
  /// **'Your saved data couldn\'t be loaded, so statistics cannot be shown right now.'**
  String get statisticsUnavailableHint;

  /// Statistics empty-state title when no dependencies are available.
  ///
  /// In en, this message translates to:
  /// **'Statistics unavailable'**
  String get statisticsUnavailableTitle;

  /// Heading above the per-seat win breakdown.
  ///
  /// In en, this message translates to:
  /// **'Wins by seat'**
  String get statisticsWinsBySeat;

  /// Retry action of the shared error view.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// Suffix appended to a player's name in the history detail view when that player won the match.
  ///
  /// In en, this message translates to:
  /// **' — winner'**
  String get winnerSuffix;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
