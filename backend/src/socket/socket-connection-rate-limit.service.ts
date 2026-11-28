import { Injectable, Logger } from '@nestjs/common';
import { REDIS_KEYS } from '../redis/redis-keys';
import { RedisService } from '../redis/redis.service';
import {
  SOCKET_CONNECTION_WINDOW_SECONDS,
  SOCKET_CONNECTIONS_PER_MINUTE_PER_IP,
  SOCKET_CONNECTIONS_PER_MINUTE_PER_USER,
} from './socket.constants';

/**
 * SocketConnectionRateLimitService (Stage 5, L-02).
 *
 * A handshake costs an RS256 verify + DB lookups, and reconnecting
 * resets the per-socket event budget — so connections themselves
 * are bounded: per IP (checked before auth, so it bounds
 * unauthenticated handshake floods) and per user (checked after
 * auth, so one account cannot open unbounded connections). The
 * limits are generous on purpose (120/min/IP, 20/min/user): a
 * legitimate client connects once per session and reconnects
 * occasionally. Redis counters are the primary store; when Redis
 * is down an in-process bucket with the same budget applies, so
 * the control survives an outage instead of failing open (a flood
 * during an outage) or closed (no client could connect at all).
 * Buckets expire after the window; stale entries are purged
 * opportunistically.
 */
@Injectable()
export class SocketConnectionRateLimitService {
  private readonly logger = new Logger(SocketConnectionRateLimitService.name);

  /** In-process fallback buckets (Redis-down only): key → window. */
  private readonly localBuckets = new Map<
    string,
    { windowStart: number; count: number }
  >();

  constructor(private readonly redis: RedisService) {}

  /** True when this IP may open another connection this minute. */
  async checkIp(ip: string): Promise<{ allowed: boolean }> {
    return this.check(
      REDIS_KEYS.rateLimit(`socket-conn-ip:${ip}`, '1m'),
      `ip:${ip}`,
      SOCKET_CONNECTIONS_PER_MINUTE_PER_IP,
    );
  }

  /** True when this user may open another connection this minute. */
  async checkUser(userId: string): Promise<{ allowed: boolean }> {
    return this.check(
      REDIS_KEYS.rateLimit(`socket-conn-user:${userId}`, '1m'),
      `user:${userId}`,
      SOCKET_CONNECTIONS_PER_MINUTE_PER_USER,
    );
  }

  private async check(
    redisKey: string,
    localKey: string,
    limit: number,
  ): Promise<{ allowed: boolean }> {
    let count: number;
    try {
      count = await this.redis.incrWithExpiry(
        redisKey,
        SOCKET_CONNECTION_WINDOW_SECONDS,
      );
    } catch (err) {
      this.logger.warn(
        `Socket connection rate limit unavailable (Redis) — using the local bucket: ${(err as Error).message}`,
      );
      return { allowed: this.checkLocal(localKey, limit) };
    }
    return { allowed: count <= limit };
  }

  /** In-process per-minute window for one key. */
  private checkLocal(key: string, limit: number): boolean {
    const now = Date.now();
    if (this.localBuckets.size > 5000) {
      for (const [id, bucket] of this.localBuckets) {
        if (
          now - bucket.windowStart >=
          SOCKET_CONNECTION_WINDOW_SECONDS * 1000
        ) {
          this.localBuckets.delete(id);
        }
      }
    }
    const bucket = this.localBuckets.get(key);
    if (
      !bucket ||
      now - bucket.windowStart >= SOCKET_CONNECTION_WINDOW_SECONDS * 1000
    ) {
      this.localBuckets.set(key, { windowStart: now, count: 1 });
      return true;
    }
    bucket.count += 1;
    return bucket.count <= limit;
  }
}
