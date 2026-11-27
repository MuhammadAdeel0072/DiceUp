import { Injectable, Logger, OnApplicationShutdown } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';

/**
 * SocketRedisClients — the two dedicated ioredis clients the
 * Socket.IO Redis adapter needs (plan §9.2/§9.4, NFR-24): one
 * publisher, one subscriber (a duplicate of the publisher). They are
 * separate from the RedisService client on purpose: the adapter owns
 * their lifecycle, and a pub/sub client must never be used for
 * regular commands.
 *
 * Failure behaviour matches RedisModule except for the retry limit:
 * a dead Redis at boot does not crash the process — the adapter
 * clients queue their commands until Redis answers (see the
 * `maxRetriesPerRequest: null` note in the constructor; Stage 4 H-01),
 * so the app still boots, /health still answers, and readiness
 * reports redis down. Commands buffer in ioredis until Redis is
 * reachable, so the adapter starts working when Redis does.
 *
 * Shutdown ordering (found by the Stage 2c e2e tests — a real defect,
 * not a guess): Nest calls `onModuleDestroy` BEFORE it closes the
 * Socket.IO server, so disconnecting here in `onModuleDestroy`
 * killed the subscriber while the Redis adapter's `close()` was
 * still issuing its `unsubscribe` commands — all four rejected with
 * "Connection is closed" as unhandled rejections and failed every
 * e2e suite. The disconnect therefore lives in
 * `onApplicationShutdown`, which Nest calls AFTER `dispose()` has
 * closed the socket server: the adapter's unsubscribes are issued
 * first, and this hook awaits an explicit `unsubscribe()` (same
 * connection, in-order — awaiting its ack proves the adapter's
 * earlier unsubscribes also completed) before disconnecting.
 * `quit()` is used for the publisher (drains pending publishes);
 * the subscriber is unsubscribed first because `quit()` is a no-op
 * while a client is in subscriber mode.
 */
@Injectable()
export class SocketRedisClients implements OnApplicationShutdown {
  private readonly logger = new Logger(SocketRedisClients.name);

  readonly pub: Redis;
  readonly sub: Redis;

  constructor(config: ConfigService) {
    // NOTE (Stage 3): `app.redisUrl`, not top-level `REDIS_URL` — same
    // validated-env freeze as DatabaseModule (see its comment).
    const url = config.getOrThrow<string>('app.redisUrl');
    // NOTE (Stage 4, H-01): `maxRetriesPerRequest: null` here is
    // load-bearing and must NOT be "aligned" with RedisModule's 3.
    // The Socket.IO Redis adapter issues SUBSCRIBE/PUBLISH commands on
    // these clients internally and does not attach a rejection handler
    // to them. With a numeric limit, a dead Redis at boot (or a Redis
    // outage at runtime) makes ioredis flush the queued SUBSCRIBE with
    // MaxRetriesPerRequestError as an UNHANDLED rejection and the
    // Node process dies in <1 s — the app can never boot degraded, so
    // /health and readiness can never report redis down (proven by a
    // dead-Redis boot probe + an isolated adapter repro, Stage 4).
    // `null` means "queue until Redis answers": the adapter's commands
    // wait instead of rejecting, the server boots, REST keeps working,
    // and the adapter recovers when Redis returns. Trade-off: while
    // Redis is down, adapter publishes queue in memory (unbounded if
    // broadcasts pile up); Phase 4 has no broadcast traffic, so this
    // is a bounded queue in practice — revisit if Phase 5 adds heavy
    // broadcast volume during an outage.
    const options = {
      maxRetriesPerRequest: null,
      retryStrategy: (times: number) => Math.min(times * 50, 2000),
    };
    this.pub = new Redis(url, options);
    this.sub = this.pub.duplicate();
    for (const client of [this.pub, this.sub]) {
      client.on('error', (err) => {
        this.logger.warn(`Socket Redis client error: ${err.message}`);
      });
    }
  }

  async onApplicationShutdown(): Promise<void> {
    // NOTE (Stage 4, H-01 follow-up): every await here is raced
    // against a short timeout. With `maxRetriesPerRequest: null` (see
    // the constructor) a command issued while Redis is down queues
    // forever instead of rejecting — awaiting `unsubscribe()` /
    // `quit()` unconditionally would hang shutdown indefinitely when
    // Redis is down. The timeout only bounds the wait; the forced
    // `disconnect()` calls below always run, so shutdown completes
    // whether or not Redis answers.
    const timeout = (ms: number): Promise<'timeout'> =>
      new Promise((resolve) => setTimeout(() => resolve('timeout'), ms));
    try {
      await Promise.race([this.sub.unsubscribe(), timeout(2000)]);
    } catch {
      // Already unsubscribed / disconnected — shutdown must not throw.
    }
    try {
      await Promise.race([this.pub.quit(), timeout(2000)]);
    } catch {
      try {
        this.pub.disconnect();
      } catch {
        // Already disconnected.
      }
    }
    try {
      this.sub.disconnect();
    } catch {
      // Already disconnected — shutdown must not throw.
    }
  }
}
