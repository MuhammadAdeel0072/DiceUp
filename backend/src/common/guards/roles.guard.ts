import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY } from '../decorators/roles.decorator';
import { ErrorCode } from '../errors/error-codes';
import type { RequestUser } from './request-user';

/**
 * RolesGuard (plan §7.1 role foundations). Checks the JWT's `role`
 * claim against @Roles() metadata. Routes without @Roles() metadata
 * allow any authenticated user — the guard is the foundation Phase 7
 * admin roles plug into; in Phase 4 every JWT carries role 'player'
 * and there is no roles table. Never trusts a client-supplied role:
 * the claim comes from the verified token via JwtStrategy.
 */
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<string[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!required || required.length === 0) return true;
    const req = context.switchToHttp().getRequest<{ user?: RequestUser }>();
    const user = req.user;
    if (!user) return true; // No principal: JwtAuthGuard decides.
    if (!required.includes(user.role)) {
      throw new ForbiddenException({
        code: ErrorCode.Forbidden,
        message: 'You do not have permission to perform this action.',
      });
    }
    return true;
  }
}
