// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get accountChangePassword => 'Change password';

  @override
  String get accountDisplayName => 'Display name';

  @override
  String get accountEmail => 'Email';

  @override
  String get accountEmailNotVerified => 'Email not verified';

  @override
  String get accountEmailStatus => 'Email status';

  @override
  String get accountEmailVerified => 'Email verified';

  @override
  String get accountLogOut => 'Log out';

  @override
  String get accountMatchesPlayed => 'Matches played';

  @override
  String get accountMatchesWon => 'Matches won';

  @override
  String accountSignedInAs(String name) {
    return 'Signed in as $name';
  }

  @override
  String get accountTitle => 'Account';

  @override
  String get accountUsername => 'Username';

  @override
  String get accountVerifyEmail => 'Verify email';

  @override
  String get appName => 'DiceUp';

  @override
  String get authCodeLabel => 'Verification code';

  @override
  String get authConfirmPasswordLabel => 'Confirm password';

  @override
  String get authCurrentPasswordLabel => 'Current password';

  @override
  String get authDisplayNameLabel => 'Display name (optional)';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authEmailOrUsernameLabel => 'Email or username';

  @override
  String get authErrorAccountSuspended => 'This account is suspended.';

  @override
  String get authErrorEmailNotVerified =>
      'Your email isn\'t verified yet. Check your inbox for the code.';

  @override
  String get authErrorEmailTaken =>
      'An account with this email already exists.';

  @override
  String get authErrorForbidden => 'You don\'t have permission to do that.';

  @override
  String get authErrorInvalidCode => 'Enter the code from the email.';

  @override
  String get authErrorInvalidCredentials => 'Email or password is incorrect.';

  @override
  String get authErrorInvalidEmail => 'Enter a valid email address.';

  @override
  String get authErrorInvalidUsername =>
      'Username must be 3–30 characters: letters, digits, dot, underscore or hyphen.';

  @override
  String get authErrorNetwork =>
      'Couldn\'t reach the server. Check your connection and try again.';

  @override
  String get authErrorPasswordTooShort =>
      'Password must be at least 8 characters.';

  @override
  String get authErrorPasswordsDoNotMatch => 'Passwords don\'t match.';

  @override
  String get authErrorRateLimited =>
      'Too many attempts. Try again in a moment.';

  @override
  String get authErrorRequired => 'This field is required.';

  @override
  String get authErrorSessionExpired => 'Your session expired. Log in again.';

  @override
  String get authErrorTimeout => 'The request timed out. Try again.';

  @override
  String get authErrorTokenExpired =>
      'That code has expired. Request a new one.';

  @override
  String get authErrorTokenInvalid =>
      'That code isn\'t right. Check it and try again.';

  @override
  String get authErrorTokenUsed => 'That code has already been used.';

  @override
  String get authErrorUnexpected => 'Something went wrong. Try again.';

  @override
  String get authErrorUsernameTaken => 'That username is already taken.';

  @override
  String get authErrorValidation =>
      'Check the highlighted fields and try again.';

  @override
  String get authInfoForgotSent =>
      'If an account exists for that email, a reset code has been sent.';

  @override
  String get authInfoPasswordChanged =>
      'Password changed. Log in with your new password.';

  @override
  String get authInfoRegisterDone =>
      'Account created — check your email for the verification code.';

  @override
  String get authInfoResetDone =>
      'Password reset. Log in with your new password.';

  @override
  String get authInfoVerifyDone => 'Email verified. Welcome to DiceUp online.';

  @override
  String get authInfoVerifyResent => 'A new code has been sent.';

  @override
  String get authNewPasswordLabel => 'New password';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authUsernameLabel => 'Username';

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
  String get forgotButton => 'Send reset code';

  @override
  String get forgotMessage =>
      'Enter your email and we\'ll send you a reset code.';

  @override
  String get forgotTitle => 'Reset password';

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
  String get homeOnlineLogOut => 'Log out';

  @override
  String get homeOnlineMessage => 'Log in to play online with friends.';

  @override
  String get homeOnlinePlay => 'Play online';

  @override
  String homeOnlineSignedIn(String name) {
    return 'You\'re signed in as $name.';
  }

  @override
  String get homeOnlineViewAccount => 'View account';

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
  String get loginButton => 'Log in';

  @override
  String get loginForgotPassword => 'Forgot password?';

  @override
  String get loginNoAccount => 'Don\'t have an account? Create one';

  @override
  String get loginTitle => 'Log in';

  @override
  String get mainMenu => 'Main Menu';

  @override
  String get modeLocal => 'Local multiplayer';

  @override
  String get modeLocalDescription => '2–4 players sharing this device.';

  @override
  String get modeLocalSemantics =>
      'Local multiplayer. 2–4 players sharing this device.';

  @override
  String get modeOnline => 'Online multiplayer';

  @override
  String get modeOnlineDescription =>
      'Play a live match with friends in a room, or find a match.';

  @override
  String get modeOnlineSemantics =>
      'Online multiplayer. Play a live match with friends in a room, or find a match.';

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
  String get modeVsAiSemantics =>
      'Play vs AI. You against computer opponents (Easy, Medium, Hard).';

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
  String get onlineCancelQueue => 'Leave queue';

  @override
  String get onlineCodeCopied => 'Room code copied';

  @override
  String get onlineCodeHint => 'Ask the host for the 6-letter code';

  @override
  String get onlineCodeLabel => 'Room code';

  @override
  String get onlineConnectionConnecting => 'Connecting to the game server…';

  @override
  String get onlineConnectionDisconnected =>
      'You are offline. Moves cannot be sent while you are disconnected — nothing is queued.';

  @override
  String get onlineConnectionReconnecting =>
      'Connection lost. Reconnecting… Moves cannot be sent until you are back.';

  @override
  String get onlineConnectionRetry => 'Retry';

  @override
  String get onlineCopyCode => 'Copy code';

  @override
  String get onlineCreateButton => 'Create room';

  @override
  String get onlineCreateTitle => 'Create a room';

  @override
  String get onlineErrorAlreadyInMatch => 'You are already in an active match.';

  @override
  String get onlineErrorAlreadyInMatchmaking =>
      'You are already in the matchmaking queue.';

  @override
  String get onlineErrorAlreadyInRoom => 'You are already in a room.';

  @override
  String get onlineErrorIllegalMove => 'That move is not legal right now.';

  @override
  String get onlineErrorInvalidState => 'That cannot be done right now.';

  @override
  String get onlineErrorMatchFinished => 'That match has finished.';

  @override
  String get onlineErrorMatchNotFound => 'That match no longer exists.';

  @override
  String get onlineErrorMatchmakingUnavailable =>
      'Matchmaking is temporarily unavailable.';

  @override
  String get onlineErrorNetwork =>
      'Could not reach the server. Check your connection.';

  @override
  String get onlineErrorNotRoomHost => 'Only the host can do that.';

  @override
  String get onlineErrorNotMatchPlayer => 'You are not a player in this match.';

  @override
  String get onlineErrorNotRoomMember => 'You are not a member of this room.';

  @override
  String get onlineErrorNotYourTurn => 'It is not your turn.';

  @override
  String get onlineErrorRoomFull => 'That room is full.';

  @override
  String get onlineErrorRoomNotFound => 'No open room has that code.';

  @override
  String get onlineErrorRoomStarted => 'That room has already started.';

  @override
  String get onlineErrorStaleState =>
      'Your view of the match is out of date. Reconnecting…';

  @override
  String get onlineErrorTimeout => 'The request timed out.';

  @override
  String get onlineErrorUnexpected => 'Something went wrong.';

  @override
  String get onlineGameForfeitConfirm => 'Leave and forfeit';

  @override
  String get onlineGameForfeitMessage =>
      'Leaving now forfeits the match for you. The other players keep playing.';

  @override
  String get onlineGameForfeitTitle => 'Leave match?';

  @override
  String get onlineGameLeave => 'Leave match';

  @override
  String get onlineGameLoadFailed => 'Could not load the match. Try again.';

  @override
  String get onlineGameLoading => 'Loading match…';

  @override
  String onlineGameMissedTurns(int count) {
    return 'Missed turns: $count of 3 — if your turn runs out, the server plays your first legal move.';
  }

  @override
  String onlineGamePlayerDisconnected(int seconds) {
    return '${seconds}s left to reconnect';
  }

  @override
  String get onlineGamePlayerForfeited => 'Forfeited';

  @override
  String get onlineGameTitle => 'Online match';

  @override
  String onlineGameTurnTimeLeft(int seconds) {
    return '${seconds}s left';
  }

  @override
  String onlineGameWaitingFor(String name) {
    return 'Waiting for $name';
  }

  @override
  String get onlineGameYourTurn => 'Your turn';

  @override
  String get onlineGoToLobby => 'Go to lobby';

  @override
  String get onlineHost => 'Host';

  @override
  String get onlineJoinButton => 'Join room';

  @override
  String get onlineJoinQueue => 'Find a match';

  @override
  String get onlineJoinTitle => 'Join a room';

  @override
  String get onlineLeaveRoom => 'Leave room';

  @override
  String get onlineLobbyTitle => 'Online lobby';

  @override
  String onlineMatched(String code) {
    return 'Match found! Room code: $code';
  }

  @override
  String get onlineMatchmakingTitle => 'Matchmaking';

  @override
  String get onlineMatchStarted => 'Match started!';

  @override
  String get onlineMaxPlayers => 'Players';

  @override
  String get onlineMembers => 'Players in room';

  @override
  String get onlineNeedPlayers => 'At least 2 players are needed to start.';

  @override
  String get onlineNeedReady =>
      'Every player must be ready before the match starts.';

  @override
  String get onlineNotHost => 'Only the host can start the match.';

  @override
  String onlinePlayerDisconnected(String name, int seconds) {
    return '$name disconnected — ${seconds}s left to reconnect';
  }

  @override
  String onlinePlayerForfeited(String name) {
    return '$name forfeited the match';
  }

  @override
  String onlinePlayerReconnected(String name) {
    return '$name reconnected';
  }

  @override
  String onlineQueuePosition(int position) {
    return 'You are #$position in the queue.';
  }

  @override
  String onlineQueueSize(int count) {
    return '$count players waiting';
  }

  @override
  String get onlineReady => 'Ready';

  @override
  String onlineRulesetSummary(String version) {
    return 'Ruleset $version — standard DiceUp rules, 4 players max.';
  }

  @override
  String get onlineShareCode => 'Share code';

  @override
  String onlineShareMessage(String code) {
    return 'Join my DiceUp room! Code: $code';
  }

  @override
  String get onlineStartMatch => 'Start match';

  @override
  String get onlineYou => 'You';

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
  String get registerButton => 'Create account';

  @override
  String get registerHaveAccount => 'Already have an account? Log in';

  @override
  String get registerTitle => 'Create account';

  @override
  String get resetButton => 'Reset password';

  @override
  String get resetMessage =>
      'Enter the code from the reset email and choose a new password.';

  @override
  String get resetTitle => 'Enter reset code';

  @override
  String get resultsEmpty => 'No match result to show.';

  @override
  String get resultsPlayAgain => 'Play Again';

  @override
  String resultsPlayerHome(int home) {
    return 'Home $home/4';
  }

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
  String get verifyButton => 'Verify';

  @override
  String verifyMessage(String email) {
    return 'We sent a verification code to $email. Enter it below.';
  }

  @override
  String get verifyResend => 'Resend code';

  @override
  String get verifyTitle => 'Verify your email';

  @override
  String get winnerSuffix => ' — winner';
}
