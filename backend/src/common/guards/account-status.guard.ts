import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { ErrorCode } from '../errors/error-codes';
import type { RequestUser } from './request-user';

/**
 * AccountStatusGuard (BR-19, FR-75/76 enforcement only). Single choke
 * point, after JwtAuthGuard: suspended/blocked accounts cannot use any
 * online action, and accounts with a pending deletion request are
 * refused too. Runs on every authenticated request (global APP_GUARD).
 * The admin endpoints that *set* the status are Phase 7 — this guard
 * only enforces the status.
 */
@Injectable()
export class AccountStatusGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest<{ user?: RequestUser }>();
    const user = req.user;
    if (!user) return true; // No principal: JwtAuthGuard decides.
    if (user.deletionRequestedAt) {
      throw new ForbiddenException({
        code: ErrorCode.Forbidden,
        message: 'This account has a pending deletion request.',
      });
    }
    if (user.status === 'suspended' || user.status === 'blocked') {
      throw new ForbiddenException({
        code: ErrorCode.AccountSuspended,
        message: 'This account is suspended.',
      });
    }
    return true;
  }
}
