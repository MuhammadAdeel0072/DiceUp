import { RedisService } from '../../src/redis/redis.service';

/**
 * In-memory fake standing in for ioredis: implements exactly the
 * surface RedisService uses (ping/get/set/del/eval/on/disconnect),
 * including Lua-script semantics for INCR+EXPIRE and lock release.
 * Unit tests the service logic; real-Redis behaviour is covered by
 * the integration suite against a real Redis 7 instance.
 */
class FakeRedis {
  private store = new Map<string, { value: string; expiresAt?: number }>();
  pingOk = true;
  on = jest.fn();

  private live(key: string): string | undefined {
    const entry = this.store.get(key);
    if (!entry) return undefined;
    if (entry.expiresAt && Date.now() > entry.expiresAt) {
      this.store.delete(key);
      return undefined;
    }
    return entry.value;
  }

  async ping(): Promise<string> {
    if (!this.pingOk) throw new Error('ECONNREFUSED');
    return 'PONG';
  }

  async get(key: string): Promise<string | null> {
    return this.live(key) ?? null;
  }

  async set(
    key: string,
    value: string,
    ...args: (string | number)[]
  ): Promise<string | null> {
    // set(key, value, 'EX', ttl) | set(key, value, 'EX', ttl, 'NX')
    const nx = args.includes('NX');
    if (nx && this.live(key) !== undefined) return null;
    const exIdx = args.indexOf('EX');
    const ttl = exIdx >= 0 ? Number(args[exIdx + 1]) : undefined;
    this.store.set(key, {
      value,
      expiresAt: ttl ? Date.now() + ttl * 1000 : undefined,
    });
    return 'OK';
  }

  async del(key: string): Promise<number> {
    return this.store.delete(key) ? 1 : 0;
  }

  async eval(script: string, _keys: number, key: string, arg: string) {
    if (script.includes('INCR')) {
      const current = Number(this.live(key) ?? 0);
      const next = current + 1;
      const ttl = Number(arg);
      this.store.set(key, {
        value: String(next),
        // TTL is set only when the key is created (count == 1).
        expiresAt:
          next === 1 ? Date.now() + ttl * 1000 : this.store.get(key)?.expiresAt,
      });
      return next;
    }
    // Release-lock script: delete only if the stored token matches.
    return this.live(key) === arg ? (this.store.delete(key), 1) : 0;
  }

  disconnect(): void {
    // No-op for the fake.
  }

  ttl(key: string): number {
    const entry = this.store.get(key);
    if (!entry?.expiresAt) return -1;
    return Math.max(0, Math.ceil((entry.expiresAt - Date.now()) / 1000));
  }
}

describe('RedisService (plan §5.2)', () => {
  let fake: FakeRedis;
  let service: RedisService;

  beforeEach(() => {
    fake = new FakeRedis();
    service = new RedisService(fake as never);
  });

  it('ping() is true when Redis answers, false (not a throw) when down', async () => {
    await expect(service.ping()).resolves.toBe(true);
    fake.pingOk = false;
    await expect(service.ping()).resolves.toBe(false);
  });

  it('set/get/del round-trip with TTL', async () => {
    await service.set('k', 'v', 60);
    await expect(service.get('k')).resolves.toBe('v');
    await service.del('k');
    await expect(service.get('k')).resolves.toBeNull();
  });

  it('incrWithExpiry counts and sets a TTL only on first use', async () => {
    await expect(service.incrWithExpiry('rl:ip:1h', 3600)).resolves.toBe(1);
    expect(fake.ttl('rl:ip:1h')).toBeGreaterThan(3500);
    await expect(service.incrWithExpiry('rl:ip:1h', 3600)).resolves.toBe(2);
    await expect(service.incrWithExpiry('rl:ip:1h', 3600)).resolves.toBe(3);
  });

  it('incrWithExpiry is atomic under parallel increments', async () => {
    const results = await Promise.all(
      Array.from({ length: 20 }, () =>
        service.incrWithExpiry('rl:parallel', 60),
      ),
    );
    expect(new Set(results).size).toBe(20);
    expect(Math.max(...results)).toBe(20);
  });

  it('acquireLock is NX: second caller gets null; wrong token cannot release', async () => {
    const token = await service.acquireLock('match:lock:abc', 10);
    expect(token).toBeTruthy();
    await expect(service.acquireLock('match:lock:abc', 10)).resolves.toBeNull();
    await expect(service.releaseLock('match:lock:abc', 'wrong')).resolves.toBe(
      false,
    );
    await expect(service.get('match:lock:abc')).resolves.toBe(token);
    await expect(
      service.releaseLock('match:lock:abc', token as string),
    ).resolves.toBe(true);
    await expect(service.get('match:lock:abc')).resolves.toBeNull();
  });
});
