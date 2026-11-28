import { randomUUID } from 'node:crypto';
import { HttpException } from '@nestjs/common';
import type { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';
import { DataSource } from 'typeorm';
import { buildDataSourceOptions } from '../../src/database/data-source';
import { MatchmakingService } from '../../src/matchmaking/matchmaking.service';
import { REDIS_KEYS } from '../../src/redis/redis-keys';
import { RedisService } from '../../src/redis/redis.service';
import { RoomBroadcaster } from '../../src/rooms/room-broadcaster';
import { RoomsService } from '../../src/rooms/rooms.service';
import { Profile } from '../../src/users/entities/profile.entity';
import { User } from '../../src/users/entities/user.entity';
import {
  REDIS_URL,
  createScratchDb,
  dropScratchDb,
  migrateScratchDb,
} from '../integration/test-helpers';

jest.setTimeout(120000);

/**
 * MatchmakingService against a real PostgreSQL scratch DB + real
 * Redis 7. Covers: queueing + positions, duplicate entries, group
 * formation at exactly 4 (room created, host = earliest arrival),
 * cancel, disconnect removal, refusal while in a room / match, and
 * concurrent grouping (8 simultaneous joins → exactly 2 rooms, an
 * empty queue, nobody in two rooms).
 */
describe('MatchmakingService (real PostgreSQL + real Redis)', () => {
  let dbName: string;
  let databaseUrl: string;
  let ds: DataSource;
  let rooms: RoomsService;
  let matchmaking: MatchmakingService;
  let redis: Redis;
  let redisService: RedisService;

  function codeOf(err: unknown): string | undefined {
    if (err instanceof HttpException) {
      const body = err.getResponse() as { code?: string };
      return typeof body === 'object' ? body.code : undefined;
    }
    return undefined;
  }

  async function makeUser(): Promise<{ id: string }> {
    const tag = randomUUID().slice(0, 8);
    const user = await ds.getRepository(User).save(
      ds.getRepository(User).create({
        email: `mm-${tag}@example.com`,
        username: `mm_${tag}`,
        passwordHash: 'x',
        status: 'active',
        emailVerifiedAt: new Date(),
      }),
    );
    await ds.getRepository(Profile).save(
      ds.getRepository(Profile).create({
        userId: user.id,
        displayName: `MM ${tag}`,
      }),
    );
    return { id: user.id };
  }

  beforeAll(async () => {
    ({ name: dbName, url: databaseUrl } = await createScratchDb());
    await migrateScratchDb(databaseUrl);
    ds = new DataSource(buildDataSourceOptions(databaseUrl));
    await ds.initialize();
    const config = {
      getOrThrow: (key: string) =>
        key === 'app' ? { rulesetVersion: '1.0.0' } : undefined,
    } as unknown as ConfigService;
    rooms = new RoomsService(ds, config, new RoomBroadcaster());
    redis = new Redis(REDIS_URL, {
      lazyConnect: true,
      maxRetriesPerRequest: 3,
    });
    redisService = new RedisService(redis as never);
    matchmaking = new MatchmakingService(
      redisService,
      rooms,
      new RoomBroadcaster(),
    );
  }, 120000);

  afterAll(async () => {
    if (redis) redis.disconnect();
    if (ds) await ds.destroy();
    if (dbName) await dropScratchDb(dbName);
  });

  beforeEach(async () => {
    await redis.del(REDIS_KEYS.matchmakingQueue);
  });

  it('queues players with positions; duplicate join is refused', async () => {
    const a = await makeUser();
    const b = await makeUser();
    const first = await matchmaking.join(a.id);
    expect(first).toMatchObject({ matched: false, position: 1 });
    const second = await matchmaking.join(b.id);
    expect(second).toMatchObject({ matched: false, position: 2 });
    await expect(matchmaking.join(a.id)).rejects.toThrow();
    try {
      await matchmaking.join(a.id);
      throw new Error('should have thrown');
    } catch (err) {
      expect(codeOf(err)).toBe('ALREADY_IN_MATCHMAKING');
    }
    await expect(matchmaking.status(a.id)).resolves.toMatchObject({
      status: 'queued',
      position: 1,
      queueSize: 2,
      groupSize: 4,
    });
  });

  it('forms a room at 4: host is the earliest arrival', async () => {
    const users = await Promise.all(
      Array.from({ length: 4 }, () => makeUser()),
    );
    for (const u of users.slice(0, 3)) {
      await expect(matchmaking.join(u.id)).resolves.toMatchObject({
        matched: false,
      });
    }
    const fourth = await matchmaking.join(users[3].id);
    expect(fourth.matched).toBe(true);
    if (!fourth.matched) throw new Error('expected a match');
    expect(fourth.room.members).toHaveLength(4);
    expect(fourth.room.hostId).toBe(users[0].id);
    expect(fourth.room.source).toBe('matchmaking');
    expect(fourth.room.maxPlayers).toBe(4);
    expect(fourth.room.code).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
    expect(fourth.room.members.map((m) => m.userId)).toEqual(
      users.map((u) => u.id),
    );
    for (const u of users) {
      await expect(matchmaking.status(u.id)).resolves.toMatchObject({
        status: 'matched',
        roomId: fourth.room.id,
        roomCode: fourth.room.code,
      });
    }
    expect(await redis.zcard(REDIS_KEYS.matchmakingQueue)).toBe(0);
  });

  it('cancel leaves the queue; a second cancel reports left: false', async () => {
    const a = await makeUser();
    await matchmaking.join(a.id);
    await expect(matchmaking.leave(a.id)).resolves.toEqual({ left: true });
    await expect(matchmaking.leave(a.id)).resolves.toEqual({ left: false });
    await expect(matchmaking.status(a.id)).resolves.toMatchObject({
      status: 'idle',
    });
  });

  it('disconnect removal drops the queue entry', async () => {
    const a = await makeUser();
    await matchmaking.join(a.id);
    await matchmaking.removeFromQueue(a.id);
    await expect(matchmaking.status(a.id)).resolves.toMatchObject({
      status: 'idle',
    });
    // Removing a non-queued player is a no-op, never a throw.
    await expect(matchmaking.removeFromQueue(a.id)).resolves.toBeUndefined();
  });

  it('refuses join while in an open room or an active match', async () => {
    const a = await makeUser();
    const room = await rooms.createRoom(a.id, 4);
    try {
      await matchmaking.join(a.id);
      throw new Error('should have thrown');
    } catch (err) {
      expect(codeOf(err)).toBe('ALREADY_IN_ROOM');
    }
    const b = await makeUser();
    await rooms.joinByCode(b.id, room.code);
    await rooms.setReady(a.id, room.id, true);
    await rooms.setReady(b.id, room.id, true);
    await rooms.startMatch(a.id, room.id);
    try {
      await matchmaking.join(a.id);
      throw new Error('should have thrown');
    } catch (err) {
      expect(codeOf(err)).toBe('ALREADY_IN_MATCH');
    }
  });

  it('concurrent grouping: 8 joins form exactly 2 rooms, queue empties', async () => {
    const users = await Promise.all(
      Array.from({ length: 8 }, () => makeUser()),
    );
    const results = await Promise.all(users.map((u) => matchmaking.join(u.id)));
    const matched = results.filter((r) => r.matched);
    expect(matched).toHaveLength(2);
    const roomIds = new Set(matched.map((r) => (r.matched ? r.room.id : '')));
    expect(roomIds.size).toBe(2);
    expect(await redis.zcard(REDIS_KEYS.matchmakingQueue)).toBe(0);
    // Nobody is in two rooms.
    const memberships = await ds.query(
      `SELECT "user_id", COUNT(*) AS c FROM "room_members"
        GROUP BY "user_id" HAVING COUNT(*) > 1`,
    );
    expect(memberships).toHaveLength(0);
    for (const r of matched) {
      if (!r.matched) continue;
      expect(r.room.members).toHaveLength(4);
    }
  });
});
