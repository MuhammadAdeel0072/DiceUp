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
  private zsets = new Map<string, Map<string, number>>();
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
    if (script.includes('ZRANGE')) {
      // popGroup script: atomically pop the first N members when at
      // least N are present, else nothing.
      const count = Number(arg);
      const members = this.sorted(key);
      if (members.length < count) return [];
      const popped = members.slice(0, count);
      const set = this.zsets.get(key)!;
      for (const m of popped) set.delete(m);
      return popped;
    }
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

  private sorted(key: string): string[] {
    const set = this.zsets.get(key);
    if (!set) return [];
    return [...set.entries()]
      .sort((a, b) => a[1] - b[1] || (a[0] < b[0] ? -1 : 1))
      .map(([member]) => member);
  }

  async zadd(
    key: string,
    mode: string,
    score: number,
    member: string,
  ): Promise<number> {
    let set = this.zsets.get(key);
    if (!set) {
      set = new Map();
      this.zsets.set(key, set);
    }
    if (mode === 'NX' && set.has(member)) return 0;
    set.set(member, score);
    return 1;
  }

  async zscore(key: string, member: string): Promise<string | null> {
    const score = this.zsets.get(key)?.get(member);
    return score === undefined ? null : String(score);
  }

  async zrank(key: string, member: string): Promise<number | null> {
    const members = this.sorted(key);
    const rank = members.indexOf(member);
    return rank === -1 ? null : rank;
  }

  async zcard(key: string): Promise<number> {
    return this.zsets.get(key)?.size ?? 0;
  }

  async zrem(key: string, member: string): Promise<number> {
    return this.zsets.get(key)?.delete(member) ? 1 : 0;
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

  it('sorted sets: zaddNx is NX, zscore/zrank/zcard/zrem track the queue', async () => {
    await expect(service.zaddNx('matchmaking:queue', 100, 'u1')).resolves.toBe(
      true,
    );
    await expect(service.zaddNx('matchmaking:queue', 200, 'u1')).resolves.toBe(
      false,
    );
    await expect(service.zscore('matchmaking:queue', 'u1')).resolves.toBe(100);
    await service.zaddNx('matchmaking:queue', 50, 'u2');
    await expect(service.zrank('matchmaking:queue', 'u2')).resolves.toBe(0);
    await expect(service.zrank('matchmaking:queue', 'u1')).resolves.toBe(1);
    await expect(service.zcard('matchmaking:queue')).resolves.toBe(2);
    await expect(service.zrem('matchmaking:queue', 'u2')).resolves.toBe(true);
    await expect(service.zrem('matchmaking:queue', 'u2')).resolves.toBe(false);
    await expect(service.zscore('matchmaking:queue', 'u2')).resolves.toBeNull();
  });

  it('popGroup pops the earliest N only when N are present', async () => {
    await service.zaddNx('matchmaking:queue', 3, 'u3');
    await service.zaddNx('matchmaking:queue', 1, 'u1');
    await service.zaddNx('matchmaking:queue', 2, 'u2');
    // Fewer than 4 present: nothing is removed.
    await expect(service.popGroup('matchmaking:queue', 4)).resolves.toEqual([]);
    await expect(service.zcard('matchmaking:queue')).resolves.toBe(3);
    await service.zaddNx('matchmaking:queue', 4, 'u4');
    await expect(service.popGroup('matchmaking:queue', 4)).resolves.toEqual([
      'u1',
      'u2',
      'u3',
      'u4',
    ]);
    await expect(service.zcard('matchmaking:queue')).resolves.toBe(0);
  });
});
