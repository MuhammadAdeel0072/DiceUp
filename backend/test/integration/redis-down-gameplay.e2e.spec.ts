import { randomUUID } from 'node:crypto';
import { AddressInfo } from 'node:net';
import { INestApplication } from '@nestjs/common';
import { DataSource } from 'typeorm';
import * as request from 'supertest';
import { io, type Socket as ClientSocket } from 'socket.io-client';
import { LogMailerService } from '../../src/mailer/log-mailer.service';
import { RoomBroadcaster } from '../../src/rooms/room-broadcaster';
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
 * Dead-Redis gameplay (Stage 5, assessment risk 5) — extends the
 * Stage 4 redis-down spec with real game traffic.
 *
 * A match is started on the live-Redis app; a second app boots
 * against the SAME scratch database with a dead Redis URL. The
 * dead-Redis node must:
 * - keep an in-progress match going (dice:roll applies, checkpoints
 *   in PostgreSQL, and reaches the members' local sockets — the
 *   broadcast gate delivers locally instead of queueing an
 *   unbounded adapter publish, and the dropped remote fan-out is
 *   counted);
 * - refuse NEW matches with MATCH_UNAVAILABLE;
 * - keep serving REST reads from PostgreSQL.
 *
 * Tokens are minted on the live app (register/verify/login need
 * Redis, so they cannot run on the dead node) and reused on the
 * dead node — both apps share the database and the JWT keys.
 */
