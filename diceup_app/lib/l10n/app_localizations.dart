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

  /// Account screen: opens the change-password form.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get accountChangePassword;

  /// Account screen: the player's display name.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get accountDisplayName;

  /// Account screen: the player's email address.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get accountEmail;

  /// Account screen: shown when the email is not yet verified.
  ///
  /// In en, this message translates to:
  /// **'Email not verified'**
  String get accountEmailNotVerified;

  /// Account screen: label of the email-verification status row.
  ///
  /// In en, this message translates to:
  /// **'Email status'**
  String get accountEmailStatus;

  /// Account screen: shown when the email is verified.
  ///
  /// In en, this message translates to:
  /// **'Email verified'**
  String get accountEmailVerified;

  /// Account screen: signs out of the online account.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get accountLogOut;

  /// Account screen: online matches played.
  ///
  /// In en, this message translates to:
  /// **'Matches played'**
  String get accountMatchesPlayed;

  /// Account screen: online matches won.
  ///
  /// In en, this message translates to:
  /// **'Matches won'**
  String get accountMatchesWon;

  /// Account screen: who is signed in.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name}'**
  String accountSignedInAs(String name);

  /// Account screen title.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountTitle;

  /// Account screen: the player's username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get accountUsername;

  /// Account screen: opens the email-verification screen.
  ///
  /// In en, this message translates to:
  /// **'Verify email'**
  String get accountVerifyEmail;

  /// The app name, shown in app bars and the splash screen. A proper noun, the same in every language.
  ///
  /// In en, this message translates to:
  /// **'DiceUp'**
  String get appName;

  /// Label of the email-verification / reset code field.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get authCodeLabel;

  /// Label of the repeat-new-password field.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get authConfirmPasswordLabel;

  /// Label of the current-password field.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get authCurrentPasswordLabel;

  /// Label of the optional display-name field on registration.
  ///
  /// In en, this message translates to:
  /// **'Display name (optional)'**
  String get authDisplayNameLabel;

  /// Label of the email field.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// Label of the login identifier field.
  ///
  /// In en, this message translates to:
  /// **'Email or username'**
  String get authEmailOrUsernameLabel;

  /// Auth error: the account is suspended.
  ///
  /// In en, this message translates to:
  /// **'This account is suspended.'**
  String get authErrorAccountSuspended;

  /// Auth error: the route needs a verified email.
  ///
  /// In en, this message translates to:
  /// **'Your email isn\'t verified yet. Check your inbox for the code.'**
  String get authErrorEmailNotVerified;

  /// Auth error: registration email is taken.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists.'**
  String get authErrorEmailTaken;

  /// Auth error: the server refused the request.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to do that.'**
  String get authErrorForbidden;

  /// Auth error: the verification / reset code field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter the code from the email.'**
  String get authErrorInvalidCode;

  /// Auth error: wrong login credentials.
  ///
  /// In en, this message translates to:
  /// **'Email or password is incorrect.'**
  String get authErrorInvalidCredentials;

  /// Auth error: the email field is not a valid email.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get authErrorInvalidEmail;

  /// Auth error: the username field is invalid.
  ///
  /// In en, this message translates to:
  /// **'Username must be 3–30 characters: letters, digits, dot, underscore or hyphen.'**
  String get authErrorInvalidUsername;

  /// Auth error: no network / server unreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the server. Check your connection and try again.'**
  String get authErrorNetwork;

  /// Auth error: the password is too short.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters.'**
  String get authErrorPasswordTooShort;

  /// Auth error: the two password fields differ.
  ///
  /// In en, this message translates to:
  /// **'Passwords don\'t match.'**
  String get authErrorPasswordsDoNotMatch;

  /// Auth error: the server rate-limited the request.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in a moment.'**
  String get authErrorRateLimited;

  /// Auth error: a required field is empty.
  ///
  /// In en, this message translates to:
  /// **'This field is required.'**
  String get authErrorRequired;

  /// Auth error: the session expired or was revoked.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Log in again.'**
  String get authErrorSessionExpired;

  /// Auth error: the request timed out.
  ///
  /// In en, this message translates to:
  /// **'The request timed out. Try again.'**
  String get authErrorTimeout;

  /// Auth error: the email token expired.
  ///
  /// In en, this message translates to:
  /// **'That code has expired. Request a new one.'**
  String get authErrorTokenExpired;

  /// Auth error: the email token is unknown.
  ///
  /// In en, this message translates to:
  /// **'That code isn\'t right. Check it and try again.'**
  String get authErrorTokenInvalid;

  /// Auth error: the email token was already used.
  ///
  /// In en, this message translates to:
  /// **'That code has already been used.'**
  String get authErrorTokenUsed;

  /// Auth error: unexpected server response.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Try again.'**
  String get authErrorUnexpected;

  /// Auth error: registration username is taken.
  ///
  /// In en, this message translates to:
  /// **'That username is already taken.'**
  String get authErrorUsernameTaken;

  /// Auth error: the server rejected a field value.
  ///
  /// In en, this message translates to:
  /// **'Check the highlighted fields and try again.'**
  String get authErrorValidation;

  /// Auth info: the reset email was requested.
  ///
  /// In en, this message translates to:
  /// **'If an account exists for that email, a reset code has been sent.'**
  String get authInfoForgotSent;

  /// Auth info: the password was changed.
  ///
  /// In en, this message translates to:
  /// **'Password changed. Log in with your new password.'**
  String get authInfoPasswordChanged;

  /// Auth info: registration succeeded.
  ///
  /// In en, this message translates to:
  /// **'Account created — check your email for the verification code.'**
  String get authInfoRegisterDone;

  /// Auth info: the password was reset.
  ///
  /// In en, this message translates to:
  /// **'Password reset. Log in with your new password.'**
  String get authInfoResetDone;

  /// Auth info: the email was verified.
  ///
  /// In en, this message translates to:
  /// **'Email verified. Welcome to DiceUp online.'**
  String get authInfoVerifyDone;

  /// Auth info: the verification email was resent.
  ///
  /// In en, this message translates to:
  /// **'A new code has been sent.'**
  String get authInfoVerifyResent;

  /// Label of the new-password field.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get authNewPasswordLabel;

  /// Label of the password field.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// Label of the username field.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get authUsernameLabel;

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

  /// Forgot-password screen: requests the reset email.
  ///
  /// In en, this message translates to:
  /// **'Send reset code'**
  String get forgotButton;

  /// Forgot-password screen: what the screen does.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and we\'ll send you a reset code.'**
  String get forgotMessage;

  /// Forgot-password screen title.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get forgotTitle;

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

  /// Home: Play Online dialog action for a signed-in player.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get homeOnlineLogOut;

  /// Body of the Play Online login-prompt dialog (M2.10, M-13).
  ///
  /// In en, this message translates to:
  /// **'Log in to play online with friends.'**
  String get homeOnlineMessage;

  /// Home: Play Online dialog action for a signed-in player, opens the online lobby.
  ///
  /// In en, this message translates to:
  /// **'Play online'**
  String get homeOnlinePlay;

  /// Home: Play Online dialog for a signed-in player.
  ///
  /// In en, this message translates to:
  /// **'You\'re signed in as {name}.'**
  String homeOnlineSignedIn(String name);

  /// Home: Play Online dialog action for a signed-in player.
  ///
  /// In en, this message translates to:
  /// **'View account'**
  String get homeOnlineViewAccount;

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

  /// Login screen: submits the login form.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get loginButton;

  /// Login screen: link to the forgot-password screen.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get loginForgotPassword;

  /// Login screen: link to the registration screen.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Create one'**
  String get loginNoAccount;

  /// Login screen title.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get loginTitle;

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

  /// Semantics label of the Local multiplayer mode card: title plus subtitle as one sentence.
  ///
  /// In en, this message translates to:
  /// **'Local multiplayer. 2–4 players sharing this device.'**
  String get modeLocalSemantics;

  /// Title of the online mode card.
  ///
  /// In en, this message translates to:
  /// **'Online multiplayer'**
  String get modeOnline;

  /// Subtitle of the online mode card.
  ///
  /// In en, this message translates to:
  /// **'Play a live match with friends in a room, or find a match.'**
  String get modeOnlineDescription;

  /// Semantics label of the online mode card: title plus subtitle as one sentence.
  ///
  /// In en, this message translates to:
  /// **'Online multiplayer. Play a live match with friends in a room, or find a match.'**
  String get modeOnlineSemantics;

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

  /// Semantics label of the Play vs AI mode card: title plus subtitle as one sentence, so a screen reader hears the mode and what it means.
  ///
  /// In en, this message translates to:
  /// **'Play vs AI. You against computer opponents (Easy, Medium, Hard).'**
  String get modeVsAiSemantics;

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

  /// Matchmaking screen: leaves the queue.
  ///
  /// In en, this message translates to:
  /// **'Leave queue'**
  String get onlineCancelQueue;

  /// Lobby: confirmation that the room code was copied.
  ///
  /// In en, this message translates to:
  /// **'Room code copied'**
  String get onlineCodeCopied;

  /// Join form: hint under the room-code field.
  ///
  /// In en, this message translates to:
  /// **'Ask the host for the 6-letter code'**
  String get onlineCodeHint;

  /// Join form: label of the room-code field.
  ///
  /// In en, this message translates to:
  /// **'Room code'**
  String get onlineCodeLabel;

  /// Connection banner: the first handshake is in flight.
  ///
  /// In en, this message translates to:
  /// **'Connecting to the game server…'**
  String get onlineConnectionConnecting;

  /// Connection banner: no socket; honest that nothing is queued while offline.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Moves cannot be sent while you are disconnected — nothing is queued.'**
  String get onlineConnectionDisconnected;

  /// Connection banner: the socket dropped and the client is retrying.
  ///
  /// In en, this message translates to:
  /// **'Connection lost. Reconnecting… Moves cannot be sent until you are back.'**
  String get onlineConnectionReconnecting;

  /// Connection banner: manual reconnect action.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get onlineConnectionRetry;

  /// Lobby: copies the room code to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get onlineCopyCode;

  /// Lobby entry: creates the room.
  ///
  /// In en, this message translates to:
  /// **'Create room'**
  String get onlineCreateButton;

  /// Lobby entry: create-room section title.
  ///
  /// In en, this message translates to:
  /// **'Create a room'**
  String get onlineCreateTitle;

  /// Lobby error: the player is already in an active match.
  ///
  /// In en, this message translates to:
  /// **'You are already in an active match.'**
  String get onlineErrorAlreadyInMatch;

  /// Matchmaking error: the player is already queued.
  ///
  /// In en, this message translates to:
  /// **'You are already in the matchmaking queue.'**
  String get onlineErrorAlreadyInMatchmaking;

  /// Lobby error: the player is already in a room.
  ///
  /// In en, this message translates to:
  /// **'You are already in a room.'**
  String get onlineErrorAlreadyInRoom;

  /// Game error: the attempted move is not legal in the current state.
  ///
  /// In en, this message translates to:
  /// **'That move is not legal right now.'**
  String get onlineErrorIllegalMove;

  /// Lobby error: the action is not possible right now.
  ///
  /// In en, this message translates to:
  /// **'That cannot be done right now.'**
  String get onlineErrorInvalidState;

  /// Game error: the match has already finished.
  ///
  /// In en, this message translates to:
  /// **'That match has finished.'**
  String get onlineErrorMatchFinished;

  /// Game error: the match no longer exists.
  ///
  /// In en, this message translates to:
  /// **'That match no longer exists.'**
  String get onlineErrorMatchNotFound;

  /// Matchmaking error: the queue is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Matchmaking is temporarily unavailable.'**
  String get onlineErrorMatchmakingUnavailable;

  /// Lobby error: the server could not be reached.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check your connection.'**
  String get onlineErrorNetwork;

  /// Lobby error: only the host can do that.
  ///
  /// In en, this message translates to:
  /// **'Only the host can do that.'**
  String get onlineErrorNotRoomHost;

  /// Game error: the viewer is not a player in this match.
  ///
  /// In en, this message translates to:
  /// **'You are not a player in this match.'**
  String get onlineErrorNotMatchPlayer;

  /// Lobby error: not a member of the room.
  ///
  /// In en, this message translates to:
  /// **'You are not a member of this room.'**
  String get onlineErrorNotRoomMember;

  /// Game error: the player tried to act outside their turn.
  ///
  /// In en, this message translates to:
  /// **'It is not your turn.'**
  String get onlineErrorNotYourTurn;

  /// Lobby error: the room is full.
  ///
  /// In en, this message translates to:
  /// **'That room is full.'**
  String get onlineErrorRoomFull;

  /// Lobby error: no open room has that code.
  ///
  /// In en, this message translates to:
  /// **'No open room has that code.'**
  String get onlineErrorRoomNotFound;

  /// Lobby error: the room has already started.
  ///
  /// In en, this message translates to:
  /// **'That room has already started.'**
  String get onlineErrorRoomStarted;

  /// Game error: the client view is behind the server state.
  ///
  /// In en, this message translates to:
  /// **'Your view of the match is out of date. Reconnecting…'**
  String get onlineErrorStaleState;

  /// Lobby error: the request timed out.
  ///
  /// In en, this message translates to:
  /// **'The request timed out.'**
  String get onlineErrorTimeout;

  /// Lobby error: generic fallback.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get onlineErrorUnexpected;

  /// Game screen: confirms leaving the match (a forfeit).
  ///
  /// In en, this message translates to:
  /// **'Leave and forfeit'**
  String get onlineGameForfeitConfirm;

  /// Game screen: leaving mid-match forfeits for the leaver only.
  ///
  /// In en, this message translates to:
  /// **'Leaving now forfeits the match for you. The other players keep playing.'**
  String get onlineGameForfeitMessage;

  /// Game screen: leave-match confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Leave match?'**
  String get onlineGameForfeitTitle;

  /// Game screen: leave-match action.
  ///
  /// In en, this message translates to:
  /// **'Leave match'**
  String get onlineGameLeave;

  /// Game screen: the first snapshot could not be loaded.
  ///
  /// In en, this message translates to:
  /// **'Could not load the match. Try again.'**
  String get onlineGameLoadFailed;

  /// Game screen: the first snapshot is loading.
  ///
  /// In en, this message translates to:
  /// **'Loading match…'**
  String get onlineGameLoading;

  /// Game screen: local missed-turn count and the server auto-play rule.
  ///
  /// In en, this message translates to:
  /// **'Missed turns: {count} of 3 — if your turn runs out, the server plays your first legal move.'**
  String onlineGameMissedTurns(int count);

  /// Game screen: per-player grace countdown while disconnected.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s left to reconnect'**
  String onlineGamePlayerDisconnected(int seconds);

  /// Game screen: per-player status after a forfeit.
  ///
  /// In en, this message translates to:
  /// **'Forfeited'**
  String get onlineGamePlayerForfeited;

  /// Game screen title.
  ///
  /// In en, this message translates to:
  /// **'Online match'**
  String get onlineGameTitle;

  /// Game screen: seconds left on the current turn.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s left'**
  String onlineGameTurnTimeLeft(int seconds);

  /// Game screen: turn banner while another player moves.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {name}'**
  String onlineGameWaitingFor(String name);

  /// Game screen: turn banner on the local player's turn.
  ///
  /// In en, this message translates to:
  /// **'Your turn'**
  String get onlineGameYourTurn;

  /// Matchmaking screen: opens the matched room's lobby.
  ///
  /// In en, this message translates to:
  /// **'Go to lobby'**
  String get onlineGoToLobby;

  /// Lobby: badge marking the host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get onlineHost;

  /// Lobby entry: joins the room by code.
  ///
  /// In en, this message translates to:
  /// **'Join room'**
  String get onlineJoinButton;

  /// Matchmaking screen: joins the queue.
  ///
  /// In en, this message translates to:
  /// **'Find a match'**
  String get onlineJoinQueue;

  /// Lobby entry: join-room section title.
  ///
  /// In en, this message translates to:
  /// **'Join a room'**
  String get onlineJoinTitle;

  /// Lobby: leaves the room.
  ///
  /// In en, this message translates to:
  /// **'Leave room'**
  String get onlineLeaveRoom;

  /// Lobby screen title.
  ///
  /// In en, this message translates to:
  /// **'Online lobby'**
  String get onlineLobbyTitle;

  /// Matchmaking screen: a group formed; shows the room code.
  ///
  /// In en, this message translates to:
  /// **'Match found! Room code: {code}'**
  String onlineMatched(String code);

  /// Matchmaking screen title.
  ///
  /// In en, this message translates to:
  /// **'Matchmaking'**
  String get onlineMatchmakingTitle;

  /// Lobby: the match started.
  ///
  /// In en, this message translates to:
  /// **'Match started!'**
  String get onlineMatchStarted;

  /// Create form: player-limit label.
  ///
  /// In en, this message translates to:
  /// **'Players'**
  String get onlineMaxPlayers;

  /// Lobby: member-list section title.
  ///
  /// In en, this message translates to:
  /// **'Players in room'**
  String get onlineMembers;

  /// Lobby: start is blocked, fewer than 2 players.
  ///
  /// In en, this message translates to:
  /// **'At least 2 players are needed to start.'**
  String get onlineNeedPlayers;

  /// Lobby: start is blocked, not everyone is ready.
  ///
  /// In en, this message translates to:
  /// **'Every player must be ready before the match starts.'**
  String get onlineNeedReady;

  /// Lobby: start is blocked, the viewer is not the host.
  ///
  /// In en, this message translates to:
  /// **'Only the host can start the match.'**
  String get onlineNotHost;

  /// Game screen: a player disconnected; grace countdown shown.
  ///
  /// In en, this message translates to:
  /// **'{name} disconnected — {seconds}s left to reconnect'**
  String onlinePlayerDisconnected(String name, int seconds);

  /// Game screen: a player forfeited.
  ///
  /// In en, this message translates to:
  /// **'{name} forfeited the match'**
  String onlinePlayerForfeited(String name);

  /// Game screen: a player reconnected inside their grace.
  ///
  /// In en, this message translates to:
  /// **'{name} reconnected'**
  String onlinePlayerReconnected(String name);

  /// Matchmaking screen: the player's queue position.
  ///
  /// In en, this message translates to:
  /// **'You are #{position} in the queue.'**
  String onlineQueuePosition(int position);

  /// Matchmaking screen: how many players are waiting.
  ///
  /// In en, this message translates to:
  /// **'{count} players waiting'**
  String onlineQueueSize(int count);

  /// Lobby: the readiness toggle.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get onlineReady;

  /// Create form: the frozen ruleset shown before readiness (G-16).
  ///
  /// In en, this message translates to:
  /// **'Ruleset {version} — standard DiceUp rules, 4 players max.'**
  String onlineRulesetSummary(String version);

  /// Lobby: shares the room code.
  ///
  /// In en, this message translates to:
  /// **'Share code'**
  String get onlineShareCode;

  /// Lobby: the shared invite text (room-code share only).
  ///
  /// In en, this message translates to:
  /// **'Join my DiceUp room! Code: {code}'**
  String onlineShareMessage(String code);

  /// Lobby: host starts the match.
  ///
  /// In en, this message translates to:
  /// **'Start match'**
  String get onlineStartMatch;

  /// Lobby: badge marking the signed-in player.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get onlineYou;

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

  /// Registration screen: submits the form.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerButton;

  /// Registration screen: link to the login screen.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Log in'**
  String get registerHaveAccount;

  /// Registration screen title.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get registerTitle;

  /// Reset-password screen: submits the code and new password.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get resetButton;

  /// Reset-password screen: what the screen does.
  ///
  /// In en, this message translates to:
  /// **'Enter the code from the reset email and choose a new password.'**
  String get resetMessage;

  /// Reset-password screen title.
  ///
  /// In en, this message translates to:
  /// **'Enter reset code'**
  String get resetTitle;

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

  /// Tokens-home count next to a player on the results screen (M3 premium, §2.6/Q8).
  ///
  /// In en, this message translates to:
  /// **'Home {home}/4'**
  String resultsPlayerHome(int home);

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

  /// Verification screen: submits the code.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verifyButton;

  /// Verification screen: what the screen does.
  ///
  /// In en, this message translates to:
  /// **'We sent a verification code to {email}. Enter it below.'**
  String verifyMessage(String email);

  /// Verification screen: sends a new code.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get verifyResend;

  /// Verification screen title.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get verifyTitle;

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
