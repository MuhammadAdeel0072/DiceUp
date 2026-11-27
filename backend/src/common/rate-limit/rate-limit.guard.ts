import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Request } from 'express';
import { REDIS_KEYS } from '../../redis/redis-keys';
import { RATE_LIMITS } from '../../auth/auth.constants';
import type { RequestUser } from '../guards/request-user';
import { RATE_LIMIT_KEY } from './rate-limit.decorator';
import type { RateLimitOptions } from './rate-limit.decorator';
import { hashRateLimitEmail, RateLimitService } from './rate-limit.service';

/**
 * RateLimitGuard (plan §6.5, NFR-20). Registered globally (APP_GUARD,
 * last in the guard chain — after JwtAuthGuard has attached the user).
 *
 * - Endpoints with @RateLimit() metadata: fail-closed per-attempt
 *   limit (register/forgot/reset/verify/refresh). Keyed by IP, or by
 *   the (hashed) request email for forgot-password.
 * - Authenticated requests without endpoint metadata: the generic
 *   100 req/min per-user limit (SDD §13.4), fail-open when Redis is
 *   down so PostgreSQL-backed reads keep working (see RateLimitService).
 * - Public endpoints without metadata (health) and unauthenticated
 *   requests: no limit applied.
 */
@Injectable()
export class RateLimitGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly limits: RateLimitService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context
      .switchToHttp()
      .getRequest<Request & { user?: RequestUser }>();
    const options = this.reflector.getAllAndOverride<RateLimitOptions>(
      RATE_LIMIT_KEY,
      [context.getHandler(), context.getClass()],
    );
    if (options) {
      const key = this.buildKey(options, req);
      if (key) {
        await this.limits.check(key, options.limit, options.windowSeconds, {
          failClosed: true,
        });
      }
      return true;
    }
    if (req.user) {
      const key = REDIS_KEYS.rateLimit(
        `user:${req.user.id}`,
        RATE_LIMITS.authenticated.windowLabel,
      );
      await this.limits.check(
        key,
        RATE_LIMITS.authenticated.limit,
        RATE_LIMITS.authenticated.windowSeconds,
        { failClosed: false },
      );
    }
    return true;
  }

  private buildKey(
    options: RateLimitOptions,
    req: Request & { user?: RequestUser },
  ): string | null {
    const ip = req.ip ?? 'unknown';
    if (options.keyBy === 'ip') {
      return REDIS_KEYS.rateLimit(`ip:${ip}`, options.windowLabel);
    }
    // keyBy 'email': hash the address — never a plaintext email in a key.
    const email = (req.body as { email?: unknown } | undefined)?.email;
    if (typeof email !== 'string' || email.length === 0) return null;
    return REDIS_KEYS.rateLimit(
      `forgot:${hashRateLimitEmail(email)}`,
      options.windowLabel,
    );
  }
}
