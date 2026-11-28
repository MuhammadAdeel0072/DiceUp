import { randomUUID } from 'node:crypto';
import { AddressInfo } from 'node:net';
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import Redis from 'ioredis';
import * as request from 'supertest';
import { io, type Socket as ClientSocket } from 'socket.io-client';
import { AppModule } from '../../src/app.module';
import { FixedDiceRoller } from '../../src/game/dice-roller';
import { MATCH_DICE_ROLLER } from '../../src/match/match.service';
import { LogMailerService } from '../../src/mailer/log-mailer.service';
import { REDIS_KEYS } from '../../src/redis/redis-keys';
import { createApp } from './test-app.factory';
import {
  REDIS_URL,
  createScratchDb,
  dropScratchDb,
  migrateScratchDb,
  RateLimitCleaner,
  uniqueUser,
} from './test-helpers';
import {
  captureSetup,
  insertRecordedEvents,
  nearWinSetup,
  snapshotTokenSteps,
} from './gameplay-helpers';

/**
 * Gameplay socket end-to-end (Phase 5, Stage 5): real PostgreSQL 16
 * + real Redis 7, real HTTP listen, socket.io-client on /game.
 *
 * The app boots with MATCH_DICE_ROLLER overridden to a shared
 * FixedDiceRoller, reseeded before each match that rolls — so dice
 * are deterministic per test while the server still generates every
 * roll (a client-supplied value is ignored). Board positions that
 * random dice cannot reach quickly (a capture, a near-win) are
 * built by inserting the exact move_events rows the engine recorded
 * in-process (see gameplay-helpers.ts) and then continued live.
 *
 * Covers: dice/move/capture/turn sync, invalid actions (out of
 * turn, wrong player, illegal move, client-supplied dice, move
 * before roll), duplicate intents (same requestId → original
 * result, one transition), simultaneous intents (exactly one wins),
 * match completion (winner + standings + persisted result),
 * state:request → match:state, non-member exclusion (cannot act,
 * cannot subscribe, cannot read), the REST lifecycle reads, and
 * the L-02 socket connection rate limit.
 */
