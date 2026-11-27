import { createHash } from 'node:crypto';
import {
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { REDIS_KEYS } from '../redis/redis-keys';
import { RedisService } from '../redis/redis.service';
import {
  LOGIN_MAX_FAILURES,
  LOGIN_THROTTLE_WINDOW_SECONDS,
} from './auth.constants';
import { RateLimitedException } from '../common/errors/rate-limited.exception';

/**
 * LoginThrottleService (NFR-16, plan §6.5/§7.1).
 * After 5 consecutive failed logins in 15 min — keyed by BOTH the
 * account identifier and the IP — further attempts return 429, even
 * with the correct password. Counters reset on success. The 429
 * message is generic so it cannot be used to enumerate accounts.
 *
 * Redis failure fails CLOSED (503 SERVICE_UNAVAILABLE): the throttle
 * is a security control, and running login unthrottled would silently
 * drop it (plan §5.2). Account keys are SHA-256 hashes of the
 * lower-cased identifier — the raw email/username never appears in a
 * Redis key or a log line.
 */
@Injectable()
export class LoginThrottleService {
  private readonly logger = new Logger(LoginThrottleService.name);

  constructor(private readonly redis: RedisService) {}

  /** Redis key for one account identifier (hashed, never plaintext). */
  static accountKey(identifier: string): string {
    const digest = createHash('sha256')
      .update(identifier.trim().toLowerCase(), 'utf8')
      .digest('hex');
    return REDIS_KEYS.loginThrottle(`account:${digest}`);
  }

  /** Redis key for one IP address. */
  static ipKey(ip: string): string {
    return REDIS_KEYS.loginThrottle(`ip:${ip}`);
  }

  /** Throws 429 when either the account or the IP counter is exhausted. */
  async assertNotThrottled(identifier: string, ip: string): Promise<void> {
    let accountCount: string | null;
    let ipCount: string | null;
    try {
      [accountCount, ipCount] = await Promise.all([
        this.redis.get(LoginThrottleService.accountKey(identifier)),
        this.redis.get(LoginThrottleService.ipKey(ip)),
      ]);
    } catch (err) {
      this.logger.error(
        `Login throttle unavailable (Redis): ${(err as Error).message}`,
      );
      throw new ServiceUnavailableException(
        'Login is temporarily unavailable. Try again later.',
      );
    }
    if (
      Number(accountCount ?? 0) >= LOGIN_MAX_FAILURES ||
      Number(ipCount ?? 0) >= LOGIN_MAX_FAILURES
    ) {
      throw new RateLimitedException(LOGIN_THROTTLE_WINDOW_SECONDS);
    }
  }

  /** Records one failed login against both the account and the IP. */
  async recordFailure(identifier: string, ip: string): Promise<void> {
    try {
      await Promise.all([
        this.redis.incrWithExpiry(
          LoginThrottleService.accountKey(identifier),
          LOGIN_THROTTLE_WINDOW_SECONDS,
        ),
        this.redis.incrWithExpiry(
          LoginThrottleService.ipKey(ip),
          LOGIN_THROTTLE_WINDOW_SECONDS,
        ),
      ]);
    } catch (err) {
      this.logger.error(
        `Login throttle unavailable (Redis): ${(err as Error).message}`,
      );
      throw new ServiceUnavailableException(
        'Login is temporarily unavailable. Try again later.',
      );
    }
  }

  /**
   * Clears the ACCOUNT counter after a successful login. Best-effort: a
   * Redis failure here must not fail an otherwise valid login.
   *
   * NOTE (Stage 4, M-03): the IP counter is deliberately NOT cleared.
   * The IP key is shared by everyone behind one egress address (NAT,
   * office, campus); deleting it on any one user's success would hand
   * an attacker brute-forcing from that address a fresh budget every
   * time any legitimate user on the same IP logs in. The IP counter
   * instead expires naturally after its 15-minute TTL. The account
   * counter is per-user, so clearing it on that user's own success is
   * safe — it is the "counter resets on success" the plan requires.
   * (`_ip` is kept in the signature so call sites stay unchanged.)
   */
  async reset(identifier: string, _ip: string): Promise<void> {
    try {
      await this.redis.del(LoginThrottleService.accountKey(identifier));
    } catch (err) {
      this.logger.warn(
        `Failed to reset login throttle counter: ${(err as Error).message}`,
      );
    }
  }
}
