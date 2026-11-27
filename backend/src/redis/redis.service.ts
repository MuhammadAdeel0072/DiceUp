import {
  Inject,
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import Redis from 'ioredis';
import { randomUUID } from 'node:crypto';

export const REDIS_CLIENT = 'REDIS_CLIENT';

/** Atomic INCR + EXPIRE-on-first-use (Lua, plan §5.2). */
const INCR_WITH_EXPIRY_SCRIPT = `
local count = redis.call('INCR', KEYS[1])
if count == 1 then
  redis.call('EXPIRE', KEYS[1], ARGV[1])
end
return count
`;

/** Release a lock only if the stored token matches (Lua, plan §5.2). */
const RELEASE_LOCK_SCRIPT = `
if redis.call('GET', KEYS[1]) == ARGV[1] then
  return redis.call('DEL', KEYS[1])
else
  return 0
end
`;

/**
 * RedisService — the ONLY Redis API the app uses (plan §5.2). Nothing
 * else may import the raw client. ioredis [P4 choice]; SDD names no
 * client library, and ioredis is the Socket.IO Redis adapter's
 * conventional pairing (§9.2).
 *
 * Failure policy (SDD §9.4, plan §5.2): if Redis is unavailable the
 * backend refuses new online sessions with a clear error (auth writes
 * fail closed — the throttle cannot be enforced, so failing open would
 * silently drop a security control) but keeps serving PostgreSQL-backed
 * reads. In Phase 4 that means health/readiness reports Redis down;
 * no business truth is ever stored only in Redis (CI-05).
 * The client is created lazily and a failed connect at boot is logged,
 * not fatal — the app must still boot so /health can answer.
 */
@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);

  constructor(@Inject(REDIS_CLIENT) private readonly client: Redis) {
    this.client.on('error', (err) => {
      this.logger.warn(`Redis client error: ${err.message}`);
    });
  }

  async onModuleInit(): Promise<void> {
    try {
      await this.client.ping();
    } catch (err) {
      this.logger.warn(
        `Redis unavailable at startup (health will report redis: down): ${(err as Error).message}`,
      );
    }
  }

  async onModuleDestroy(): Promise<void> {
    try {
      this.client.disconnect();
    } catch {
      // Already disconnected — shutdown must not throw.
    }
  }

  /** True when Redis answers PING; false (never throws) otherwise. */
  async ping(): Promise<boolean> {
    try {
      const reply = await this.client.ping();
      return reply === 'PONG';
    } catch {
      return false;
    }
  }

  async get(key: string): Promise<string | null> {
    return this.client.get(key);
  }

  async set(key: string, value: string, ttlSeconds: number): Promise<void> {
    await this.client.set(key, value, 'EX', ttlSeconds);
  }

  async del(key: string): Promise<void> {
    await this.client.del(key);
  }

  /**
   * Atomic counter with TTL (rate limits, NFR-16/20). Returns the new
   * count. The TTL is set only when the key is created, so concurrent
   * increments cannot extend the window (race-tested in unit tests).
   */
  async incrWithExpiry(key: string, windowSeconds: number): Promise<number> {
    const result = await this.client.eval(
      INCR_WITH_EXPIRY_SCRIPT,
      1,
      key,
      String(windowSeconds),
    );
    return Number(result);
  }

  /**
   * Remaining TTL of a key in seconds (-2: no such key, -1: no expiry).
   * Used for Retry-After values on rate-limit responses (plan §6.5).
   */
  async ttl(key: string): Promise<number> {
    return this.client.ttl(key);
  }

  /**
   * Per-match lock helper (SDD §9.4 `match:lock:{matchId}`, TTL 10 s).
   * Returns a token on success, null when the lock is held. No caller
   * exists in Phase 4 (Phase 5, FR-50/53).
   */
  async acquireLock(key: string, ttlSeconds = 10): Promise<string | null> {
    const token = randomUUID();
    const result = await this.client.set(key, token, 'EX', ttlSeconds, 'NX');
    return result === 'OK' ? token : null;
  }

  /** Releases a lock only if `token` matches; returns true if released. */
  async releaseLock(key: string, token: string): Promise<boolean> {
    const result = await this.client.eval(RELEASE_LOCK_SCRIPT, 1, key, token);
    return Number(result) === 1;
  }
}
