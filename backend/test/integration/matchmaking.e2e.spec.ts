import { INestApplication } from '@nestjs/common';
import Redis from 'ioredis';
import * as request from 'supertest';
import { LogMailerService } from '../../src/mailer/log-mailer.service';
import { REDIS_KEYS } from '../../src/redis/redis-keys';
import { RoomsService } from '../../src/rooms/rooms.service';
import {
  REDIS_URL,
  bootTestApp,
  createScratchDb,
  dropScratchDb,
  migrateScratchDb,
  RateLimitCleaner,
  uniqueUser,
} from './test-helpers';

/**
 * Matchmaking REST end-to-end (plan §10.3): real PostgreSQL 16 +
 * real Redis 7, fresh scratch database. Covers: join/leave/status,
 * duplicate queue entries, group formation at 4 (room created),
 * refusal while in a room or an active match, and unauthorised
 * access. Disconnect removal is covered by rooms-socket.e2e.spec.ts
 * (it needs a live socket); atomic grouping under concurrency is
 * covered by matchmaking.service.spec.ts.
 */
describe('matchmaking REST (real PostgreSQL + real Redis)', () => {
  let dbName: string;
  let databaseUrl: string;
  let app: INestApplication;
  let mailer: LogMailerService;
  let cleaner: RateLimitCleaner;
  let redis: Redis;

  const api = () => request(app.getHttpServer());
  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  async function verifiedAccessToken(): Promise<{
    accessToken: string;
    userId: string;
  }> {
    const u = uniqueUser();
    const reg = await api().post('/v1/auth/register').send(u);
    expect(reg.status).toBe(201);
    const msg = mailer.findLatest(u.email, 'verification');
    expect(msg).toBeDefined();
    const ver = await api()
      .post('/v1/auth/verify-email')
      .send({ token: msg!.token });
    expect(ver.status).toBe(200);
    const log = await api()
      .post('/v1/auth/login')
      .send({ identifier: u.email, password: u.password });
    expect(log.status).toBe(200);
    return {
      accessToken: log.body.data.tokens.accessToken as string,
      userId: reg.body.data.user.id as string,
    };
  }

  const joinQueue = (token: string) =>
    api().post('/v1/matchmaking/join').set(auth(token));
  const queueStatus = (token: string) =>
    api().get('/v1/matchmaking/status').set(auth(token));

  beforeAll(async () => {
    ({ name: dbName, url: databaseUrl } = await createScratchDb());
    await migrateScratchDb(databaseUrl);
    app = await bootTestApp(databaseUrl);
    await app.listen(0);
    mailer = app.get(LogMailerService);
    cleaner = new RateLimitCleaner();
    redis = new Redis(REDIS_URL, {
      lazyConnect: true,
      maxRetriesPerRequest: 3,
    });
  }, 120000);

  afterAll(async () => {
    if (redis) redis.disconnect();
    if (cleaner) await cleaner.quit();
    if (app) await app.close();
    if (dbName) await dropScratchDb(dbName);
  });

  beforeEach(async () => {
    await cleaner.clear();
    mailer.clear();
    // The queue is one global sorted set in the shared local Redis:
    // a player left queued by an earlier test would silently join
    // the next test's group. Each test starts from an empty queue.
    await redis.del(REDIS_KEYS.matchmakingQueue);
  });

  it('refuses unauthenticated matchmaking calls (401)', async () => {
    await expect(api().post('/v1/matchmaking/join')).resolves.toMatchObject({
      status: 401,
    });
    await expect(api().post('/v1/matchmaking/leave')).resolves.toMatchObject({
      status: 401,
    });
    await expect(api().get('/v1/matchmaking/status')).resolves.toMatchObject({
      status: 401,
    });
  });

  it('queues with positions; duplicate join 409; cancel → idle', async () => {
    const a = await verifiedAccessToken();
    const first = await joinQueue(a.accessToken);
    expect(first.status).toBe(200);
    expect(first.body.data).toMatchObject({
      matched: false,
      position: 1,
      groupSize: 4,
    });
    const dup = await joinQueue(a.accessToken);
    expect(dup.status).toBe(409);
    expect(dup.body.error.code).toBe('ALREADY_IN_MATCHMAKING');
    const b = await verifiedAccessToken();
    const second = await joinQueue(b.accessToken);
    expect(second.body.data).toMatchObject({ matched: false, position: 2 });
    const status = await queueStatus(a.accessToken);
    expect(status.body.data).toMatchObject({
      status: 'queued',
      position: 1,
      queueSize: 2,
    });
    const left = await api()
      .post('/v1/matchmaking/leave')
      .set(auth(a.accessToken));
    expect(left.status).toBe(200);
    expect(left.body.data).toEqual({ left: true });
    const idle = await queueStatus(a.accessToken);
    expect(idle.body.data).toMatchObject({ status: 'idle' });
    const leftAgain = await api()
      .post('/v1/matchmaking/leave')
      .set(auth(a.accessToken));
    expect(leftAgain.body.data).toEqual({ left: false });
  });

  it('forms a room when the 4th player joins; all four see matched', async () => {
    const players = [];
    for (let i = 0; i < 4; i += 1) {
      players.push(await verifiedAccessToken());
    }
    for (const p of players.slice(0, 3)) {
      const res = await joinQueue(p.accessToken);
      expect(res.body.data.matched).toBe(false);
    }
    const fourth = await joinQueue(players[3].accessToken);
    expect(fourth.status).toBe(200);
    expect(fourth.body.data.matched).toBe(true);
    const room = fourth.body.data.room;
    expect(room.members).toHaveLength(4);
    expect(room.hostId).toBe(players[0].userId);
    expect(room.source).toBe('matchmaking');
    for (const p of players) {
      const status = await queueStatus(p.accessToken);
      expect(status.body.data).toMatchObject({
        status: 'matched',
        roomId: room.id,
        roomCode: room.code,
      });
    }
  });

  it('refuses join while in an open room or an active match', async () => {
    const a = await verifiedAccessToken();
    const created = await api()
      .post('/v1/rooms')
      .set(auth(a.accessToken))
      .send({ maxPlayers: 4 });
    expect(created.status).toBe(201);
    const inRoom = await joinQueue(a.accessToken);
    expect(inRoom.status).toBe(409);
    expect(inRoom.body.error.code).toBe('ALREADY_IN_ROOM');
    const b = await verifiedAccessToken();
    await api()
      .post('/v1/rooms/join')
      .set(auth(b.accessToken))
      .send({ code: created.body.data.code });
    const rooms = app.get(RoomsService);
    await rooms.setReady(a.userId, created.body.data.id, true);
    await rooms.setReady(b.userId, created.body.data.id, true);
    await rooms.startMatch(a.userId, created.body.data.id);
    const inMatch = await joinQueue(a.accessToken);
    expect(inMatch.status).toBe(409);
    expect(inMatch.body.error.code).toBe('ALREADY_IN_MATCH');
  });
});
