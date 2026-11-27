import { SetMetadata } from '@nestjs/common';

/** Per-endpoint rate-limit options (plan §6.5). */
export interface RateLimitOptions {
  limit: number;
  windowSeconds: number;
  /** Label used in the Redis key, e.g. '1h' / '1m'. */
  windowLabel: string;
  /** What the counter is keyed by: the client IP, or the request email. */
  keyBy: 'ip' | 'email';
}

export const RATE_LIMIT_KEY = 'rateLimit';

/**
 * Marks an endpoint with a fail-closed per-attempt rate limit
 * (register / forgot-password / reset / verify / refresh). Login uses
 * the failure-based NFR-16 throttle instead (LoginThrottleService)
 * and carries no decorator.
 */
export const RateLimit = (options: RateLimitOptions): MethodDecorator =>
  SetMetadata(RATE_LIMIT_KEY, options);
