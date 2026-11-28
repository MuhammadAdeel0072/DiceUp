/**
 * Error codes for the §6.3 error envelope (plan §6.3 / SDD §12.5).
 * Clients switch on `code`, never on message text.
 */
export enum ErrorCode {
  ValidationFailed = 'VALIDATION_FAILED',
  Unauthorized = 'UNAUTHORIZED',
  InvalidCredentials = 'INVALID_CREDENTIALS',
  Forbidden = 'FORBIDDEN',
  AccountSuspended = 'ACCOUNT_SUSPENDED',
  EmailNotVerified = 'EMAIL_NOT_VERIFIED',
  NotFound = 'NOT_FOUND',
  UsernameTaken = 'USERNAME_TAKEN',
  EmailTaken = 'EMAIL_TAKEN',
  TokenAlreadyUsed = 'TOKEN_ALREADY_USED',
  TokenExpired = 'TOKEN_EXPIRED',
  InvalidState = 'INVALID_STATE',
  // Phase 5, Stage 3 — rooms (FR-43/44/46/47/59).
  RoomNotFound = 'ROOM_NOT_FOUND',
  RoomFull = 'ROOM_FULL',
  RoomStarted = 'ROOM_STARTED',
  NotRoomMember = 'NOT_ROOM_MEMBER',
  NotRoomHost = 'NOT_ROOM_HOST',
  AlreadyInRoom = 'ALREADY_IN_ROOM',
  AlreadyInMatch = 'ALREADY_IN_MATCH',
  // Phase 5, Stage 3 — matchmaking (FR-45).
  AlreadyInMatchmaking = 'ALREADY_IN_MATCHMAKING',
  NotInMatchmaking = 'NOT_IN_MATCHMAKING',
  MatchmakingUnavailable = 'MATCHMAKING_UNAVAILABLE',
  // Phase 5, Stage 5 — gameplay (FR-49–FR-53, FR-57/58).
  MatchNotFound = 'MATCH_NOT_FOUND',
  NotMatchPlayer = 'NOT_MATCH_PLAYER',
  NotYourTurn = 'NOT_YOUR_TURN',
  IllegalMove = 'ILLEGAL_MOVE',
  MatchFinished = 'MATCH_FINISHED',
  StaleState = 'STALE_STATE',
  MatchUnavailable = 'MATCH_UNAVAILABLE',
  RateLimited = 'RATE_LIMITED',
  PayloadTooLarge = 'PAYLOAD_TOO_LARGE',
  ServiceUnavailable = 'SERVICE_UNAVAILABLE',
  InternalError = 'INTERNAL_ERROR',
}

export interface ErrorBody {
  code: string;
  message: string;
  details?: Record<string, string[]>;
  /** Extra structured detail (e.g. readiness per-dependency status). */
  data?: unknown;
  correlationId?: string;
}

export interface SuccessEnvelope<T> {
  success: true;
  data: T;
}

export interface ErrorEnvelope {
  success: false;
  error: ErrorBody;
}

export type Envelope<T> = SuccessEnvelope<T> | ErrorEnvelope;
