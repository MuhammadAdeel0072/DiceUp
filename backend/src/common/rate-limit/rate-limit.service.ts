import { createHash } from 'node:crypto';
import {
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { RedisService } from '../../redis/redis.service';
import { RateLimitedException } from '../errors/rate-limited.exception';

/**
 * RateLimitService (plan §6.5, NFR-20).
 * Thin wrapper over RedisService.incrWithExpiry (atomic INCR + EXPIRE
 * on first use). On exceeding the limit it throws RateLimitedException,
 * which the exception filter turns into a 429 with a Retry-After
 * header (remaining window TTL when Redis can report it).
 *
 * Failure policy: `failClosed: true` (auth endpoints — register,
 * forgot/reset/verify/refresh) throws 503 when Redis is unavailable,
 * because running those endpoints unthrottled would silently drop a
 * security control (plan §5.2). `failClosed: false` (the generic
 * authenticated 100/min limit) fails OPEN with a warning so
 * PostgreSQL-backed reads keep working when Redis is down — that is
 * the plan's "keeps serving reads" rule applied to the read path.
 */
@Injectable()
export class RateLimitService {
  private readonly logger = new Logger(RateLimitService.name);

  constructor(private readonly redis: RedisService) {}

  async check(
    key: string,
    limit: number,
    windowSeconds: number,
    opts: { failClosed: boolean },
  ): Promise<void> {
    let count: number;
    try {
      count = await this.redis.incrWithExpiry(key, windowSeconds);
    } catch (err) {
      if (opts.failClosed) {
        this.logger.error(
          `Rate limit unavailable (Redis): ${(err as Error).message}`,
        );
        throw new ServiceUnavailableException(
          'This service is temporarily unavailable. Try again later.',
        );
      }
      this.logger.warn(
        `Rate limit unavailable (Redis) — allowing request: ${(err as Error).message}`,
      );
      return;
    }
    if (count > limit) {
      let retryAfter = windowSeconds;
      try {
        const ttl = await this.redis.ttl(key);
        if (ttl > 0) retryAfter = ttl;
      } catch {
        // Keep the window as the Retry-After fallback.
      }
      throw new RateLimitedException(retryAfter);
    }
  }
}

/** SHA-256 of a lower-cased email, for rate-limit keys (never plaintext). */
export function hashRateLimitEmail(email: string): string {
  return createHash('sha256')
    .update(email.trim().toLowerCase(), 'utf8')
    .digest('hex');
}
