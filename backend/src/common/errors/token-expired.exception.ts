import { HttpException, HttpStatus } from '@nestjs/common';
import { ErrorCode } from './error-codes';

/** 410 — an email token that existed but has expired (plan §6.3, D-P4-10). */
export class TokenExpiredException extends HttpException {
  constructor(message = 'This token has expired.') {
    super({ code: ErrorCode.TokenExpired, message }, HttpStatus.GONE);
  }
}
