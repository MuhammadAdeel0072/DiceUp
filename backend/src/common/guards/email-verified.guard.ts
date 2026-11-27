import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { ErrorCode } from '../errors/error-codes';
import type { RequestUser } from './request-user';

/**
 * EmailVerifiedGuard (FR-03, NFR-17). Deny-by-default: unverified
 * users can log in and resend verification (they need a session for
 * that), but are refused every online-guarded route with 403
 * EMAIL_NOT_VERIFIED. Applied at the controller level (UsersController)
 * — auth endpoints are intentionally NOT guarded by it.
 */
@Injectable()
export class EmailVerifiedGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest<{ user?: RequestUser }>();
    const user = req.user;
    if (!user) return true; // No principal: JwtAuthGuard decides.
    if (!user.emailVerified) {
      throw new ForbiddenException({
        code: ErrorCode.EmailNotVerified,
        message: 'Verify your email to use online features.',
      });
    }
    return true;
  }
}
