/**
 * DiceUp Phase 5 — Stage 8 load / concurrency harness (NFR-05/06/24).
 *
 * Drives REAL clients against a running dev server (default
 * http://127.0.0.1:3000): seeded verified users log in over HTTP,
 * connect to /game with socket.io-client, create/join rooms, start
 * matches and play rolls/moves, while the harness records connected
 * clients, match:started rate, intent round-trip latency (p50/p95)
 * and error/rejected/429 rates at each ramp step.
 *
 * Run from backend/:
 *   node test/load/load-test.js [--steps 50,100,250,500] [--rolls 2]
 *                               [--base-url http://127.0.0.1:3000]
 *                               [--checks-only] [--run-id stage8]
 *
 * What it does NOT do (deliberate, documented):
 * - Register -> verify is NOT driven end-to-end: verification tokens
 *   are never logged and never leave the server (by design), so an
 *   external harness cannot complete verify-email. Users are seeded
 *   directly in the live scratch DB instead (verified, Argon2id hash
 *   of one shared load password, same params as PasswordHasherService).
 *   Register itself is smoke-tested (a few POSTs, latency + status);
 *   register -> verify -> login is covered by the e2e suite.
 * - The 120/min/IP socket-connection limit (L-02) is a deliberate
 *   product control. All load clients come from 127.0.0.1, so the
 *   harness clears the `ratelimit:socket-conn-ip:127.0.0.1:1m` bucket
 *   between connect waves and says so in its output. Without the
 *   clears, connects past 120/min would be refused by design.
 * - Rows created in the live scratch DB (users, rooms, matches,
 *   move_events) are LEFT in place; the Flutter gate truncates the
 *   live tables before its run.
 *
 * Exit code 0 = every concurrency check passed (ramp steps never
 * fail the run on latency alone — they report); 1 = a check failed.
 */
'use strict';

const { randomUUID } = require('node:crypto');
const { execSync } = require('node:child_process');
const os = require('node:os');
const path = require('node:path');
const { Client } = require('pg');
const argon2 = require('argon2');
const Redis = require('ioredis');
const { io } = require('socket.io-client');

require('dotenv').config({ path: path.resolve(__dirname, '..', '..', '.env') });

const LOAD_PASSWORD = 'LoadPass!1';
const CONNECT_TIMEOUT_MS = 10000;
const EVENT_TIMEOUT_MS = 15000;
const CONNECT_WAVE = 100; // stay under the 120/min/IP product limit
const LOGIN_CONCURRENCY = 20;

function parseArgs(argv) {
  const out = {
    steps: [50, 100, 250, 500],
    rolls: 2,
    baseUrl: process.env.LOAD_BASE_URL || 'http://127.0.0.1:3000',
    runId: Date.now().toString(36),
    checksOnly: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--steps') out.steps = argv[i + 1].split(',').map(Number);
    if (a === '--rolls') out.rolls = Number(argv[i + 1]);
    if (a === '--base-url') out.baseUrl = argv[i + 1];
    if (a === '--run-id') out.runId = argv[i + 1];
    if (a === '--checks-only') out.checksOnly = true;
  }
  return out;
}

function percentile(sorted, p) {
  if (sorted.length === 0) return null;
  const idx = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[Math.max(0, idx)];
}

function stats(latencies) {
  const sorted = [...latencies].sort((a, b) => a - b);
  return {
    n: sorted.length,
    p50: percentile(sorted, 50),
    p95: percentile(sorted, 95),
    max: sorted.length ? sorted[sorted.length - 1] : null,
  };
}

async function mapLimit(items, limit, fn) {
  const results = new Array(items.length);
  let next = 0;
  const workers = new Array(Math.min(limit, items.length)).fill(null).map(async () => {
    while (next < items.length) {
      const i = next;
      next += 1;
      results[i] = await fn(items[i], i);
    }
  });
  await Promise.all(workers);
  return results;
}

function once(socket, event, timeoutMs = EVENT_TIMEOUT_MS) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error(`timed out waiting for '${event}'`));
    }, timeoutMs);
    socket.once(event, (data) => {
      clearTimeout(timer);
      resolve(data);
    });
  });
}

