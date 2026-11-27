import { HttpException, HttpStatus } from '@nestjs/common';
import { ErrorCode } from './error-codes';

/**
 * 429 with a Retry-After value. HttpExceptionFilter sets the
 * `Retry-After` response header from `retryAfterSeconds` (plan §6.5:
 * all 429s carry Retry-After). The body keeps the standard envelope
 * code RATE_LIMITED; the message never reveals whether an account
 * exists (NFR-16).
 */
export class RateLimitedException extends HttpException {
  readonly retryAfterSeconds: number;

  constructor(retryAfterSeconds: number, message?: string) {
    super(
      {
        code: ErrorCode.RateLimited,
        message: message ?? 'Too many requests. Try again later.',
      },
      HttpStatus.TOO_MANY_REQUESTS,
    );
    this.retryAfterSeconds = Math.max(1, Math.ceil(retryAfterSeconds));
  }
}
