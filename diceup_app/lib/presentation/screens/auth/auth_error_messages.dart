import 'package:diceup/l10n/app_localizations.dart';

/// Maps auth error / info codes to localised UI copy (Phase 5,
/// Stage 2).
///
/// The backend envelope `error.code` is the contract — screens
/// never render the raw code or the backend's English message.
/// Per-field messages from a `VALIDATION_FAILED` response are the
/// exception: they arrive as server data (already user-facing) and
/// screens render them under the field they belong to, via
/// [AuthState.fieldErrors].

/// Localised banner copy for an auth [errorCode], or null when
/// there is no error to show.
///
/// [tokenContext] is true on the verification / reset screens: a
/// bare 401 there means the code is unknown, not that the login
/// failed. Everywhere else a 401 means the session is gone.
String? authErrorMessage(
  AppLocalizations l10n,
  String? errorCode, {
  bool tokenContext = false,
}) {
  return switch (errorCode) {
    null => null,
    'INVALID_CREDENTIALS' => l10n.authErrorInvalidCredentials,
    'EMAIL_TAKEN' => l10n.authErrorEmailTaken,
    'USERNAME_TAKEN' => l10n.authErrorUsernameTaken,
    'TOKEN_EXPIRED' => l10n.authErrorTokenExpired,
    'TOKEN_ALREADY_USED' => l10n.authErrorTokenUsed,
    'UNAUTHORIZED' =>
      tokenContext ? l10n.authErrorTokenInvalid : l10n.authErrorSessionExpired,
    'EMAIL_NOT_VERIFIED' => l10n.authErrorEmailNotVerified,
    'ACCOUNT_SUSPENDED' => l10n.authErrorAccountSuspended,
    'FORBIDDEN' => l10n.authErrorForbidden,
    'VALIDATION_FAILED' => l10n.authErrorValidation,
    'RATE_LIMITED' => l10n.authErrorRateLimited,
    'NETWORK_ERROR' => l10n.authErrorNetwork,
    'TIMEOUT' => l10n.authErrorTimeout,
    _ => l10n.authErrorUnexpected,
  };
}

/// Localised banner copy for a non-error [AuthState.infoCode], or
/// null when there is nothing to report.
String? authInfoMessage(AppLocalizations l10n, String? infoCode) {
  return switch (infoCode) {
    null => null,
    'registerDone' => l10n.authInfoRegisterDone,
    'verifyDone' => l10n.authInfoVerifyDone,
    'verifyResent' => l10n.authInfoVerifyResent,
    'forgotSent' => l10n.authInfoForgotSent,
    'resetDone' => l10n.authInfoResetDone,
    'passwordChanged' => l10n.authInfoPasswordChanged,
    _ => null,
  };
}
