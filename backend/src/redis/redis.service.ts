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
 * Atomically pop the first N members of a sorted set (matchmaking
 * grouping, FR-45). Returns the popped members (in score order) when
 * at least N are present, otherwise an empty array — and nothing is
 * removed. The check-and-remove is one Lua script, so two concurrent
 * joiners can never both pop the same group (the TOCTOU guard for
 * grouping; the per-match Redis lock is not needed here because the
 * script itself is the atomic step).
 */
const POP_GROUP_SCRIPT = `
local members = redis.call('ZRANGE', KEYS[1], 0, ARGV[1] - 1)
if #members < tonumber(ARGV[1]) then
  return {}
end
redis.call('ZREM', KEYS[1], unpack(members))
return members
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

  // -- Sorted sets (matchmaking queue, FR-45) ---------------------------
  // One queue entry per player in `matchmaking:queue` (score = enqueue
  // time in ms). The queue is Redis-only by design (SDD §9.4) — a
  // queued player holds no PostgreSQL row, so a Redis loss only drops
  // waiting players (they re-join), never a match (CI-05).

  /** Add `member` with `score` only if absent; true when added. */
  async zaddNx(key: string, score: number, member: string): Promise<boolean> {
    const added = await this.client.zadd(key, 'NX', score, member);
    return added === 1;
  }

  /** Score of `member`, or null when absent. */
  async zscore(key: string, member: string): Promise<number | null> {
    const score = await this.client.zscore(key, member);
    return score === null ? null : Number(score);
  }

  /** 0-based rank of `member` (arrival order), or null when absent. */
  async zrank(key: string, member: string): Promise<number | null> {
    return this.client.zrank(key, member);
  }

  /** Number of members in the set. */
  async zcard(key: string): Promise<number> {
    return this.client.zcard(key);
  }

  /** Remove `member`; true when it was present. */
  async zrem(key: string, member: string): Promise<boolean> {
    const removed = await this.client.zrem(key, member);
    return removed === 1;
  }

  /**
   * Atomically pop the first `count` members (lowest scores) when at
   * least that many are present; otherwise returns [] and removes
   * nothing. Members come back in score (arrival) order.
   */
  async popGroup(key: string, count: number): Promise<string[]> {
    const result = await this.client.eval(
      POP_GROUP_SCRIPT,
      1,
      key,
      String(count),
    );
    return (result as unknown[]).map(String);
  }
}
