import { Injectable, Logger, NestMiddleware } from '@nestjs/common';
import type { NextFunction, Request, Response } from 'express';
import { RATE_LIMITS } from '../../auth/auth.constants';
import { ErrorCode } from '../errors/error-codes';
import { REDIS_KEYS } from '../../redis/redis-keys';
import { RedisService } from '../../redis/redis.service';

/**
 * UnauthenticatedRateLimitMiddleware (Stage 5, L-01).
 *
 * A global per-IP flood bound on every `/v1` request except health.
 * It runs as Nest middleware — BEFORE the guard chain — because
 * JwtAuthGuard 401s before RateLimitGuard, so a flood against
 * protected routes otherwise hit RS256 verification unbounded.
 * Authenticated requests pass through it too (a fake Authorization
 * header must not buy an exemption); the per-user 100/min limit
 * and the per-endpoint limits remain the fine controls.
 *
 * Failure policy: fail OPEN when Redis is unavailable (reads keep
 * working; the auth endpoints' own fail-closed limits still apply
 * downstream). Over the limit: 429 with a Retry-After header and
 * the §6.3 envelope.
 */
@Injectable()
export class UnauthenticatedRateLimitMiddleware implements NestMiddleware {
  private readonly logger = new Logger(UnauthenticatedRateLimitMiddleware.name);

  constructor(private readonly redis: RedisService) {}

  async use(req: Request, res: Response, next: NextFunction): Promise<void> {
    const path = req.path ?? '';
    if (!path.startsWith('/v1/') || path.startsWith('/v1/health')) {
      next();
      return;
    }
    const ip = req.ip ?? 'unknown';
    const key = REDIS_KEYS.rateLimit(
      `ip:${ip}`,
      RATE_LIMITS.ipFlood.windowLabel,
    );
    let count: number;
    try {
      count = await this.redis.incrWithExpiry(
        key,
        RATE_LIMITS.ipFlood.windowSeconds,
      );
    } catch (err) {
      this.logger.warn(
        `IP flood limit unavailable (Redis) — allowing request: ${(err as Error).message}`,
      );
      next();
      return;
    }
    if (count > RATE_LIMITS.ipFlood.limit) {
      let retryAfter: number = RATE_LIMITS.ipFlood.windowSeconds;
      try {
        const ttl = await this.redis.ttl(key);
        if (ttl > 0) retryAfter = ttl;
      } catch {
        // Keep the window as the Retry-After fallback.
      }
      res.setHeader('Retry-After', String(retryAfter));
      res.status(429).json({
        success: false,
        error: {
          code: ErrorCode.RateLimited,
          message: 'Too many requests from this address. Slow down.',
        },
      });
      return;
    }
    next();
  }
}