describe('gameplay socket (real PostgreSQL + real Redis)', () => {
  let dbName: string;
  let databaseUrl: string;
  let app: INestApplication;
  let ds: DataSource;
  let mailer: LogMailerService;
  let cleaner: RateLimitCleaner;
  let redis: Redis;
  let roller: FixedDiceRoller;
  let port: number;
  const clients: ClientSocket[] = [];

  const api = () => request(app.getHttpServer());
  const url = () => `http://127.0.0.1:${port}/game`;
  const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

  /** Boot the app with a deterministic dice roller (test override). */
  async function bootGameApp(
    dbUrl: string,
  ): Promise<{ app: INestApplication; roller: FixedDiceRoller }> {
    process.env.NODE_ENV = 'test';
    process.env.DATABASE_URL = dbUrl;
    process.env.REDIS_URL = REDIS_URL;
    process.env.PORT = '3000';
    process.env.RULESET_VERSION = '1.0.0';
    const dice = new FixedDiceRoller([6], { cycle: true });
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(MATCH_DICE_ROLLER)
      .useValue(dice)
      .compile();
    const testApp = moduleRef.createNestApplication();
    await createApp(testApp);
    await testApp.init();
    return { app: testApp, roller: dice };
  }

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

  /** Attempt a connection; resolves with ok or the connect_error code. */
  function tryConnect(
    authToken: string,
  ): Promise<{ ok: boolean; code?: string }> {
    return new Promise((resolve) => {
      const client = io(url(), {
        auth: { token: authToken },
        reconnection: false,
        timeout: 5000,
      });
      clients.push(client);
      client.once('connect', () => resolve({ ok: true }));
      client.once('connect_error', (err: Error & { data?: unknown }) => {
        const data = err.data as { error?: { code?: string } } | undefined;
        resolve({ ok: false, code: data?.error?.code });
      });
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

  /** Events of one type seen within `ms` (for asserting non-delivery). */
  function collectFor<T>(
    client: ClientSocket,
    event: string,
    ms: number,
  ): Promise<T[]> {
    return new Promise((resolve) => {
      const seen: T[] = [];
      const handler = (data: T) => seen.push(data);
      client.on(event, handler);
      setTimeout(() => {
        client.off(event, handler);
        resolve(seen);
      }, ms);
    });
  }

  /** Poll until `check()` holds (for events delivered to another socket). */
  async function waitFor(
    check: () => boolean,
    timeoutMs = 8000,
  ): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      if (check()) return;
      if (Date.now() > deadline) {
        throw new Error('timed out waiting for a condition');
      }
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
  }

  function nextRejected(client: ClientSocket): Promise<{
    matchId: string;
    requestId?: string;
    code: string;
    message: string;
  }> {
    return once(client, 'action:rejected');
  }

  function nextException(
    client: ClientSocket,
  ): Promise<{ success: boolean; error: { code: string; message: string } }> {
    return once(client, 'exception');
  }

  async function verifiedAccessToken(): Promise<{
    accessToken: string;
    userId: string;
    username: string;
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
      username: u.username,
    };
  }

  async function createRoom(
    token: string,
    maxPlayers = 2,
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

  async function joinRoom(socket: ClientSocket, code: string): Promise<void> {
    const updated = once(socket, 'room:updated');
    socket.emit('room:join', { roomCode: code });
    await updated;
  }

  async function setReady(
    socket: ClientSocket,
    watcher: ClientSocket,
    roomId: string,
    ready: boolean,
  ): Promise<void> {
    const updated = once(watcher, 'room:updated');
    socket.emit('room:ready', { roomId, ready });
    await updated;
  }

  /** Two players, one room, match started. Returns the match id. */
  async function startMatch(): Promise<{
    matchId: string;
    roomId: string;
    host: { accessToken: string; userId: string; username: string };
    guest: { accessToken: string; userId: string; username: string };
    hostSocket: ClientSocket;
    guestSocket: ClientSocket;
  }> {
    const host = await verifiedAccessToken();
    const guest = await verifiedAccessToken();
    const room = await createRoom(host.accessToken, 2);
    const hostConn = await connect(host.accessToken);
    const guestConn = await connect(guest.accessToken);
    await joinRoom(hostConn.client, room.code);
    await joinRoom(guestConn.client, room.code);
    await setReady(guestConn.client, hostConn.client, room.id, true);
    await setReady(hostConn.client, guestConn.client, room.id, true);
    const hostStarted = once<{
      matchId: string;
      roomId: string;
      seats: Array<{ userId: string; seat: number; colour: string }>;
    }>(hostConn.client, 'match:started');
    const guestStarted = once<{ matchId: string }>(
      guestConn.client,
      'match:started',
    );
    hostConn.client.emit('match:start', { roomId: room.id });
    const started = await hostStarted;
    await guestStarted;
    return {
      matchId: started.matchId,
      roomId: room.id,
      host,
      guest,
      hostSocket: hostConn.client,
      guestSocket: guestConn.client,
    };
  }

  async function countEvents(matchId: string, type?: string): Promise<number> {
    const rows = await ds.query(
      `SELECT COUNT(*) AS "n" FROM "move_events" WHERE "match_id" = $1` +
        (type ? ` AND "type" = $2` : ''),
      type ? [matchId, type] : [matchId],
    );
    return Number(rows[0].n);
  }

  beforeAll(async () => {
    ({ name: dbName, url: databaseUrl } = await createScratchDb());
    await migrateScratchDb(databaseUrl);
    ({ app, roller } = await bootGameApp(databaseUrl));
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
    // Leave Redis clean: the L-02 tests flood the per-IP connection
    // counter (120/min), and the next spec file's beforeAll connects
    // within the same minute window.
    if (cleaner) await cleaner.clear();
    if (cleaner) await cleaner.quit();
    if (app) await app.close();
    if (dbName) await dropScratchDb(dbName);
  });

  beforeEach(async () => {
    await cleaner.clear();
    mailer.clear();
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

  it('dice sync: both players see the server roll; state:request serves the snapshot', async () => {
    const { matchId, hostSocket, guestSocket } = await startMatch();
    roller.reseed([6]);
    const hostRolled = once<{
      matchId: string;
      playerId: string;
      value: number;
      seq: number;
    }>(hostSocket, 'dice:rolled');
    const guestRolled = once<{
      matchId: string;
      playerId: string;
      value: number;
      seq: number;
    }>(guestSocket, 'dice:rolled');
    hostSocket.emit('dice:roll', {
      matchId,
      requestId: randomUUID(),
    });
    const hostSeen = await hostRolled;
    const guestSeen = await guestRolled;
    expect(hostSeen).toEqual(guestSeen);
    expect(hostSeen.matchId).toBe(matchId);
    expect(hostSeen.value).toBe(6);
    expect(hostSeen.seq).toBe(2);
    // The snapshot agrees (seq 2 proves no follow-up event fired).
    const state = once<{
      matchId: string;
      seq: number;
      snapshot: Record<string, unknown>;
      seats: Array<{ userId: string; seat: number }>;
    }>(guestSocket, 'match:state');
    guestSocket.emit('state:request', { matchId, lastSeq: 2 });
    const snapshot = await state;
    expect(snapshot.matchId).toBe(matchId);
    expect(snapshot.seq).toBe(2);
    expect(snapshot.seats).toHaveLength(2);
    const snap = snapshot.snapshot as {
      phase: string;
      lastRoll: number;
      currentPlayerIndex: number;
    };
    expect(snap.phase).toBe('awaitingMove');
    expect(snap.lastRoll).toBe(6);
    expect(snap.currentPlayerIndex).toBe(0);
  });

  it('move sync: a release lands on the start cell with an extra turn', async () => {
    const { matchId, host, hostSocket, guestSocket } = await startMatch();
    roller.reseed([6]);
    const hostRolled = once(hostSocket, 'dice:rolled');
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    await hostRolled;
    const hostMoved = once<{
      matchId: string;
      tokenId: string;
      landing: { kind: string; index: number };
      captured: string[];
      extraTurn: boolean;
      winner: string | null;
      seq: number;
      turn: { playerId: string; turnEndsAt: unknown };
    }>(hostSocket, 'token:moved');
    const guestMoved = once<{ tokenId: string; seq: number }>(
      guestSocket,
      'token:moved',
    );
    hostSocket.emit('token:move', {
      matchId,
      tokenId: '0:0',
      requestId: randomUUID(),
    });
    const moved = await hostMoved;
    const guestSeen = await guestMoved;
    expect(moved.tokenId).toBe('0:0');
    expect(moved.landing).toEqual({ kind: 'track', index: 0 });
    expect(moved.captured).toEqual([]);
    expect(moved.extraTurn).toBe(true);
    expect(moved.winner).toBeNull();
    expect(moved.seq).toBe(3);
    // Stage 6: the turn carries the real deadline (extra turn, so
    // the deadline is the re-armed one for the host's next roll).
    expect(moved.turn.playerId).toBe(host.userId);
    expect(typeof moved.turn.turnEndsAt).toBe('string');
    expect(Date.parse(moved.turn.turnEndsAt as string)).toBeGreaterThan(
      Date.now(),
    );
    expect(guestSeen.tokenId).toBe('0:0');
    expect(guestSeen.seq).toBe(3);
  });

  it('turn sync: a roll with no legal move passes the turn to the other player', async () => {
    const { matchId, guest, hostSocket, guestSocket } = await startMatch();
    roller.reseed([2]);
    const hostRolled = once<{ value: number; seq: number }>(
      hostSocket,
      'dice:rolled',
    );
    const guestTurn = once<{
      matchId: string;
      playerId: string;
      turnEndsAt: unknown;
      seq: number;
    }>(guestSocket, 'turn:changed');
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    const rolled = await hostRolled;
    expect(rolled.value).toBe(2);
    expect(rolled.seq).toBe(2);
    const turned = await guestTurn;
    expect(turned.playerId).toBe(guest.userId);
    // Stage 6: turn:changed carries the real deadline of the
    // guest's turn (30 s from the roll, per the seeded config).
    expect(typeof turned.turnEndsAt).toBe('string');
    expect(Date.parse(turned.turnEndsAt as string)).toBeGreaterThan(Date.now());
    expect(turned.seq).toBe(3);
    // It is now the guest's turn: their roll succeeds.
    const guestRolled = once<{ value: number; seq: number }>(
      guestSocket,
      'dice:rolled',
    );
    guestSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    const guestRoll = await guestRolled;
    expect(guestRoll.value).toBe(2);
    expect(guestRoll.seq).toBe(4);
  });

  it('capture sync: the capturing move sends the victim home and grants an extra turn', async () => {
    const { matchId, host, guest, hostSocket, guestSocket } =
      await startMatch();
    const setup = captureSetup([
      { userId: host.userId, seat: 0, colour: 'red', name: host.username },
      { userId: guest.userId, seat: 1, colour: 'green', name: guest.username },
    ]);
    await insertRecordedEvents(ds, matchId, setup.events);
    // Replay reproduced the scripted position (the checkpoint proof).
    const before = await api()
      .get(`/v1/matches/${matchId}/state`)
      .set(auth(host.accessToken));
    expect(before.status).toBe(200);
    expect(
      snapshotTokenSteps(
        before.body.data.snapshot as Record<string, unknown>,
        0,
        0,
      ),
    ).toBe(7);
    expect(
      snapshotTokenSteps(
        before.body.data.snapshot as Record<string, unknown>,
        1,
        0,
      ),
    ).toBe(3);
    roller.reseed([6, 3]);
    // Collect the guest's moves from the start: a `once` registered
    // after the host has seen its copy can catch the FIRST move's
    // still-in-flight delivery to the guest instead of the capture.
    const guestMoves: Array<{
      tokenId: string;
      landing: { kind: string; index: number };
      captured: string[];
      extraTurn: boolean;
      seq: number;
    }> = [];
    guestSocket.on('token:moved', (data) =>
      guestMoves.push(
        data as {
          tokenId: string;
          landing: { kind: string; index: number };
          captured: string[];
          extraTurn: boolean;
          seq: number;
        },
      ),
    );
    const hostRolled = once<{ value: number; seq: number }>(
      hostSocket,
      'dice:rolled',
    );
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    expect((await hostRolled).value).toBe(6);
    const hostMoved = once<{
      tokenId: string;
      landing: { kind: string; index: number };
      seq: number;
    }>(hostSocket, 'token:moved');
    hostSocket.emit('token:move', {
      matchId,
      tokenId: '0:0',
      requestId: randomUUID(),
    });
    const firstMove = await hostMoved;
    // Steps 7 -> 13 land on track (0 + 13 - 1) = 12.
    expect(firstMove.landing).toEqual({ kind: 'track', index: 12 });
    const secondRoll = once<{ value: number }>(hostSocket, 'dice:rolled');
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    expect((await secondRoll).value).toBe(3);
    const secondMove = once<{
      tokenId: string;
      captured: string[];
      extraTurn: boolean;
    }>(hostSocket, 'token:moved');
    hostSocket.emit('token:move', {
      matchId,
      tokenId: '0:0',
      requestId: randomUUID(),
    });
    const moved = await secondMove;
    expect(moved.captured).toEqual(['1:0']);
    // Steps 13 -> 16 land on track 15 — green's cell (13 + 3 - 1):
    // the capture sends 1:0 back to the yard and grants an extra turn.
    await waitFor(() => guestMoves.length >= 2);
    const capture = guestMoves[1];
    expect(capture.tokenId).toBe('0:0');
    expect(capture.landing).toEqual({ kind: 'track', index: 15 });
    expect(capture.captured).toEqual(['1:0']);
    expect(capture.extraTurn).toBe(true);
    const after = await api()
      .get(`/v1/matches/${matchId}/state`)
      .set(auth(host.accessToken));
    expect(
      snapshotTokenSteps(
        after.body.data.snapshot as Record<string, unknown>,
        0,
        0,
      ),
    ).toBe(16);
    expect(
      snapshotTokenSteps(
        after.body.data.snapshot as Record<string, unknown>,
        1,
        0,
      ),
    ).toBe(0);
  });

  it('client-supplied dice are ignored: the server rolls its own value', async () => {
    const { matchId, hostSocket, guestSocket } = await startMatch();
    roller.reseed([2]);
    const hostRolled = once<{ value: number }>(hostSocket, 'dice:rolled');
    const guestRolled = once<{ value: number }>(guestSocket, 'dice:rolled');
    hostSocket.emit('dice:roll', {
      matchId,
      requestId: randomUUID(),
      value: 6,
    });
    expect((await hostRolled).value).toBe(2);
    expect((await guestRolled).value).toBe(2);
  });

  it('invalid actions are rejected with a code and the state is unchanged', async () => {
    const { matchId, host, hostSocket, guestSocket } = await startMatch();
    roller.reseed([6, 5]);
    // The host (seat 0) moves first: the guest's roll is out of turn.
    const notTurn = nextRejected(guestSocket);
    guestSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    expect((await notTurn).code).toBe('NOT_YOUR_TURN');
    // Host rolls 6 and releases 0:0 (yard -> start cell, step 1).
    const hostRolled = once<{ value: number; seq: number }>(
      hostSocket,
      'dice:rolled',
    );
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    expect((await hostRolled).value).toBe(6);
    const hostMoved = once(hostSocket, 'token:moved');
    hostSocket.emit('token:move', {
      matchId,
      tokenId: '0:0',
      requestId: randomUUID(),
    });
    await hostMoved;
    // Host rolls 5 (extra turn from the six): only 0:0 may move —
    // 0:1 is still in the yard and a 5 cannot release it.
    const secondRoll = once<{ value: number }>(hostSocket, 'dice:rolled');
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    expect((await secondRoll).value).toBe(5);
    const illegal = nextRejected(hostSocket);
    hostSocket.emit('token:move', {
      matchId,
      tokenId: '0:1',
      requestId: randomUUID(),
    });
    expect((await illegal).code).toBe('ILLEGAL_MOVE');
    // The legal move still applies; the turn then passes to the guest.
    const moved = once(hostSocket, 'token:moved');
    hostSocket.emit('token:move', {
      matchId,
      tokenId: '0:0',
      requestId: randomUUID(),
    });
    await moved;
    // Only the accepted transitions checkpointed — seq 1 started,
    // 2 dice, 3 move, 4 dice, 5 move, 6 turn change.
    const state = await api()
      .get(`/v1/matches/${matchId}/state`)
      .set(auth(host.accessToken));
    expect(state.body.data.seq).toBe(6);
    expect(await countEvents(matchId)).toBe(6);
    // The guest's turn, before any roll: a move is not a legal state.
    const beforeRoll = nextRejected(guestSocket);
    guestSocket.emit('token:move', {
      matchId,
      tokenId: '1:0',
      requestId: randomUUID(),
    });
    expect((await beforeRoll).code).toBe('INVALID_STATE');
    expect(await countEvents(matchId)).toBe(6);
  });

  it('duplicate intents return the original result with no second transition', async () => {
    const { matchId, hostSocket, guestSocket } = await startMatch();
    roller.reseed([6]);
    const rollId = randomUUID();
    const firstRoll = once<{ value: number; seq: number }>(
      hostSocket,
      'dice:rolled',
    );
    // Wait for BOTH copies of the original roll first: the guest's
    // delivery can lag the host's, and a late original landing in
    // the quiet window below would look like a duplicate broadcast.
    const guestFirstRoll = once<{ value: number; seq: number }>(
      guestSocket,
      'dice:rolled',
    );
    hostSocket.emit('dice:roll', { matchId, requestId: rollId });
    const rolled = await firstRoll;
    expect(await guestFirstRoll).toEqual(rolled);
    expect(rolled.seq).toBe(2);
    // The duplicate goes to the requester only, with the same seq —
    // and the guest sees nothing new.
    const guestQuiet = collectFor(guestSocket, 'dice:rolled', 400);
    const dupRoll = once<{ value: number; seq: number }>(
      hostSocket,
      'dice:rolled',
    );
    hostSocket.emit('dice:roll', { matchId, requestId: rollId });
    const repeated = await dupRoll;
    expect(repeated).toEqual(rolled);
    expect(await guestQuiet).toEqual([]);
    expect(await countEvents(matchId, 'dice_rolled')).toBe(1);
    const moveId = randomUUID();
    const firstMove = once<{ tokenId: string; seq: number }>(
      hostSocket,
      'token:moved',
    );
    hostSocket.emit('token:move', {
      matchId,
      tokenId: '0:0',
      requestId: moveId,
    });
    const moved = await firstMove;
    expect(moved.seq).toBe(3);
    const dupMove = once<{ tokenId: string; seq: number }>(
      hostSocket,
      'token:moved',
    );
    hostSocket.emit('token:move', {
      matchId,
      tokenId: '0:0',
      requestId: moveId,
    });
    expect(await dupMove).toEqual(moved);
    expect(await countEvents(matchId, 'token_moved')).toBe(1);
  });

  it('simultaneous intents: exactly one wins and the state stays consistent', async () => {
    const { matchId, hostSocket, guestSocket } = await startMatch();
    roller.reseed([6]);
    // Two concurrent rolls, different requestIds: one dice:rolled,
    // one action:rejected, one row.
    const rolled = once(hostSocket, 'dice:rolled');
    const rejected = nextRejected(hostSocket);
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    await rolled;
    expect((await rejected).code).toBe('INVALID_STATE');
    expect(await countEvents(matchId, 'dice_rolled')).toBe(1);
    // Two concurrent moves for two different legal tokens: one wins.
    const moved = once(hostSocket, 'token:moved');
    const moveRejected = nextRejected(hostSocket);
    hostSocket.emit('token:move', {
      matchId,
      tokenId: '0:0',
      requestId: randomUUID(),
    });
    hostSocket.emit('token:move', {
      matchId,
      tokenId: '0:1',
      requestId: randomUUID(),
    });
    await moved;
    expect((await moveRejected).code).toBe('INVALID_STATE');
    expect(await countEvents(matchId, 'token_moved')).toBe(1);
    expect(guestSocket.connected).toBe(true);
  });

  it('match completion: winner, standings and the persisted result', async () => {
    const { matchId, host, guest, hostSocket, guestSocket } =
      await startMatch();
    const setup = nearWinSetup([
      { userId: host.userId, seat: 0, colour: 'red', name: host.username },
      { userId: guest.userId, seat: 1, colour: 'green', name: guest.username },
    ]);
    await insertRecordedEvents(ds, matchId, setup.events);
    const finalState = setup.finalState as {
      players: Array<{ tokens: Array<{ stepsTaken: number }> }>;
    };
    const winningToken = finalState.players[0].tokens.findIndex(
      (t) => t.stepsTaken === 55,
    );
    expect(winningToken).toBeGreaterThanOrEqual(0);
    roller.reseed([1]);
    const hostEnded = once<{
      matchId: string;
      winnerId: string;
      standings: Array<{
        userId: string;
        rank: number;
        result: string;
      }>;
      seq: number;
    }>(hostSocket, 'match:ended');
    const guestEnded = once<{ winnerId: string }>(guestSocket, 'match:ended');
    const hostMoved = once<{ winner: string | null }>(
      hostSocket,
      'token:moved',
    );
    const hostRolled = once<{ value: number }>(hostSocket, 'dice:rolled');
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    expect((await hostRolled).value).toBe(1);
    hostSocket.emit('token:move', {
      matchId,
      tokenId: `0:${winningToken}`,
      requestId: randomUUID(),
    });
    expect((await hostMoved).winner).toBe(host.userId);
    const ended = await hostEnded;
    expect((await guestEnded).winnerId).toBe(host.userId);
    expect(ended.winnerId).toBe(host.userId);
    expect(ended.standings).toEqual([
      expect.objectContaining({
        userId: host.userId,
        rank: 1,
        result: 'win',
      }),
      expect.objectContaining({
        userId: guest.userId,
        rank: 2,
        result: 'loss',
      }),
    ]);
    const view = await api()
      .get(`/v1/matches/${matchId}`)
      .set(auth(host.accessToken));
    expect(view.status).toBe(200);
    expect(view.body.data.status).toBe('completed');
    expect(view.body.data.winnerId).toBe(host.userId);
    expect(view.body.data.players).toEqual([
      expect.objectContaining({
        userId: host.userId,
        result: 'win',
        finishRank: 1,
      }),
      expect.objectContaining({
        userId: guest.userId,
        result: 'loss',
        finishRank: 2,
      }),
    ]);
    // The move log ends with match_ended — fetch the tail window by
    // seq, since the full scripted log exceeds the default page of
    // 200 rows (the endpoint returns from the start otherwise).
    const stateRes = await api()
      .get(`/v1/matches/${matchId}/state`)
      .set(auth(host.accessToken));
    const finalSeq = stateRes.body.data.seq as number;
    const log = await api()
      .get(`/v1/matches/${matchId}/events?fromSeq=${finalSeq - 2}&limit=10`)
      .set(auth(host.accessToken));
    expect(log.status).toBe(200);
    expect(log.body.data.seq).toBe(finalSeq);
    const seqs = (log.body.data.events as Array<{ seq: number }>).map(
      (e) => e.seq,
    );
    expect(seqs).toEqual([...seqs].sort((a, b) => a - b));
    expect((log.body.data.events as Array<{ type: string }>).at(-1)?.type).toBe(
      'match_ended',
    );
    // The match is over: further intents are refused.
    const finished = nextRejected(hostSocket);
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    expect((await finished).code).toBe('MATCH_FINISHED');
  });

  it('state:request with a lastSeq ahead of the server is rejected', async () => {
    const { matchId, hostSocket } = await startMatch();
    const rejected = nextRejected(hostSocket);
    hostSocket.emit('state:request', { matchId, lastSeq: 99 });
    expect((await rejected).code).toBe('STALE_STATE');
    const state = once<{ seq: number }>(hostSocket, 'match:state');
    hostSocket.emit('state:request', { matchId, lastSeq: 0 });
    expect((await state).seq).toBe(1);
  });

  it('a non-member cannot act, cannot subscribe, and cannot read the match', async () => {
    const { matchId, host, hostSocket } = await startMatch();
    const outsider = await verifiedAccessToken();
    const outsiderConn = await connect(outsider.accessToken);
    const outsiderSocket = outsiderConn.client;
    const notPlayer = nextRejected(outsiderSocket);
    outsiderSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    expect((await notPlayer).code).toBe('NOT_MATCH_PLAYER');
    const notPlayerState = nextRejected(outsiderSocket);
    outsiderSocket.emit('state:request', { matchId, lastSeq: 0 });
    expect((await notPlayerState).code).toBe('NOT_MATCH_PLAYER');
    // The outsider never receives match events: the host rolls and
    // the outsider's socket stays silent.
    roller.reseed([6]);
    const outsiderQuiet = collectFor(outsiderSocket, 'dice:rolled', 400);
    const hostRolled = once(hostSocket, 'dice:rolled');
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    await hostRolled;
    expect(await outsiderQuiet).toEqual([]);
    // REST reads are player-only too.
    const forbidden = await api()
      .get(`/v1/matches/${matchId}`)
      .set(auth(outsider.accessToken));
    expect(forbidden.status).toBe(403);
    expect(forbidden.body.error.code).toBe('NOT_MATCH_PLAYER');
    const unknown = await api()
      .get(`/v1/matches/${randomUUID()}`)
      .set(auth(host.accessToken));
    expect(unknown.status).toBe(404);
    expect(unknown.body.error.code).toBe('MATCH_NOT_FOUND');
    const noActive = await api()
      .get('/v1/matches/active')
      .set(auth(outsider.accessToken));
    expect(noActive.status).toBe(404);
  });

  it('REST lifecycle reads: active, match, state, ordered events', async () => {
    const { matchId, host, guest, hostSocket } = await startMatch();
    roller.reseed([6]);
    const rolled = once(hostSocket, 'dice:rolled');
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    await rolled;
    const active = await api()
      .get('/v1/matches/active')
      .set(auth(host.accessToken));
    expect(active.status).toBe(200);
    expect(active.body.data.id).toBe(matchId);
    expect(active.body.data.status).toBe('in_progress');
    expect(active.body.data.seq).toBe(2);
    const match = await api()
      .get(`/v1/matches/${matchId}`)
      .set(auth(guest.accessToken));
    expect(match.status).toBe(200);
    expect(match.body.data.players).toHaveLength(2);
    const state = await api()
      .get(`/v1/matches/${matchId}/state`)
      .set(auth(host.accessToken));
    expect(state.status).toBe(200);
    expect(state.body.data.seq).toBe(2);
    expect((state.body.data.snapshot as { phase: string }).phase).toBe(
      'awaitingMove',
    );
    const events = await api()
      .get(`/v1/matches/${matchId}/events`)
      .set(auth(host.accessToken));
    expect(events.status).toBe(200);
    expect(
      (events.body.data.events as Array<{ type: string }>).map((e) => e.type),
    ).toEqual(['match_started', 'dice_rolled']);
    const fromTwo = await api()
      .get(`/v1/matches/${matchId}/events?fromSeq=2&limit=1`)
      .set(auth(host.accessToken));
    expect(fromTwo.body.data.events).toHaveLength(1);
    expect(fromTwo.body.data.events[0].seq).toBe(2);
  });

  it('malformed game payloads are rejected on exception, connection survives', async () => {
    const { hostSocket } = await startMatch();
    const err = nextException(hostSocket);
    hostSocket.emit('dice:roll', { matchId: 'not-a-uuid', requestId: 'x' });
    const envelope = await err;
    expect(envelope.success).toBe(false);
    expect(envelope.error.code).toBe('VALIDATION_FAILED');
    // The connection still works afterwards.
    const pong = once<{ requestId: string }>(hostSocket, 'pong');
    hostSocket.emit('ping', { requestId: randomUUID() });
    expect((await pong).requestId).toBeDefined();
  });

  it('L-02: the per-user connection limit refuses the 21st connection', async () => {
    const user = await verifiedAccessToken();
    const results: Array<{ ok: boolean; code?: string }> = [];
    for (let i = 0; i < 21; i += 1) {
      results.push(await tryConnect(user.accessToken));
    }
    expect(results.slice(0, 20).every((r) => r.ok)).toBe(true);
    expect(results[20].ok).toBe(false);
    expect(results[20].code).toBe('RATE_LIMITED');
  });

  it('L-02: the per-IP connection limit refuses past 120 connections', async () => {
    const users = [];
    for (let i = 0; i < 7; i += 1) {
      users.push(await verifiedAccessToken());
      // Register + verify-email share one `ratelimit:ip:…:1h` bucket
      // (10/hr, Phase 4 design — the endpoint is not in the key), so
      // 7 users would exhaust it mid-loop without a reset. The reset
      // is safe here: no sockets exist yet, so no connection counter
      // is touched.
      await cleaner.clear();
    }
    const results: Array<{ ok: boolean; code?: string }> = [];
    for (let i = 0; i < 126; i += 1) {
      const user = users[i % users.length];
      results.push(await tryConnect(user.accessToken));
      if (results.filter((r) => !r.ok).length >= 3) break;
    }
    const okCount = results.filter((r) => r.ok).length;
    expect(okCount).toBe(120);
    expect(
      results.slice(120).every((r) => !r.ok && r.code === 'RATE_LIMITED'),
    ).toBe(true);
  });
});
