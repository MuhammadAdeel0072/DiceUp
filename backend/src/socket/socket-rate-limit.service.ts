import { Injectable, Logger } from '@nestjs/common';
import { RedisService } from '../redis/redis.service';
import { REDIS_KEYS } from '../redis/redis-keys';
import {
  SOCKET_EVENTS_PER_SECOND,
  SOCKET_EVENT_WINDOW_SECONDS,
} from './socket.constants';

/**
 * SocketRateLimitService (NFR-20, SDD §12.6) — the 20 events/s per
 * connection limiter. One Redis counter per socket id, via the same
 * atomic `incrWithExpiry` primitive the REST limiter uses (plan §5.2),
 * so the window cannot be extended by concurrent increments.
 *
 * Failure policy (Stage 5): Redis down falls back to an in-process
 * per-socket bucket with the same 20/s budget. Failing CLOSED here
 * would kill every in-progress match the moment Redis died (every
 * game event would 503); failing OPEN would silently drop the
 * control. The local bucket keeps the control alive on the node
 * holding the match, at the cost of a per-process view — a client
 * reconnecting to another node gets a fresh budget there, which
 * the connection limiter (L-02) bounds instead. Buckets are
 * keyed by socket id and expire after the window; stale entries
 * are purged opportunistically so a long-lived process cannot
 * accumulate them.
 */
@Injectable()
export class SocketRateLimitService {
  private readonly logger = new Logger(SocketRateLimitService.name);

  /** In-process fallback buckets (Redis-down only): socket id → window. */
  private readonly localBuckets = new Map<
    string,
    { windowStart: number; count: number }
  >();

  constructor(private readonly redis: RedisService) {}

  /** True when this event is within the per-connection budget. */
  async check(socketId: string): Promise<{ allowed: boolean }> {
    let count: number;
    try {
      count = await this.redis.incrWithExpiry(
        REDIS_KEYS.socketRateLimit(socketId),
        SOCKET_EVENT_WINDOW_SECONDS,
      );
    } catch (err) {
      this.logger.warn(
        `Socket rate limit unavailable (Redis) — using the local per-socket bucket: ${(err as Error).message}`,
      );
      return { allowed: this.checkLocal(socketId) };
    }
    return { allowed: count <= SOCKET_EVENTS_PER_SECOND };
  }

  /** In-process 20/s sliding window for one socket id. */
  private checkLocal(socketId: string): boolean {
    const now = Date.now();
    if (this.localBuckets.size > 5000) {
      for (const [id, bucket] of this.localBuckets) {
        if (now - bucket.windowStart >= SOCKET_EVENT_WINDOW_SECONDS * 1000) {
          this.localBuckets.delete(id);
        }
      }
    }
    const bucket = this.localBuckets.get(socketId);
    if (
      !bucket ||
      now - bucket.windowStart >= SOCKET_EVENT_WINDOW_SECONDS * 1000
    ) {
      this.localBuckets.set(socketId, { windowStart: now, count: 1 });
      return true;
    }
    bucket.count += 1;
    return bucket.count <= SOCKET_EVENTS_PER_SECOND;
  }
}
