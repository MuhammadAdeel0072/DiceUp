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
