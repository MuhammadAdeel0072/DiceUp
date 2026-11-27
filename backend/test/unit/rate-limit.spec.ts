import { ServiceUnavailableException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { ExecutionContext } from '@nestjs/common';
import { RateLimitedException } from '../../src/common/errors/rate-limited.exception';
import { RateLimitGuard } from '../../src/common/rate-limit/rate-limit.guard';
import type { RateLimitOptions } from '../../src/common/rate-limit/rate-limit.decorator';
import { RATE_LIMIT_KEY } from '../../src/common/rate-limit/rate-limit.decorator';
import { RateLimitService } from '../../src/common/rate-limit/rate-limit.service';
import type { RedisService } from '../../src/redis/redis.service';

/** In-memory stand-in for RedisService (unit tests only). */
class FakeRedis {
  private readonly store = new Map<string, number>();
  fail = false;

  async incrWithExpiry(key: string, _window: number): Promise<number> {
    if (this.fail) throw new Error('Redis down');
    const next = (this.store.get(key) ?? 0) + 1;
    this.store.set(key, next);
    return next;
  }

  async ttl(_key: string): Promise<number> {
    return 42;
  }
}

describe('RateLimitService (plan §6.5)', () => {
  let redis: FakeRedis;
  let service: RateLimitService;

  beforeEach(() => {
    redis = new FakeRedis();
    service = new RateLimitService(redis as unknown as RedisService);
  });

  it('allows requests under the limit', async () => {
    await service.check('k', 3, 60, { failClosed: true });
    await service.check('k', 3, 60, { failClosed: true });
    await service.check('k', 3, 60, { failClosed: true });
    await expect(
      service.check('k', 3, 60, { failClosed: true }),
    ).rejects.toBeInstanceOf(RateLimitedException);
  });

  it('429 carries the remaining TTL as Retry-After', async () => {
    for (let i = 0; i < 2; i++) {
      await service.check('k', 2, 60, { failClosed: true });
    }
    try {
      await service.check('k', 2, 60, { failClosed: true });
      fail('should have thrown');
    } catch (err) {
      expect((err as RateLimitedException).retryAfterSeconds).toBe(42);
    }
  });

  it('fail-closed endpoints throw 503 when Redis is down', async () => {
    redis.fail = true;
    await expect(
      service.check('k', 2, 60, { failClosed: true }),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('the generic authenticated limit fails OPEN when Redis is down', async () => {
    redis.fail = true;
    await expect(
      service.check('k', 2, 60, { failClosed: false }),
    ).resolves.toBeUndefined();
  });
});

describe('RateLimitGuard', () => {
  let redis: FakeRedis;

  beforeEach(() => {
    redis = new FakeRedis();
  });

  function makeGuardAndContext(opts: {
    metadata?: RateLimitOptions;
    user?: { id: string };
    ip?: string;
    body?: unknown;
  }): { guard: RateLimitGuard; context: ExecutionContext } {
    const reflector = new Reflector();
    jest.spyOn(reflector, 'getAllAndOverride').mockImplementation((key) => {
      if (key === RATE_LIMIT_KEY) return opts.metadata as never;
      return undefined as never;
    });
    const service = new RateLimitService(redis as unknown as RedisService);
    const guard = new RateLimitGuard(reflector, service);
    const req = {
      ip: opts.ip ?? '127.0.0.1',
      body: opts.body ?? {},
      user: opts.user,
    };
    const context = {
      switchToHttp: () => ({ getRequest: () => req }),
      getHandler: () => ({}) as never,
      getClass: () => ({}) as never,
    } as unknown as ExecutionContext;
    return { guard, context };
  }

  it('passes public routes with no metadata and no user', async () => {
    const { guard, context } = makeGuardAndContext({});
    await expect(guard.canActivate(context)).resolves.toBe(true);
  });

  it('enforces @RateLimit metadata keyed by IP', async () => {
    const meta: RateLimitOptions = {
      limit: 2,
      windowSeconds: 3600,
      windowLabel: '1h',
      keyBy: 'ip',
    };
    const { guard } = makeGuardAndContext({ metadata: meta });
    const ctx = () => makeGuardAndContext({ metadata: meta }).context;
    await expect(guard.canActivate(ctx())).resolves.toBe(true);
    await expect(guard.canActivate(ctx())).resolves.toBe(true);
    await expect(guard.canActivate(ctx())).rejects.toBeInstanceOf(
      RateLimitedException,
    );
  });

  it('enforces @RateLimit metadata keyed by hashed email', async () => {
    const meta: RateLimitOptions = {
      limit: 1,
      windowSeconds: 3600,
      windowLabel: '1h',
      keyBy: 'email',
    };
    const { guard } = makeGuardAndContext({ metadata: meta });
    const ctx = (email: string) =>
      makeGuardAndContext({ metadata: meta, body: { email } }).context;
    await expect(guard.canActivate(ctx('ali@example.com'))).resolves.toBe(true);
    await expect(
      guard.canActivate(ctx('ali@example.com')),
    ).rejects.toBeInstanceOf(RateLimitedException);
    // A different email has its own counter.
    await expect(guard.canActivate(ctx('bob@example.com'))).resolves.toBe(true);
  });

  it('applies the generic 100/min limit to authenticated requests', async () => {
    const { guard } = makeGuardAndContext({ user: { id: 'user-1' } });
    const ctx = () => makeGuardAndContext({ user: { id: 'user-1' } }).context;
    for (let i = 0; i < 100; i++) {
      await guard.canActivate(ctx());
    }
    await expect(guard.canActivate(ctx())).rejects.toBeInstanceOf(
      RateLimitedException,
    );
  });
});
