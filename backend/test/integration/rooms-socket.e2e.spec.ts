import { AddressInfo } from 'node:net';
import { INestApplication } from '@nestjs/common';
import { DataSource } from 'typeorm';
import Redis from 'ioredis';
import * as request from 'supertest';
import { io, type Socket as ClientSocket } from 'socket.io-client';
import { LogMailerService } from '../../src/mailer/log-mailer.service';
import { REDIS_KEYS } from '../../src/redis/redis-keys';
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
 * Room socket end-to-end (plan §10.3): real PostgreSQL 16 + real
 * Redis 7, real HTTP listen, socket.io-client on /game.
 *
 * Covers: authenticated `room:join` / `room:leave` / `room:ready`
 * with `room:updated` broadcasts to the room, `match:start` +
 * `match:started` (host-only, all-ready gate), the §6.3 error codes
 * on the `exception` channel (ROOM_NOT_FOUND / ROOM_FULL /
 * NOT_ROOM_HOST / INVALID_STATE), `matchmaking:matched` delivery to
 * each grouped player's socket, and queue removal on disconnect.
 * Gameplay events (dice:roll, token:move) are Stage 5 — not here.
 */
describe('room socket (real PostgreSQL + real Redis)', () => {
  let dbName: string;
  let databaseUrl: string;
  let app: INestApplication;
  let ds: DataSource;
  let mailer: LogMailerService;
  let cleaner: RateLimitCleaner;
  let redis: Redis;
  let port: number;
  const clients: ClientSocket[] = [];

  const api = () => request(app.getHttpServer());
  const url = () => `http://127.0.0.1:${port}/game`;
  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  function connect(authToken?: string): Promise<{
    client: ClientSocket;
    connected: Promise<{ userId: string; socketId: string }>;
  }> {
    return new Promise((resolve, reject) => {
      const client = io(url(), {
        auth: authToken ? { token: authToken } : {},
        reconnection: false,
        timeout: 5000,
      });
      clients.push(client);
      const connected = once<{ userId: string; socketId: string }>(
        client,
        'connected',
      );
      connected.catch(() => undefined);
      client.once('connect', () => resolve({ client, connected }));
      client.once('connect_error', (err: Error) => reject(err));
    });
  }

  function once<T>(
    client: ClientSocket,
    event: string,
    timeoutMs = 8000,
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

  /** Next `exception` event payload (the §6.3 envelope). */
  function nextException(
    client: ClientSocket,
  ): Promise<{ success: boolean; error: { code: string; message: string } }> {
    return once(client, 'exception');
  }

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

  async function createRoom(
    token: string,
    maxPlayers = 4,
  ): Promise<{ id: string; code: string }> {
    const res = await api()
      .post('/v1/rooms')
      .set(auth(token))
      .send({ maxPlayers });
    expect(res.status).toBe(201);
    return {
      id: res.body.data.id as string,
      code: res.body.data.code as string,
    };
  }

  beforeAll(async () => {
    ({ name: dbName, url: databaseUrl } = await createScratchDb());
    await migrateScratchDb(databaseUrl);
    app = await bootTestApp(databaseUrl);
    await app.listen(0);
    port = (app.getHttpServer().address() as AddressInfo).port;
    ds = app.get(DataSource);
    mailer = app.get(LogMailerService);
    cleaner = new RateLimitCleaner();
    redis = new Redis(REDIS_URL, {
      lazyConnect: true,
      maxRetriesPerRequest: 3,
    });
  }, 120000);

  afterAll(async () => {
    for (const client of clients) {
      try {
        client.disconnect();
      } catch {
        // Already gone.
      }
    }
    if (redis) redis.disconnect();
    if (cleaner) await cleaner.quit();
    if (app) await app.close();
    if (dbName) await dropScratchDb(dbName);
  });

  beforeEach(async () => {
    await cleaner.clear();
    mailer.clear();
    // One global queue in the shared local Redis — clear it so a
    // queued player from an earlier test cannot join this test's group.
    await redis.del(REDIS_KEYS.matchmakingQueue);
  });

  afterEach(() => {
    for (const client of clients.splice(0)) {
      try {
        client.disconnect();
      } catch {
        // Already gone.
      }
    }
  });

  it('room:join broadcasts room:updated; room:ready updates readiness for all', async () => {
    const host = await verifiedAccessToken();
    const guest = await verifiedAccessToken();
    const room = await createRoom(host.accessToken, 4);

    const hostSocket = await connect(host.accessToken);
    const hostUpdated = once<{
      room: { id: string; status: string };
      members: Array<{ userId: string; isReady: boolean }>;
      ready: Record<string, boolean>;
    }>(hostSocket.client, 'room:updated');
    hostSocket.client.emit('room:join', { roomCode: room.code });
    const hostView = await hostUpdated;
    expect(hostView.room.id).toBe(room.id);
    expect(hostView.members).toHaveLength(1);

    // The guest's join broadcasts to the host's socket too.
    const hostSeesGuest = once<{ members: Array<{ userId: string }> }>(
      hostSocket.client,
      'room:updated',
    );
    const guestSocket = await connect(guest.accessToken);
    const guestUpdated = once<{
      members: Array<{ userId: string }>;
    }>(guestSocket.client, 'room:updated');
    guestSocket.client.emit('room:join', { roomCode: room.code });
    const guestView = await guestUpdated;
    expect(guestView.members).toHaveLength(2);
    const hostAfterGuest = await hostSeesGuest;
    expect(hostAfterGuest.members).toHaveLength(2);

    // Guest readies up: the host sees ready:true for the guest.
    const hostSeesReady = once<{
      ready: Record<string, boolean>;
    }>(hostSocket.client, 'room:updated');
    guestSocket.client.emit('room:ready', { roomId: room.id, ready: true });
    const readyView = await hostSeesReady;
    expect(readyView.ready[guest.userId]).toBe(true);
    expect(readyView.ready[host.userId]).toBe(false);
  });

  it('room:join with an unknown code emits ROOM_NOT_FOUND on exception', async () => {
    const user = await verifiedAccessToken();
    const { client } = await connect(user.accessToken);
    const err = nextException(client);
    client.emit('room:join', { roomCode: 'ZZZZZZ' });
    const envelope = await err;
    expect(envelope.success).toBe(false);
    expect(envelope.error.code).toBe('ROOM_NOT_FOUND');
  });

  it('room:join on a full room emits ROOM_FULL', async () => {
    const host = await verifiedAccessToken();
    const room = await createRoom(host.accessToken, 2);
    const guest = await verifiedAccessToken();
    await api()
      .post('/v1/rooms/join')
      .set(auth(guest.accessToken))
      .send({ code: room.code });
    const third = await verifiedAccessToken();
    const { client } = await connect(third.accessToken);
    const err = nextException(client);
    client.emit('room:join', { roomCode: room.code });
    const envelope = await err;
    expect(envelope.error.code).toBe('ROOM_FULL');
  });

  it('match:start: non-host and not-all-ready are rejected; ready host starts', async () => {
    const host = await verifiedAccessToken();
    const guest = await verifiedAccessToken();
    const room = await createRoom(host.accessToken, 2);
    const hostSocket = await connect(host.accessToken);
    const guestSocket = await connect(guest.accessToken);
    hostSocket.client.emit('room:join', { roomCode: room.code });
    await once(hostSocket.client, 'room:updated');
    guestSocket.client.emit('room:join', { roomCode: room.code });
    await once(guestSocket.client, 'room:updated');

    // Non-host start → NOT_ROOM_HOST.
    const notHost = nextException(guestSocket.client);
    guestSocket.client.emit('match:start', { roomId: room.id });
    expect((await notHost).error.code).toBe('NOT_ROOM_HOST');

    // Host start with nobody ready → INVALID_STATE.
    const notReady = nextException(hostSocket.client);
    hostSocket.client.emit('match:start', { roomId: room.id });
    expect((await notReady).error.code).toBe('INVALID_STATE');

    // Both ready → both sockets get match:started.
    const hostStarted = once<{
      matchId: string;
      roomId: string;
      seats: Array<{ userId: string; seat: number; colour: string }>;
      rulesetVersion: string;
    }>(hostSocket.client, 'match:started');
    const guestStarted = once<{ matchId: string }>(
      guestSocket.client,
      'match:started',
    );
    const hostSeesGuestReady = once(hostSocket.client, 'room:updated');
    guestSocket.client.emit('room:ready', { roomId: room.id, ready: true });
    await hostSeesGuestReady;
    const guestSeesHostReady = once(guestSocket.client, 'room:updated');
    hostSocket.client.emit('room:ready', { roomId: room.id, ready: true });
    await guestSeesHostReady;
    hostSocket.client.emit('match:start', { roomId: room.id });
    const started = await hostStarted;
    const guestSeen = await guestStarted;
    expect(started.matchId).toBe(guestSeen.matchId);
    expect(started.roomId).toBe(room.id);
    expect(started.rulesetVersion).toBe('1.0.0');
    expect(started.seats).toEqual([
      { userId: host.userId, seat: 0, colour: 'red' },
      { userId: guest.userId, seat: 1, colour: 'green' },
    ]);
    // The match row exists in PostgreSQL.
    const rows = await ds.query(
      `SELECT "status" FROM "matches" WHERE "id" = $1`,
      [started.matchId],
    );
    expect(rows).toHaveLength(1);
    expect(rows[0].status).toBe('in_progress');
  });

  it('room:leave removes the member and broadcasts; leaver gets no further updates', async () => {
    const host = await verifiedAccessToken();
    const guest = await verifiedAccessToken();
    const room = await createRoom(host.accessToken, 4);
    const hostSocket = await connect(host.accessToken);
    const guestSocket = await connect(guest.accessToken);
    hostSocket.client.emit('room:join', { roomCode: room.code });
    await once(hostSocket.client, 'room:updated');
    guestSocket.client.emit('room:join', { roomCode: room.code });
    await once(guestSocket.client, 'room:updated');
    const hostSeesLeave = once<{ members: Array<{ userId: string }> }>(
      hostSocket.client,
      'room:updated',
    );
    guestSocket.client.emit('room:leave', { roomId: room.id });
    const afterLeave = await hostSeesLeave;
    expect(afterLeave.members.map((m) => m.userId)).toEqual([host.userId]);
  });

  it('matchmaking:matched reaches every grouped player’s socket', async () => {
    const players = [];
    for (let i = 0; i < 4; i += 1) {
      players.push(await verifiedAccessToken());
    }
    const sockets = [];
    const matchedPromises = [];
    for (const p of players) {
      const s = await connect(p.accessToken);
      sockets.push(s);
      matchedPromises.push(
        once<{ roomId: string; roomCode: string }>(
          s.client,
          'matchmaking:matched',
        ),
      );
    }
    for (const p of players.slice(0, 3)) {
      const res = await api()
        .post('/v1/matchmaking/join')
        .set(auth(p.accessToken));
      expect(res.body.data.matched).toBe(false);
    }
    const fourth = await api()
      .post('/v1/matchmaking/join')
      .set(auth(players[3].accessToken));
    expect(fourth.body.data.matched).toBe(true);
    const roomCode = fourth.body.data.room.code as string;
    const notices = await Promise.all(matchedPromises);
    expect(notices).toHaveLength(4);
    for (const n of notices) {
      expect(n.roomCode).toBe(roomCode);
      expect(n.roomId).toBe(fourth.body.data.room.id as string);
    }
  });

  it('disconnect removes the player from the matchmaking queue', async () => {
    const user = await verifiedAccessToken();
    const joined = await api()
      .post('/v1/matchmaking/join')
      .set(auth(user.accessToken));
    expect(joined.body.data.matched).toBe(false);
    const { client } = await connect(user.accessToken);
    client.disconnect();
    // The gateway removes the queue entry on disconnect; poll until
    // it is gone (bounded — the removal is synchronous in the handler,
    // the poll only absorbs scheduling jitter).
    let status = '';
    for (let i = 0; i < 20; i += 1) {
      const res = await api()
        .get('/v1/matchmaking/status')
        .set(auth(user.accessToken));
      status = res.body.data.status as string;
      if (status === 'idle') break;
      await new Promise((r) => setTimeout(r, 100));
    }
    expect(status).toBe('idle');
  });
});