/** First of several events wins; the losers' listeners are removed. */
function firstOf(socket, events, timeoutMs = EVENT_TIMEOUT_MS) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(`timed out waiting for one of [${events.join(', ')}]`));
    }, timeoutMs);
    const handlers = new Map();
    const cleanup = () => {
      clearTimeout(timer);
      for (const [event, handler] of handlers) socket.off(event, handler);
    };
    for (const event of events) {
      const handler = (data) => {
        cleanup();
        resolve({ event, data });
      };
      handlers.set(event, handler);
      socket.once(event, handler);
    }
  });
}

async function httpJson(baseUrl, method, pathName, body, token) {
  const res = await fetch(`${baseUrl}${pathName}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let parsed = null;
  try {
    parsed = await res.json();
  } catch {
    parsed = null;
  }
  return { status: res.status, body: parsed };
}

class LoadClient {
  constructor(email, userId) {
    this.email = email;
    this.userId = userId;
    this.token = null;
    this.socket = null;
  }

  async login(baseUrl) {
    const t0 = Date.now();
    const res = await httpJson(baseUrl, 'POST', '/v1/auth/login', {
      identifier: this.email,
      password: LOAD_PASSWORD,
    });
    const ms = Date.now() - t0;
    if (res.status !== 200) {
      throw new Error(`login failed for ${this.email}: ${res.status}`);
    }
    this.token = res.body.data.tokens.accessToken;
    return ms;
  }

  async connect(baseUrl) {
    return new Promise((resolve, reject) => {
      const socket = io(`${baseUrl}/game`, {
        auth: { token: this.token },
        reconnection: false,
        timeout: CONNECT_TIMEOUT_MS,
      });
      this.socket = socket;
      const connected = once(socket, 'connected', CONNECT_TIMEOUT_MS);
      connected.catch(() => undefined);
      socket.once('connect', () => resolve(connected));
      socket.once('connect_error', (err) => reject(err));
    });
  }

  disconnect() {
    try {
      this.socket?.disconnect();
    } catch {
      // Already gone.
    }
    this.socket = null;
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const { baseUrl } = args;
  const startedAt = Date.now();
  const report = {
    baseUrl,
    runId: args.runId,
    steps: args.steps,
    rollsPerMatch: args.rolls,
    startedAt: new Date(startedAt).toISOString(),
    checks: {},
    registerSmoke: null,
    startedAtZSuffixLive: null,
    ramp: [],
    settleWaits: [],
  };

  const dbUrl = process.env.DATABASE_URL;
  if (!dbUrl) throw new Error('DATABASE_URL is not set (backend/.env)');
  const redisUrl = process.env.REDIS_URL || 'redis://127.0.0.1:6379';
  const pg = new Client({ connectionString: dbUrl });
  await pg.connect();
  const redis = new Redis(redisUrl, { lazyConnect: true, maxRetriesPerRequest: 3 });
  await redis.connect();

  const serverPid = (() => {
    try {
      // -x: exact command-line match. A plain -f also matches stale
      // shells whose command line merely CONTAINS "node dist/main.js"
      // (e.g. the shell that started the server) and reports garbage
      // CPU/RSS for them.
      return execSync('pgrep -xf "node dist/main.js" | head -1', { encoding: 'utf8' }).trim();
    } catch {
      return null;
    }
  })();

  const serverStats = () => {
    if (!serverPid) return { pid: null };
    try {
      const out = execSync(`ps -o %cpu=,rss= -p ${serverPid}`, { encoding: 'utf8' })
        .trim()
        .split(/\s+/);
      return { pid: Number(serverPid), cpuPct: Number(out[0]), rssKiB: Number(out[1]) };
    } catch {
      return { pid: Number(serverPid), cpuPct: null, rssKiB: null };
    }
  };

  async function clearRateLimits() {
    const keys = await redis.keys('ratelimit:*');
    if (keys.length > 0) await redis.del(...keys);
    await redis.del('matchmaking:queue');
    return keys.length;
  }

  // Ramp users are single-use within a run (a user that already owns
  // a room gets 409 ALREADY_IN_ROOM on create), so the run needs the
  // SUM of the steps, not the max. Check/probe users are seeded under
  // a timestamped namespace so they are fresh even when the run reuses
  // a --run-id whose ramp users already own rooms.
  const rampUsers = args.steps.reduce((a, b) => a + b, 0);
  const checkUsers = 18; // (a) 0-1, (b) 2-3, (c) host 4 + 10 contenders, probe 15-16, spare 17
  const totalUsers = rampUsers + checkUsers;

  // -- Seed verified users (one shared Argon2id hash, same params as
  // PasswordHasherService: argon2id, 64 MiB, 3 iterations, p=1).
  process.stdout.write(`seeding ${totalUsers} verified users ... `);
  const hash = await argon2.hash(LOAD_PASSWORD, {
    type: argon2.argon2id,
    memoryCost: 64 * 1024,
    timeCost: 3,
    parallelism: 1,
  });
  const seedValues = [];
  for (let i = 0; i < rampUsers; i += 1) {
    seedValues.push(`('load_${args.runId}_${i}@example.com', 'load_${args.runId}_${i}', '${hash}', 'active', now(), now(), now())`);
  }
  const chkTag = `${args.runId}_chk_${Date.now().toString(36)}`;
  for (let i = 0; i < checkUsers; i += 1) {
    seedValues.push(`('load_${chkTag}_${i}@example.com', 'load_${chkTag}_${i}', '${hash}', 'active', now(), now(), now())`);
  }
  await pg.query(
    `INSERT INTO users (email, username, password_hash, status, email_verified_at, created_at, updated_at)
     VALUES ${seedValues.join(', ')}
     ON CONFLICT (email) DO NOTHING`,
  );
  const { rows: userRows } = await pg.query(
    `SELECT id, email FROM users WHERE email LIKE 'load_${args.runId}_%@example.com' ORDER BY email`,
  );
  if (userRows.length < totalUsers) {
    throw new Error(`seeded only ${userRows.length}/${totalUsers} users`);
  }
  console.log(`ok (${userRows.length})`);

  const rampClients = userRows
    .filter((r) => !r.email.includes('_chk_'))
    .map((r) => new LoadClient(r.email, r.id));
  const checkClients = userRows
    .filter((r) => r.email.includes('_chk_'))
    .map((r) => new LoadClient(r.email, r.id));
  if (rampClients.length < rampUsers || checkClients.length < checkUsers) {
    throw new Error(
      `seed split wrong: ramp ${rampClients.length}/${rampUsers}, check ${checkClients.length}/${checkUsers}`,
    );
  }
  const clients = rampClients;

  const errors = [];
  const recordError = (where, err) => {
    errors.push({ where, message: String(err?.message ?? err) });
  };

  // -- Register smoke: a few real registers (latency + status only;
  // verification cannot be completed externally — see header).
  await clearRateLimits();
  {
    const latencies = [];
    let ok = 0;
    const regTag = `${args.runId}_${Date.now().toString(36)}`;
    for (let i = 0; i < 5; i += 1) {
      const t0 = Date.now();
      const res = await httpJson(baseUrl, 'POST', '/v1/auth/register', {
        email: `loadreg_${regTag}_${i}@example.com`,
        username: `loadreg_${regTag}_${i}`,
        password: LOAD_PASSWORD,
        displayName: `Load Reg ${i}`,
      });
      latencies.push(Date.now() - t0);
      if (res.status === 201) ok += 1;
      else recordError('register-smoke', `status ${res.status}`);
    }
    report.registerSmoke = { attempted: 5, created: ok, latencyMs: stats(latencies) };
    console.log(`register smoke: ${ok}/5 created, p50 ${stats(latencies).p50}ms`);
  }
  await clearRateLimits();

  // -- Log in + connect, in waves (see header re: the 120/min/IP limit).
  const allLatencies = { login: [], connect: [] };
  async function loginAndConnect(pool, label) {
    const t0 = Date.now();
    await mapLimit(pool, LOGIN_CONCURRENCY, async (c) => {
      try {
        allLatencies.login.push(await c.login(baseUrl));
      } catch (err) {
        recordError(`${label}:login`, err);
      }
    });
    const waves = [];
    for (let i = 0; i < pool.length; i += CONNECT_WAVE) {
      waves.push(pool.slice(i, i + CONNECT_WAVE));
    }
    let waveNo = 0;
    for (const wave of waves) {
      waveNo += 1;
      if (waveNo > 1) {
        // Product limit is 120/min/IP; clear the bucket between waves.
        await redis.del('ratelimit:socket-conn-ip:127.0.0.1:1m');
      }
      await mapLimit(wave, CONNECT_WAVE, async (c) => {
        const s0 = Date.now();
        try {
          await c.connect(baseUrl);
          allLatencies.connect.push(Date.now() - s0);
        } catch (err) {
          recordError(`${label}:connect`, err);
        }
      });
    }
    console.log(`${label}: ${pool.length} clients in ${Date.now() - t0}ms`);
    return pool.filter((c) => c.socket?.connected);
  }

  async function createRoom(host) {
    const res = await httpJson(baseUrl, 'POST', '/v1/rooms', { maxPlayers: 2 }, host.token);
    if (res.status !== 201) throw new Error(`create room: ${res.status}`);
    return { id: res.body.data.id, code: res.body.data.code };
  }

  async function joinRoom(client, code) {
    const updated = once(client.socket, 'room:updated');
    client.socket.emit('room:join', { roomCode: code });
    return updated;
  }

  async function setReady(client, watcher, roomId, ready) {
    const updated = once(watcher.socket, 'room:updated');
    client.socket.emit('room:ready', { roomId, ready });
    return updated;
  }

  async function startMatchPair(host, guest) {
    const room = await createRoom(host);
    await joinRoom(host, room.code);
    await joinRoom(guest, room.code);
    await setReady(guest, host, room.id, true);
    await setReady(host, guest, room.id, true);
    const hostStarted = once(host.socket, 'match:started');
    const guestStarted = once(guest.socket, 'match:started');
    host.socket.emit('match:start', { roomId: room.id });
    const started = await hostStarted;
    await guestStarted;
    return { matchId: started.matchId, roomId: room.id };
  }

  async function requestState(client, matchId, lastSeq) {
    const t0 = Date.now();
    const state = once(client.socket, 'match:state');
    client.socket.emit('state:request', { matchId, lastSeq: lastSeq ?? 0 });
    const payload = await state;
    return { payload, ms: Date.now() - t0 };
  }

  /** One roll (+ optional move) by the player to move. Returns latencies. */
  async function playOneTurn(match, seats) {
    const latencies = [];
    const { payload: state } = await requestState(match.players[0], match.matchId, match.seq);
    const snapshot = state.snapshot;
    match.seq = state.seq;
    if (snapshot.phase === 'finished') return { latencies, finished: true };
    const currentSeat = snapshot.currentPlayerIndex;
    const actor = match.players[currentSeat];
    const requestId = randomUUID();
    const t0 = Date.now();
    const rolled = once(actor.socket, 'dice:rolled');
    actor.socket.emit('dice:roll', { matchId: match.matchId, requestId });
    const dice = await rolled;
    latencies.push(Date.now() - t0);
    match.seq = dice.seq;
    const after = await requestState(actor, match.matchId, match.seq);
    const afterSnapshot = after.payload.snapshot;
    match.seq = after.payload.seq;
    if (afterSnapshot.phase === 'awaitingMove') {
      const seat = afterSnapshot.currentPlayerIndex;
      const mover = match.players[seat];
      const moved = await moveWithRetries(mover, match, seat, latencies);
      if (!moved) recordError('play:move', `no legal token moved in ${match.matchId}`);
    }
    return { latencies, finished: afterSnapshot.phase === 'finished' };
  }

  async function moveWithRetries(mover, match, seat, latencies) {
    for (let token = 0; token < 4; token += 1) {
      const moveId = randomUUID();
      const t0 = Date.now();
      const movedPromise = once(mover.socket, 'token:moved');
      const rejectedPromise = once(mover.socket, 'action:rejected');
      mover.socket.emit('token:move', {
        matchId: match.matchId,
        tokenId: `${seat}:${token}`,
        requestId: moveId,
      });
      const winner = await Promise.race([
        movedPromise.then((p) => ({ kind: 'moved', payload: p })),
        rejectedPromise.then((p) => ({ kind: 'rejected', payload: p })),
      ]);
      if (winner.kind === 'moved') {
        latencies.push(Date.now() - t0);
        match.seq = winner.payload.seq;
        return true;
      }
      // Illegal token for this roll — try the next one.
    }
    return false;
  }

  // -- Concurrency checks (small scale, before the ramp).
  async function settle(label, timeoutMs = 180000) {
    const settleStart = Date.now();
    let remaining = -1;
    while (Date.now() - settleStart < timeoutMs) {
      const { rows } = await pg.query(
        "SELECT count(*)::int AS n FROM matches WHERE status = 'in_progress'",
      );
      remaining = rows[0].n;
      if (remaining === 0) break;
      await new Promise((r) => setTimeout(r, 5000));
    }
    return { afterStep: label, waitedMs: Date.now() - settleStart, remainingInProgress: remaining };
  }

  async function runConcurrencyChecks() {
    console.log('concurrency checks ...');
    const pool = checkClients;
    const connected = await loginAndConnect(pool, 'checks');
    if (connected.length < 16) {
      report.checks.setup = { pass: false, detail: `only ${connected.length}/16 check clients connected` };
      return false;
    }
    let allPass = true;

    // (a) Duplicate requestId replay: roll + move return the original
    // result, no second transition (FR-53).
    try {
      const [host, guest] = connected;
      const { matchId } = await startMatchPair(host, guest);
      const rollId = randomUUID();
      const first = once(host.socket, 'dice:rolled');
      const guestFirst = once(guest.socket, 'dice:rolled');
      host.socket.emit('dice:roll', { matchId, requestId: rollId });
      const rolled = await first;
      await guestFirst;
      const dup = once(host.socket, 'dice:rolled');
      host.socket.emit('dice:roll', { matchId, requestId: rollId });
      const repeated = await dup;
      const { rows: rollRows } = await pg.query(
        "SELECT count(*)::int AS n FROM move_events WHERE match_id = $1 AND type = 'dice_rolled'",
        [matchId],
      );
      const rollOk = JSON.stringify(repeated) === JSON.stringify(rolled) && rollRows[0].n === 1;
      // Move replay, same requestId.
      const { payload: st } = await requestState(host, matchId, rolled.seq);
      let moveOk = true;
      if (st.snapshot.phase === 'awaitingMove') {
        const seat = st.snapshot.currentPlayerIndex;
        const mover = seat === 0 ? host : guest;
        const moveId = randomUUID();
        const firstMove = once(mover.socket, 'token:moved');
        mover.socket.emit('token:move', { matchId, tokenId: `${seat}:0`, requestId: moveId });
        let moved;
        try {
          moved = await firstMove;
        } catch {
          // Token 0 may be illegal for this roll; try the next token.
          const retry = once(mover.socket, 'token:moved');
          mover.socket.emit('token:move', { matchId, tokenId: `${seat}:1`, requestId: moveId });
          moved = await retry;
        }
        const dupMove = once(mover.socket, 'token:moved');
        mover.socket.emit('token:move', { matchId, tokenId: moved.tokenId, requestId: moveId });
        const repeatedMove = await dupMove;
        const { rows: moveRows } = await pg.query(
          "SELECT count(*)::int AS n FROM move_events WHERE match_id = $1 AND type = 'token_moved'",
          [matchId],
        );
        moveOk = JSON.stringify(repeatedMove) === JSON.stringify(moved) && moveRows[0].n === 1;
      }
      report.checks.duplicateRequestId = { pass: rollOk && moveOk, detail: `roll replay identical=${rollOk}, move replay identical=${moveOk}` };
      if (!rollOk || !moveOk) allPass = false;
    } catch (err) {
      report.checks.duplicateRequestId = { pass: false, detail: String(err?.message ?? err) };
      allPass = false;
    }

    // (b) Simultaneous intents: two rolls at once, exactly one wins.
    try {
      const [host, guest] = connected.slice(2, 4);
      const { matchId } = await startMatchPair(host, guest);
      const rolled = once(host.socket, 'dice:rolled');
      const rejected = once(host.socket, 'action:rejected');
      host.socket.emit('dice:roll', { matchId, requestId: randomUUID() });
      host.socket.emit('dice:roll', { matchId, requestId: randomUUID() });
      const got = await rolled;
      const rej = await rejected;
      const { rows } = await pg.query(
        "SELECT count(*)::int AS n FROM move_events WHERE match_id = $1 AND type = 'dice_rolled'",
        [matchId],
      );
      // Live dice are random (unlike the seeded e2e roller): the
      // loser's rejection is INVALID_STATE when the winner's roll left
      // the turn with the roller (awaitingMove) and NOT_YOUR_TURN when
      // the roll passed the turn. Either way exactly one transition
      // happened and the loser was rejected.
      const pass =
        rows[0].n === 1 &&
        (rej.code === 'INVALID_STATE' || rej.code === 'NOT_YOUR_TURN') &&
        got.seq === 2;
      report.checks.simultaneousIntents = { pass, detail: `dice_rolled rows=${rows[0].n}, rejected=${rej.code}, seq=${got.seq}` };
      if (!pass) allPass = false;
    } catch (err) {
      report.checks.simultaneousIntents = { pass: false, detail: String(err?.message ?? err) };
      allPass = false;
    }

    // (c) 10 concurrent joins on the last seat: exactly 1 wins.
    try {
      const host = connected[4];
      const contenders = connected.slice(5, 15);
      const room = await createRoom(host);
      await joinRoom(host, room.code);
      // Register every waiter's listener BEFORE any emit, then emit
      // all ten joins together: the race is genuinely concurrent.
      const waiters = contenders.map((c) =>
        firstOf(c.socket, ['room:updated', 'exception']),
      );
      for (const c of contenders) c.socket.emit('room:join', { roomCode: room.code });
      const outcomes = await Promise.all(waiters);
      const wins = outcomes.filter((o) => o.event === 'room:updated');
      const fulls = outcomes.filter(
        (o) => o.event === 'exception' && o.data?.error?.code === 'ROOM_FULL',
      );
      const roomRes = await httpJson(baseUrl, 'GET', `/v1/rooms/${room.id}`, undefined, host.token);
      const members = roomRes.body?.data?.members?.length ?? roomRes.body?.data?.memberCount;
      const pass = wins.length === 1 && fulls.length === 9;
      report.checks.lastSeatRace = {
        pass,
        detail:
          `wins=${wins.length}, ROOM_FULL=${fulls.length}, members=${members}; ` +
          `outcomes=[${outcomes
            .map((o) => `${o.event}:${o.data?.error?.code ?? JSON.stringify(o.data)?.slice(0, 80) ?? '?'}`)
            .join(', ')}]`,
      };
      if (!pass) allPass = false;
    } catch (err) {
      report.checks.lastSeatRace = { pass: false, detail: String(err?.message ?? err) };
      allPass = false;
    }

    for (const c of connected) c.disconnect();
    console.log(`concurrency checks: ${allPass ? 'ALL PASS' : 'FAILURES — see report'}`);
    return allPass;
  }

  const checksPass = await runConcurrencyChecks();
  await clearRateLimits();

  // Live Z-suffix check on the fixed snapshot writer: one real match,
  // read its authoritative snapshot over REST.
  try {
    const probe = [checkClients[15], checkClients[16]];
    const connected = await loginAndConnect(probe, 'probe');
    const { matchId } = await startMatchPair(connected[0], connected[1]);
    const res = await httpJson(baseUrl, 'GET', `/v1/matches/${matchId}/state`, undefined, connected[0].token);
    const startedAtValue = res.body?.data?.snapshot?.startedAt ?? res.body?.data?.state?.snapshot?.startedAt;
    report.startedAtZSuffixLive = {
      value: startedAtValue ?? null,
      zSuffixed: typeof startedAtValue === 'string' && startedAtValue.endsWith('Z'),
    };
    for (const c of connected) c.disconnect();
    console.log(`live snapshot startedAt: ${startedAtValue} (Z=${report.startedAtZSuffixLive.zSuffixed})`);
  } catch (err) {
    report.startedAtZSuffixLive = { value: null, zSuffixed: false, error: String(err?.message ?? err) };
    recordError('probe:startedAt', err);
  }
  // Let the probe match settle (turn timers forfeit absent players)
  // so the ramp measures a quiet server.
  report.settleWaits.push(await settle('probe'));
  await clearRateLimits();

  // -- Ramp (skipped with --checks-only).
  let playerOffset = 0;
  for (const step of args.checksOnly ? [] : args.steps) {
    const pool = clients.slice(playerOffset, playerOffset + step);
    playerOffset += step;
    const stepReport = {
      players: step,
      connected: 0,
      roomsCreated: 0,
      matchesStarted: 0,
      matchStartedRate: null,
      intentLatencyMs: null,
      errors: 0,
      rejected: 0,
      serverBefore: serverStats(),
      serverAfter: null,
      loadAvg: os.loadavg(),
      durationMs: null,
    };
    const t0 = Date.now();
    const connected = await loginAndConnect(pool, `step-${step}`);
    stepReport.connected = connected.length;
    const pairs = [];
    for (let i = 0; i + 1 < connected.length; i += 2) {
      pairs.push([connected[i], connected[i + 1]]);
    }
    const matches = [];
    const startedLatencies = [];
    await mapLimit(pairs, 25, async ([host, guest]) => {
      const s0 = Date.now();
      try {
        const m = await startMatchPair(host, guest);
        startedLatencies.push(Date.now() - s0);
        matches.push({ ...m, players: [host, guest], seq: 1 });
        stepReport.matchesStarted += 1;
      } catch (err) {
        recordError(`step-${step}:start`, err);
      }
    });
    stepReport.roomsCreated = matches.length;
    const intentLatencies = [];
    let rejectedCount = 0;
    const rejectedListener = () => {
      rejectedCount += 1;
    };
    for (const c of connected) c.socket?.on('action:rejected', rejectedListener);
    const playErrorsBefore = errors.length;
    await mapLimit(matches, 50, async (match) => {
      try {
        for (let r = 0; r < args.rolls; r += 1) {
          const { latencies, finished } = await playOneTurn(match, match.players);
          intentLatencies.push(...latencies);
          if (finished) break;
        }
      } catch (err) {
        recordError(`step-${step}:play`, err);
      }
    });
    stepReport.intentLatencyMs = stats(intentLatencies);
    stepReport.matchStartedRate =
      startedLatencies.length > 0
        ? Number((startedLatencies.length / ((Date.now() - t0) / 1000)).toFixed(2))
        : 0;
    stepReport.rejected = rejectedCount;
    stepReport.errors = errors.length - playErrorsBefore;
    stepReport.durationMs = Date.now() - t0;
    for (const c of connected) {
      try {
        c.socket?.off('action:rejected', rejectedListener);
      } catch {
        // ignore
      }
      c.disconnect();
    }
    stepReport.serverAfter = serverStats();
    stepReport.loadAvg = os.loadavg();
    report.ramp.push(stepReport);
    console.log(
      `step ${step}: connected ${stepReport.connected}/${step} matches ${stepReport.matchesStarted} ` +
        `intent p50=${stepReport.intentLatencyMs.p50}ms p95=${stepReport.intentLatencyMs.p95}ms ` +
        `errors=${stepReport.errors} rejected=${stepReport.rejected} (${stepReport.durationMs}ms)`,
    );

    // Let in-progress matches settle (turn timers forfeit absent
    // players) so the next step measures a quiet server.
    report.settleWaits.push(await settle(`step-${step}`));
    await clearRateLimits();
  }

  report.checksPass = checksPass;
  report.errors = errors.slice(0, 20);
  report.errorCount = errors.length;
  report.loginLatencyMs = stats(allLatencies.login);
  report.connectLatencyMs = stats(allLatencies.connect);
  report.finishedAt = new Date().toISOString();
  report.wallMs = Date.now() - startedAt;

  console.log('\n===== LOAD REPORT =====');
  console.log(JSON.stringify(report, null, 2));

  await redis.disconnect();
  await pg.end();
  process.exit(checksPass ? 0 : 1);
}

main().catch((err) => {
  console.error(`load-test fatal: ${err?.stack ?? err}`);
  process.exit(2);
});
