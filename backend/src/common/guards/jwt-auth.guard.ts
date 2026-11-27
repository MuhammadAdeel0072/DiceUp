import { ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthGuard } from '@nestjs/passport';
import { Observable, lastValueFrom } from 'rxjs';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';

/**
 * Global JWT auth guard (NFR-17, plan §7.1). Registered as APP_GUARD:
 * every route requires a valid access token unless it is explicitly
 * @Public(). Token verification + the load-bearing `sid` session check
 * happen in JwtStrategy.validate() — this guard only adds the
 * public-route allow-list on top of passport-jwt. A revoked or
 * expired session fails here on EVERY authenticated request, which is
 * what makes logout/revocation real despite the 15-min JWT lifetime.
 * This check must not be optimised away (plan §12 item 7).
 */
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {
  constructor(private readonly reflector: Reflector) {
    super();
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;
    const result = super.canActivate(context);
    if (result instanceof Observable) return lastValueFrom(result);
    if (result instanceof Promise) return result;
    return result;
  }
}