describe('dead-Redis gameplay (real PostgreSQL, Redis down)', () => {
  let dbName: string;
  let databaseUrl: string;
  let liveApp: INestApplication;
  let deadApp: INestApplication;
  let ds: DataSource;
  let mailer: LogMailerService;
  let cleaner: RateLimitCleaner;
  let livePort: number;
  let deadPort: number;
  const clients: ClientSocket[] = [];

  let host: { accessToken: string; userId: string };
  let guest: { accessToken: string; userId: string };
  let matchId: string;
  let room2Id: string;
  let host2: { accessToken: string; userId: string };

  const liveApi = () => request(liveApp.getHttpServer());
  const deadApi = () => request(deadApp.getHttpServer());
  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  function connect(
    port: number,
    authToken: string,
  ): Promise<{ client: ClientSocket; connected: Promise<unknown> }> {
    return new Promise((resolve, reject) => {
      const client = io(`http://127.0.0.1:${port}/game`, {
        auth: { token: authToken },
        reconnection: false,
        // Handshakes on the dead node also wait out Redis retries.
        timeout: 30000,
      });
      clients.push(client);
      const connected = once(client, 'connected');
      connected.catch(() => undefined);
      client.once('connect', () => resolve({ client, connected }));
      client.once('connect_error', (err: Error) => reject(err));
    });
  }

  function once<T>(
    client: ClientSocket,
    event: string,
    // Dead-Redis operations are slow: each RedisService command
    // waits out up to 3 reconnect cycles at the 2 s backoff cap
    // (~6 s per command once backoff saturates), so a roll on the
    // dead node takes ~15 s end to end. The behaviour is what this
    // spec proves; the latency is a measured property of the Phase 4
    // retry policy (see the final report).
    timeoutMs = 45000,
  ): Promise<T> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`timed out waiting for '${event}'`)),
        timeoutMs,
      );
      client.once(event, (data: T) => {
        clearTimeout(timer);
        resolve(data);
      });
    });
  }

  async function verifiedAccessToken(
    api: () => ReturnType<typeof request>,
  ): Promise<{ accessToken: string; userId: string }> {
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

  beforeAll(async () => {
    ({ name: dbName, url: databaseUrl } = await createScratchDb());
    await migrateScratchDb(databaseUrl);
    liveApp = await bootTestApp(databaseUrl);
    await liveApp.listen(0);
    livePort = (liveApp.getHttpServer().address() as AddressInfo).port;
    ds = liveApp.get(DataSource);
    mailer = liveApp.get(LogMailerService);
    cleaner = new RateLimitCleaner();
    // Clear any counters left by an earlier spec file (notably the
    // gameplay spec's L-02 flood: 120 connections/min per IP) before
    // this file's own sockets connect.
    await cleaner.clear();

    host = await verifiedAccessToken(liveApi);
    guest = await verifiedAccessToken(liveApi);
    const room = await liveApi()
      .post('/v1/rooms')
      .set(auth(host.accessToken))
      .send({ maxPlayers: 2 });
    expect(room.status).toBe(201);
    await liveApi()
      .post('/v1/rooms/join')
      .set(auth(guest.accessToken))
      .send({ code: room.body.data.code as string });
    const hostConn = await connect(livePort, host.accessToken);
    const guestConn = await connect(livePort, guest.accessToken);
    const join = async (client: ClientSocket, code: string) => {
      const updated = once(client, 'room:updated');
      client.emit('room:join', { roomCode: code });
      await updated;
    };
    await join(hostConn.client, room.body.data.code as string);
    await join(guestConn.client, room.body.data.code as string);
    const ready = async (
      client: ClientSocket,
      watcher: ClientSocket,
      roomId: string,
    ) => {
      const updated = once(watcher, 'room:updated');
      client.emit('room:ready', { roomId, ready: true });
      await updated;
    };
    await ready(guestConn.client, hostConn.client, room.body.data.id as string);
    await ready(hostConn.client, guestConn.client, room.body.data.id as string);
    const started = once<{ matchId: string }>(hostConn.client, 'match:started');
    hostConn.client.emit('match:start', { roomId: room.body.data.id });
    matchId = (await started).matchId;

    // A second room, ready but NOT started — the dead node must
    // refuse to start it.
    host2 = await verifiedAccessToken(liveApi);
    const guest2 = await verifiedAccessToken(liveApi);
    const room2 = await liveApi()
      .post('/v1/rooms')
      .set(auth(host2.accessToken))
      .send({ maxPlayers: 2 });
    expect(room2.status).toBe(201);
    room2Id = room2.body.data.id as string;
    await liveApi()
      .post('/v1/rooms/join')
      .set(auth(guest2.accessToken))
      .send({ code: room2.body.data.code as string });

    deadApp = await bootTestApp(databaseUrl, {
      redisUrl: 'redis://127.0.0.1:6399',
    });
    await deadApp.listen(0);
    deadPort = (deadApp.getHttpServer().address() as AddressInfo).port;
  }, 180000);

  afterAll(async () => {
    for (const client of clients) {
      try {
        client.disconnect();
      } catch {
        // Already gone.
      }
    }
    if (cleaner) await cleaner.quit();
    if (deadApp) await deadApp.close();
    // bootTestApp overwrote process.env.REDIS_URL with the dead URL;
    // restore the shared default so later spec files boot against
    // the real Redis.
    process.env.REDIS_URL = REDIS_URL;
    if (liveApp) await liveApp.close();
    if (dbName) await dropScratchDb(dbName);
  });

  it('boots degraded: liveness answers, readiness reports redis down', async () => {
    const live = await deadApi().get('/v1/health');
    expect(live.status).toBe(200);
    const ready = await deadApi().get('/v1/health/ready');
    expect(ready.status).toBe(503);
    expect(ready.body.error.data.redis).toBe('down');
    expect(ready.body.error.data.database).toBe('up');
  });

  it('an in-progress match continues: the roll applies, checkpoints, and reaches local sockets', async () => {
    const hostConn = await connect(deadPort, host.accessToken);
    const guestConn = await connect(deadPort, guest.accessToken);
    const broadcaster = deadApp.get(RoomBroadcaster);
    const droppedBefore = broadcaster.getDroppedRemoteBroadcasts();
    const t0 = Date.now();
    const hostRolled = once<{
      matchId: string;
      playerId: string;
      value: number;
      seq: number;
    }>(hostConn.client, 'dice:rolled');
    const guestRolled = once<{
      matchId: string;
      playerId: string;
      value: number;
      seq: number;
    }>(guestConn.client, 'dice:rolled');
    hostConn.client.emit('dice:roll', {
      matchId,
      requestId: randomUUID(),
    });
    const hostSeen = await hostRolled;
    const guestSeen = await guestRolled;
    // Record the dead-node roll latency (see the `once` comment):
    // it is slow, but it completes, checkpoints, and delivers.
    const rollMs = Date.now() - t0;
    expect(rollMs).toBeLessThan(45000);
    expect(hostSeen).toEqual(guestSeen);
    expect(hostSeen.matchId).toBe(matchId);
    expect(hostSeen.playerId).toBe(host.userId);
    expect(hostSeen.value).toBeGreaterThanOrEqual(1);
    expect(hostSeen.value).toBeLessThanOrEqual(6);
    expect(hostSeen.seq).toBe(2);
    // The transition checkpointed in PostgreSQL (not just in memory).
    const rows = await ds.query(
      `SELECT "type", "payload" FROM "move_events" WHERE "match_id" = $1 AND "seq_no" = 2`,
      [matchId],
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].type).toBe('dice_rolled');
    expect((rows[0].payload as { value: number }).value).toBe(hostSeen.value);
    // The broadcast gate delivered locally and counted the dropped
    // remote fan-out instead of queueing an unbounded publish.
    expect(broadcaster.getDroppedRemoteBroadcasts()).toBeGreaterThan(
      droppedBefore,
    );
    // A snapshot still serves from PostgreSQL on the dead node.
    const state = once<{ seq: number }>(guestConn.client, 'match:state');
    guestConn.client.emit('state:request', { matchId, lastSeq: 0 });
    expect((await state).seq).toBeGreaterThanOrEqual(2);
  });

  it('new matches are refused while Redis is down', async () => {
    const host2Conn = await connect(deadPort, host2.accessToken);
    const err = once<{
      success: boolean;
      error: { code: string; message: string };
    }>(host2Conn.client, 'exception');
    host2Conn.client.emit('match:start', { roomId: room2Id });
    const envelope = await err;
    expect(envelope.success).toBe(false);
    expect(envelope.error.code).toBe('MATCH_UNAVAILABLE');
    const matches = await ds.query(
      `SELECT COUNT(*) AS "n" FROM "matches" WHERE "room_id" = $1`,
      [room2Id],
    );
    expect(Number(matches[0].n)).toBe(0);
  });

  it('REST reads keep serving from PostgreSQL while Redis is down', async () => {
    const res = await deadApi()
      .get(`/v1/matches/${matchId}`)
      .set(auth(host.accessToken));
    expect(res.status).toBe(200);
    expect(res.body.data.id).toBe(matchId);
    expect(res.body.data.status).toBe('in_progress');
    const events = await deadApi()
      .get(`/v1/matches/${matchId}/events`)
      .set(auth(guest.accessToken));
    expect(events.status).toBe(200);
    expect(
      (events.body.data.events as Array<{ type: string }>).map((e) => e.type),
    ).toContain('dice_rolled');
  });
});
