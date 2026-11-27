import { ServiceUnavailableException } from '@nestjs/common';
import { LoginThrottleService } from '../../src/auth/login-throttle.service';
import type { RedisService } from '../../src/redis/redis.service';
import { RateLimitedException } from '../../src/common/errors/rate-limited.exception';

/** In-memory stand-in for RedisService (unit tests only). */
class FakeRedis {
  private readonly store = new Map<string, number>();
  fail = false;

  async get(key: string): Promise<string | null> {
    if (this.fail) throw new Error('Redis down');
    const v = this.store.get(key);
    return v === undefined ? null : String(v);
  }

  async incrWithExpiry(key: string, _window: number): Promise<number> {
    if (this.fail) throw new Error('Redis down');
    const next = (this.store.get(key) ?? 0) + 1;
    this.store.set(key, next);
    return next;
  }

  async del(key: string): Promise<void> {
    if (this.fail) throw new Error('Redis down');
    this.store.delete(key);
  }

  async ttl(_key: string): Promise<number> {
    return 900;
  }
}

describe('LoginThrottleService (NFR-16)', () => {
  let redis: FakeRedis;
  let throttle: LoginThrottleService;

  beforeEach(() => {
    redis = new FakeRedis();
    throttle = new LoginThrottleService(redis as unknown as RedisService);
  });

  it('allows logins below the failure threshold', async () => {
    await throttle.recordFailure('ali@example.com', '1.2.3.4');
    await throttle.recordFailure('ali@example.com', '1.2.3.4');
    await expect(
      throttle.assertNotThrottled('ali@example.com', '1.2.3.4'),
    ).resolves.toBeUndefined();
  });

  it('throttles after 5 failures — even with the correct password path', async () => {
    for (let i = 0; i < 5; i++) {
      await throttle.recordFailure('ali@example.com', '1.2.3.4');
    }
    await expect(
      throttle.assertNotThrottled('ali@example.com', '1.2.3.4'),
    ).rejects.toBeInstanceOf(RateLimitedException);
    try {
      await throttle.assertNotThrottled('ali@example.com', '1.2.3.4');
      fail('should have thrown');
    } catch (err) {
      expect(err).toBeInstanceOf(RateLimitedException);
      expect((err as RateLimitedException).retryAfterSeconds).toBe(900);
    }
  });

  it('throttles by account and by IP independently', async () => {
    // 5 failures for the account from different IPs → account throttled.
    for (let i = 0; i < 5; i++) {
      await throttle.recordFailure('ali@example.com', `10.0.0.${i}`);
    }
    await expect(
      throttle.assertNotThrottled('ali@example.com', '9.9.9.9'),
    ).rejects.toBeInstanceOf(RateLimitedException);
    // A different account from a fresh IP is not throttled.
    await expect(
      throttle.assertNotThrottled('bob@example.com', '9.9.9.9'),
    ).resolves.toBeUndefined();
    // 5 failures from one IP across accounts → IP throttled.
    for (let i = 0; i < 5; i++) {
      await throttle.recordFailure(`user${i}@example.com`, '5.5.5.5');
    }
    await expect(
      throttle.assertNotThrottled('new@example.com', '5.5.5.5'),
    ).rejects.toBeInstanceOf(RateLimitedException);
  });

  it('success resets the account counter but NOT the shared IP counter', async () => {
    for (let i = 0; i < 5; i++) {
      await throttle.recordFailure('ali@example.com', '1.2.3.4');
    }
    await throttle.reset('ali@example.com', '1.2.3.4');
    // The account itself is unthrottled again (from a fresh IP).
    await expect(
      throttle.assertNotThrottled('ali@example.com', '9.9.9.9'),
    ).resolves.toBeUndefined();
    // Stage 4, M-03: the IP counter survives the reset — a success by
    // one user must not hand an attacker on the same egress IP a fresh
    // budget. It expires naturally after its 15-minute TTL instead.
    await expect(
      throttle.assertNotThrottled('other@example.com', '1.2.3.4'),
    ).rejects.toBeInstanceOf(RateLimitedException);
  });

  it('never puts a raw email address in a Redis key', () => {
    expect(LoginThrottleService.accountKey('Ali@Example.com')).not.toContain(
      'Ali',
    );
    expect(LoginThrottleService.accountKey('Ali@Example.com')).not.toContain(
      'example.com',
    );
    // Case-insensitive: same identifier, same key.
    expect(LoginThrottleService.accountKey('ALI@EXAMPLE.COM')).toBe(
      LoginThrottleService.accountKey('ali@example.com'),
    );
  });

  it('fails CLOSED (503) when Redis is down — never runs unthrottled', async () => {
    redis.fail = true;
    await expect(
      throttle.assertNotThrottled('ali@example.com', '1.2.3.4'),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    await expect(
      throttle.recordFailure('ali@example.com', '1.2.3.4'),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
    // reset() is best-effort and must not fail the login.
    await expect(
      throttle.reset('ali@example.com', '1.2.3.4'),
    ).resolves.toBeUndefined();
  });
});
