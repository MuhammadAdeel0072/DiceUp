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
  insertRecordedEvents,
  nearWinSetup,
  snapshotTokenSteps,
} from './gameplay-helpers';

jest.setTimeout(120000);

/**
 * Recovery + timers socket end-to-end (Phase 5, Stage 6): real
 * PostgreSQL 16 + real Redis 7, real HTTP listen, socket.io-client
 * on /game. The app boots with the seeded config overridden to
 * SHORT values (turn 2 s, grace 3 s, missed-turn limit 3) so the
 * timer/grace paths run in seconds — the values still come from
 * the `game_configurations` row, never from a test-only bypass.
 *
 * Covers: disconnect mid-turn → `player:disconnected` with
 * `graceEndsAt` → reconnect → `match:state` with the same seq +
 * turn → play continues; grace expiry → `player:forfeited` →
 * sole remaining player wins; 3 missed turns → forfeit;
 * voluntary leave mid-match → forfeit; timer expiry → auto-roll
 * + FIRST legal auto-move (engine order) and skip-if-no-legal-move;
 * exactly-once timeout (no duplicate rows); restart
 * restore-or-cancel (stop the server mid-match, restart on the
 * same DB, assert the match is restored with correct state and
 * play continues, and a corrupt-log match is cleanly cancelled);
 * reconnect to a finished match returns the final state;
 * non-member reconnect/state requests are rejected.
 */
