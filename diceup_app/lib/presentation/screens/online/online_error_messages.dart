import 'package:diceup/l10n/app_localizations.dart';

/// Maps room / matchmaking error codes to localised UI copy
/// (Phase 5, Stage 3).
///
/// The backend envelope `error.code` is the contract — screens never
/// render the raw code or the backend's English message.
///
/// Stage 7 adds the gameplay rejection codes (`action:rejected`):
/// `NOT_YOUR_TURN`, `ILLEGAL_MOVE`, `MATCH_FINISHED`,
/// `NOT_MATCH_PLAYER`, `MATCH_NOT_FOUND`, `STALE_STATE`.
String? onlineErrorMessage(AppLocalizations l10n, String? errorCode) {
  return switch (errorCode) {
    null => null,
    'ROOM_NOT_FOUND' => l10n.onlineErrorRoomNotFound,
    'ROOM_FULL' => l10n.onlineErrorRoomFull,
    'ROOM_STARTED' => l10n.onlineErrorRoomStarted,
    'NOT_ROOM_MEMBER' => l10n.onlineErrorNotRoomMember,
    'NOT_ROOM_HOST' => l10n.onlineErrorNotRoomHost,
    'ALREADY_IN_ROOM' => l10n.onlineErrorAlreadyInRoom,
    'ALREADY_IN_MATCH' => l10n.onlineErrorAlreadyInMatch,
    'ALREADY_IN_MATCHMAKING' => l10n.onlineErrorAlreadyInMatchmaking,
    'MATCHMAKING_UNAVAILABLE' => l10n.onlineErrorMatchmakingUnavailable,
    'INVALID_STATE' => l10n.onlineErrorInvalidState,
    'NOT_YOUR_TURN' => l10n.onlineErrorNotYourTurn,
    'ILLEGAL_MOVE' => l10n.onlineErrorIllegalMove,
    'MATCH_FINISHED' => l10n.onlineErrorMatchFinished,
    'NOT_MATCH_PLAYER' => l10n.onlineErrorNotMatchPlayer,
    'MATCH_NOT_FOUND' => l10n.onlineErrorMatchNotFound,
    'STALE_STATE' => l10n.onlineErrorStaleState,
    'UNAUTHORIZED' => l10n.authErrorSessionExpired,
    'NETWORK_ERROR' => l10n.onlineErrorNetwork,
    'TIMEOUT' => l10n.onlineErrorTimeout,
    _ => l10n.onlineErrorUnexpected,
  };
}