describe('recovery + timers socket (real PostgreSQL + real Redis)', () => {
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

  async function listenOn(testApp: INestApplication): Promise<number> {
    await testApp.listen(0);
    return (testApp.getHttpServer().address() as AddressInfo).port;
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

  function once<T>(
    client: ClientSocket,
    event: string,
    timeoutMs = 15000,
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

  /** Short Stage 6 timings for this spec (still config-driven). */
  async function setShortConfig(
    turn = 2,
    grace = 3,
    missed = 3,
  ): Promise<void> {
    await ds.query(
      `UPDATE "game_configurations"
          SET "turn_timer_seconds" = $1, "grace_period_seconds" = $2,
              "missed_turn_limit" = $3
        WHERE "version" = '1.0.0'`,
      [turn, grace, missed],
    );
  }

  async function countEvents(matchId: string, type?: string): Promise<number> {
    const rows = await ds.query(
      `SELECT COUNT(*) AS "n" FROM "move_events" WHERE "match_id" = $1` +
        (type ? ` AND "type" = $2` : ''),
      type ? [matchId, type] : [matchId],
    );
    return Number(rows[0].n);
  }

  async function matchStatus(
    matchId: string,
  ): Promise<{ status: string; winnerId: string | null }> {
    const rows = await ds.query(
      `SELECT "status", "winner_id" AS "winnerId" FROM "matches" WHERE "id" = $1`,
      [matchId],
    );
    return rows[0];
  }

  beforeAll(async () => {
    ({ name: dbName, url: databaseUrl } = await createScratchDb());
    await migrateScratchDb(databaseUrl);
    ({ app, roller } = await bootGameApp(databaseUrl));
    port = await listenOn(app);
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
    if (cleaner) await cleaner.clear();
    if (cleaner) await cleaner.quit();
    if (app) await app.close();
    if (dbName) await dropScratchDb(dbName);
  });

  beforeEach(async () => {
    await cleaner.clear();
    mailer.clear();
    await redis.del(REDIS_KEYS.matchmakingQueue);
    await setShortConfig();
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

  it('disconnect mid-turn → player:disconnected → reconnect → same state → play continues', async () => {
    // A 5 s turn here: the disconnect/reconnect round-trip must
    // finish before the timer fires, or the auto-play moves first.
    await setShortConfig(5, 3, 3);
    const { matchId, host, guest, hostSocket, guestSocket } =
      await startMatch();
    roller.reseed([6]);
    // Baseline: the match is at seq 1, host to move.
    const before = await api()
      .get(`/v1/matches/${matchId}/state`)
      .set(auth(host.accessToken));
    expect(before.status).toBe(200);
    expect(before.body.data.seq).toBe(1);
    expect(before.body.data.turn.playerId).toBe(host.userId);
    expect(before.body.data.turn.turnEndsAt).not.toBeNull();
    // Host drops mid-turn; the guest hears it with a grace deadline.
    const guestSeesDisconnect = once<{
      matchId: string;
      playerId: string;
      graceEndsAt: string;
      seq: number;
    }>(guestSocket, 'player:disconnected');
    hostSocket.disconnect();
    const disconnected = await guestSeesDisconnect;
    expect(disconnected.matchId).toBe(matchId);
    expect(disconnected.playerId).toBe(host.userId);
    expect(Date.parse(disconnected.graceEndsAt)).toBeGreaterThan(Date.now());
    expect(disconnected.seq).toBe(1);
    // Host reconnects on a fresh socket; the guest hears it, and
    // the host gets the persisted state — same seq, same turn.
    const guestSeesReconnect = once<{
      matchId: string;
      playerId: string;
    }>(guestSocket, 'player:reconnected');
    const hostReconnected = await connect(host.accessToken);
    await guestSeesReconnect;
    const state = once<{
      matchId: string;
      seq: number;
      snapshot: { currentPlayerIndex: number; phase: string };
      turn: { playerId: string; turnEndsAt: string };
    }>(hostReconnected.client, 'match:state');
    hostReconnected.client.emit('state:request', { matchId, lastSeq: 1 });
    const snapshot = await state;
    expect(snapshot.matchId).toBe(matchId);
    expect(snapshot.seq).toBe(1);
    expect(snapshot.snapshot.currentPlayerIndex).toBe(0);
    expect(snapshot.snapshot.phase).toBe('awaitingRoll');
    expect(snapshot.turn.playerId).toBe(host.userId);
    expect(Date.parse(snapshot.turn.turnEndsAt)).toBeGreaterThan(Date.now());
    // Play continues from the reconnected socket.
    const hostRolled = once<{ value: number; seq: number }>(
      hostReconnected.client,
      'dice:rolled',
    );
    const guestRolled = once<{ value: number; seq: number }>(
      guestSocket,
      'dice:rolled',
    );
    hostReconnected.client.emit('dice:roll', {
      matchId,
      requestId: randomUUID(),
    });
    expect((await hostRolled).value).toBe(6);
    expect((await guestRolled).value).toBe(6);
    // The guest never saw a forfeit.
    expect(await collectFor(guestSocket, 'player:forfeited', 500)).toHaveLength(
      0,
    );
    void guest;
  });

  it('grace expiry forfeits; the sole remaining player wins', async () => {
    const { matchId, host, guest, hostSocket, guestSocket } =
      await startMatch();
    roller.reseed([2]);
    const guestSeesDisconnect = once<{ playerId: string }>(
      guestSocket,
      'player:disconnected',
    );
    hostSocket.disconnect();
    expect((await guestSeesDisconnect).playerId).toBe(host.userId);
    // Grace is 3 s; the host's 2 s turn times out first (one miss),
    // then the grace sweep forfeits — either order ends the same.
    const forfeited = once<{ matchId: string; playerId: string }>(
      guestSocket,
      'player:forfeited',
    );
    const ended = once<{ matchId: string; winnerId: string }>(
      guestSocket,
      'match:ended',
    );
    expect((await forfeited).playerId).toBe(host.userId);
    const end = await ended;
    expect(end.matchId).toBe(matchId);
    expect(end.winnerId).toBe(guest.userId);
    expect((await matchStatus(matchId)).status).toBe('completed');
    const rows = await ds.query(
      `SELECT "result" FROM "match_players" WHERE "match_id" = $1 AND "user_id" = $2`,
      [matchId, host.userId],
    );
    expect(rows[0].result).toBe('forfeit');
  });

  it('3 missed turns forfeit the player (both idle)', async () => {
    const { matchId, host, guest, guestSocket } = await startMatch();
    roller.reseed([2]); // never a legal move while all tokens yarded
    const forfeits: Array<{ playerId: string }> = [];
    guestSocket.on('player:forfeited', (data) =>
      forfeits.push(data as { playerId: string }),
    );
    const ended = once<{ winnerId: string }>(guestSocket, 'match:ended');
    // Host misses at ~2 s, guest at ~4 s, host ~6 s, guest ~8 s,
    // host's 3rd miss at ~10 s → forfeit, guest wins.
    const end = await ended;
    expect(end.winnerId).toBe(guest.userId);
    expect(forfeits.map((f) => f.playerId)).toEqual([host.userId]);
    const rows = await ds.query(
      `SELECT "user_id" AS "userId", "missed_turns" AS "missedTurns", "result"
         FROM "match_players" WHERE "match_id" = $1 ORDER BY "seat"`,
      [matchId],
    );
    expect(rows[0]).toEqual(
      expect.objectContaining({
        userId: host.userId,
        missedTurns: 3,
        result: 'forfeit',
      }),
    );
    expect(rows[1]).toEqual(
      expect.objectContaining({
        userId: guest.userId,
        missedTurns: 2,
        result: 'win',
      }),
    );
  });

  it('voluntary leave mid-match forfeits the leaver', async () => {
    const { matchId, roomId, host, guest, hostSocket, guestSocket } =
      await startMatch();
    const forfeited = once<{ playerId: string }>(
      guestSocket,
      'player:forfeited',
    );
    const ended = once<{ winnerId: string }>(guestSocket, 'match:ended');
    hostSocket.emit('room:leave', { roomId });
    expect((await forfeited).playerId).toBe(host.userId);
    expect((await ended).winnerId).toBe(guest.userId);
    expect((await matchStatus(matchId)).winnerId).toBe(guest.userId);
    void guest;
  });

  it('timer expiry auto-rolls and auto-moves the FIRST legal move', async () => {
    const { matchId, host, guestSocket } = await startMatch();
    roller.reseed([6]);
    const guestRolled = once<{ value: number; seq: number }>(
      guestSocket,
      'dice:rolled',
    );
    const guestMoved = once<{
      tokenId: string;
      landing: { kind: string; index: number };
      seq: number;
      turn: { playerId: string; turnEndsAt: string };
    }>(guestSocket, 'token:moved');
    const rolled = await guestRolled;
    expect(rolled.value).toBe(6);
    expect(rolled.seq).toBe(2);
    const moved = await guestMoved;
    // First legal move in engine order: token 0 releases.
    expect(moved.tokenId).toBe('0:0');
    expect(moved.landing).toEqual({ kind: 'track', index: 0 });
    expect(moved.seq).toBe(3);
    expect(moved.turn.playerId).toBe(host.userId); // extra turn
    expect(Date.parse(moved.turn.turnEndsAt)).toBeGreaterThan(Date.now());
    const state = await api()
      .get(`/v1/matches/${matchId}/state`)
      .set(auth(host.accessToken));
    expect(
      snapshotTokenSteps(
        state.body.data.snapshot as Record<string, unknown>,
        0,
        0,
      ),
    ).toBe(1);
  });

  it('timer expiry with no legal move skips the turn, exactly once', async () => {
    const { matchId, host, guest, hostSocket, guestSocket } =
      await startMatch();
    roller.reseed([2]);
    const guestRolled = once<{ value: number; seq: number }>(
      guestSocket,
      'dice:rolled',
    );
    const guestTurn = once<{
      playerId: string;
      turnEndsAt: string;
      seq: number;
    }>(guestSocket, 'turn:changed');
    const noMoves = collectFor(guestSocket, 'token:moved', 6000);
    expect((await guestRolled).value).toBe(2);
    const turned = await guestTurn;
    expect(turned.playerId).toBe(guest.userId);
    expect(Date.parse(turned.turnEndsAt)).toBeGreaterThan(Date.now());
    // The guest's own 2 s turn also times out: exactly one more
    // roll (seq 4), still no moves — no duplicate timeout rows.
    const hostTurn = once<{ playerId: string }>(hostSocket, 'turn:changed');
    expect((await hostTurn).playerId).toBe(host.userId);
    expect(await noMoves).toHaveLength(0);
    expect(await countEvents(matchId, 'dice_rolled')).toBe(2);
    expect(await countEvents(matchId, 'token_moved')).toBe(0);
    void guest;
  });

  it('reconnect to a finished match returns the final state; non-members are rejected', async () => {
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
    const ended = once<{ winnerId: string; seq: number }>(
      hostSocket,
      'match:ended',
    );
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    await once(hostSocket, 'dice:rolled');
    hostSocket.emit('token:move', {
      matchId,
      tokenId: `0:${winningToken}`,
      requestId: randomUUID(),
    });
    const end = await ended;
    expect(end.winnerId).toBe(host.userId);
    // Reconnect (fresh socket) to the finished match: final state.
    const fresh = await connect(host.accessToken);
    const state = once<{
      matchId: string;
      seq: number;
      snapshot: { phase: string; winnerIndex: number };
      turn: { playerId: string | null; turnEndsAt: string | null };
    }>(fresh.client, 'match:state');
    fresh.client.emit('state:request', { matchId, lastSeq: end.seq });
    const snapshot = await state;
    expect(snapshot.seq).toBe(end.seq);
    expect(snapshot.snapshot.phase).toBe('finished');
    expect(snapshot.snapshot.winnerIndex).toBe(0);
    expect(snapshot.turn.playerId).toBeNull();
    expect(snapshot.turn.turnEndsAt).toBeNull();
    const rest = await api()
      .get(`/v1/matches/${matchId}`)
      .set(auth(host.accessToken));
    expect(rest.status).toBe(200);
    expect(rest.body.data.status).toBe('completed');
    expect(rest.body.data.winnerId).toBe(host.userId);
    // A non-member cannot read state over either transport.
    const stranger = await verifiedAccessToken();
    const strangerSocket = (await connect(stranger.accessToken)).client;
    const rejected = once<{ code: string }>(strangerSocket, 'action:rejected');
    strangerSocket.emit('state:request', { matchId, lastSeq: 0 });
    expect((await rejected).code).toBe('NOT_MATCH_PLAYER');
    const restDenied = await api()
      .get(`/v1/matches/${matchId}/state`)
      .set(auth(stranger.accessToken));
    expect(restDenied.status).toBe(403);
    expect(restDenied.body.error.code).toBe('NOT_MATCH_PLAYER');
    void guestSocket;
  });

  it('restart restores an in-progress match and cancels a corrupt one', async () => {
    // Long timers here so no auto-play fires across the restart.
    await setShortConfig(30, 60, 3);
    const { matchId, host, guest, hostSocket, guestSocket } =
      await startMatch();
    roller.reseed([6]);
    const rolled = once<{ value: number }>(hostSocket, 'dice:rolled');
    hostSocket.emit('dice:roll', { matchId, requestId: randomUUID() });
    expect((await rolled).value).toBe(6);
    const moved = once<{ tokenId: string }>(hostSocket, 'token:moved');
    hostSocket.emit('token:move', {
      matchId,
      tokenId: '0:0',
      requestId: randomUUID(),
    });
    expect((await moved).tokenId).toBe('0:0');
    const before = await api()
      .get(`/v1/matches/${matchId}/state`)
      .set(auth(host.accessToken));
    expect(before.body.data.seq).toBe(3);
    expect(
      snapshotTokenSteps(
        before.body.data.snapshot as Record<string, unknown>,
        0,
        0,
      ),
    ).toBe(1);
    // A second match whose log is corrupt (bad dice value).
    const bad = await startMatch();
    await ds.query(
      `INSERT INTO "move_events"
         ("match_id", "seq_no", "actor_id", "type", "payload", "request_id")
       VALUES ($1, 2, NULL, 'dice_rolled', '{"value": 99}'::jsonb, NULL)`,
      [bad.matchId],
    );
    // Stop the server mid-match, then restart on the same DB.
    for (const client of clients.splice(0)) {
      try {
        client.disconnect();
      } catch {
        // Already gone.
      }
    }
    await app.close();
    ({ app, roller } = await bootGameApp(databaseUrl));
    port = await listenOn(app);
    ds = app.get(DataSource);
    mailer = app.get(LogMailerService);
    await setShortConfig(30, 60, 3);
    // The good match is restored with the same state; the corrupt
    // one is cleanly cancelled, never resumed corrupted.
    const after = await api()
      .get(`/v1/matches/${matchId}/state`)
      .set(auth(host.accessToken));
    expect(after.status).toBe(200);
    expect(after.body.data.seq).toBe(3);
    expect(
      snapshotTokenSteps(
        after.body.data.snapshot as Record<string, unknown>,
        0,
        0,
      ),
    ).toBe(1);
    expect(after.body.data.turn.playerId).toBe(host.userId);
    const badStatus = await matchStatus(bad.matchId);
    expect(badStatus.status).toBe('cancelled');
    // Play continues on the restored match (reconnect + roll).
    roller.reseed([6]);
    const hostConn = (await connect(host.accessToken)).client;
    const guestConn = (await connect(guest.accessToken)).client;
    const state = once<{ seq: number }>(hostConn, 'match:state');
    hostConn.emit('state:request', { matchId, lastSeq: 3 });
    expect((await state).seq).toBe(3);
    // The guest's fresh socket must resubscribe too (state:request
    // joins it to the match room) before it can hear broadcasts.
    const guestState = once<{ seq: number }>(guestConn, 'match:state');
    guestConn.emit('state:request', { matchId, lastSeq: 3 });
    expect((await guestState).seq).toBe(3);
    const guestRolled = once<{ value: number; seq: number }>(
      guestConn,
      'dice:rolled',
    );
    hostConn.emit('dice:roll', { matchId, requestId: randomUUID() });
    const roll = await guestRolled;
    expect(roll.value).toBe(6);
    expect(roll.seq).toBe(4);
    void guestSocket;
  });
});
