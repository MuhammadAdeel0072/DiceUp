import { AddressInfo } from 'node:net';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { randomUUID } from 'node:crypto';
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { JwtService } from '@nestjs/jwt';
import { DataSource } from 'typeorm';
import * as request from 'supertest';
import { io, type Socket as ClientSocket } from 'socket.io-client';
import Redis from 'ioredis';
import { AppModule } from '../../src/app.module';
import { LogMailerService } from '../../src/mailer/log-mailer.service';
import { REDIS_CLIENT } from '../../src/redis/redis.service';
import { createApp } from './test-app.factory';
import {
  bootTestApp,
  createScratchDb,
  dropScratchDb,
  migrateScratchDb,
  RateLimitCleaner,
  uniqueUser,
} from './test-helpers';

/**
 * Full journey (Stage 3 integration verification, plan §10.3/§12):
 * the whole backend as ONE system, against real PostgreSQL 16 + real
 * Redis 7, on a live server booted from the app (same bootstrap as
 * main.ts via the test-app factory, real HTTP listen on an ephemeral
 * port — the production build `node dist/main` boots the identical
 * AppModule, verified separately in the clean-environment check).
 *
 * One user walks the entire lifecycle in a single test so a break
 * anywhere in the chain fails the journey: register → verify (token
 * from the log-mailer capture) → login → protected GET /users/me →
 * Socket.IO /game connect with the SAME access token → ping/pong →
 * refresh → logout → the OLD access token fails on BOTH REST (401)
 * and socket (connect_error) → refresh-token reuse revokes the whole
 * family. Companion tests cover readiness (deps up / Redis down),
 * the login rate limit firing end-to-end, an expired access token on
 * both transports, and no secrets in the log output.
 *
 * Rate-limit counters are cleared before each test (all supertest
 * traffic comes from one IP by design); the flood test builds its
 * flood inside a single test.
 */
describe('full journey (real PostgreSQL + real Redis, live server)', () => {
  let dbName: string;
  let databaseUrl: string;
  let app: INestApplication;
  let ds: DataSource;
  let mailer: LogMailerService;
  let cleaner: RateLimitCleaner;
  let port: number;
  const clients: ClientSocket[] = [];

  const api = () => request(app.getHttpServer());
  const url = () => `http://127.0.0.1:${port}/game`;

  beforeAll(async () => {
    ({ name: dbName, url: databaseUrl } = await createScratchDb());
    await migrateScratchDb(databaseUrl);
    app = await bootTestApp(databaseUrl);
    await app.listen(0);
    port = (app.getHttpServer().address() as AddressInfo).port;
    ds = app.get(DataSource);
    mailer = app.get(LogMailerService);
    cleaner = new RateLimitCleaner();
  }, 120000);

  afterAll(async () => {
    for (const c of clients) c.disconnect();
    if (cleaner) await cleaner.quit();
    if (app) await app.close();
    if (dbName) await dropScratchDb(dbName);
  });

  beforeEach(async () => {
    await cleaner.clear();
    mailer.clear();
  });

  /** Wait for one event (or reject on timeout). */
  function once<T>(
    client: ClientSocket,
    event: string,
    timeoutMs = 5000,
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

  /**
   * Connect a client; resolves on `connect`, rejects on `connect_error`.
   * The `connected` promise is registered BEFORE the handshake can
   * complete (the server emits `connected` from handleConnection
   * immediately after accepting the socket).
   */
  function connect(auth?: Record<string, unknown>): Promise<{
    client: ClientSocket;
    connected: Promise<{
      userId: string;
      socketId: string;
      connectedAt: string;
    }>;
  }> {
    return new Promise((resolve, reject) => {
      const client = io(url(), {
        auth: auth ?? {},
        reconnection: false,
        timeout: 5000,
      });
      clients.push(client);
      const connected = once<{
        userId: string;
        socketId: string;
        connectedAt: string;
      }>(client, 'connected');
      // A refused handshake never resolves `connected`; swallow its
      // timeout rejection so refusal tests stay clean.
      connected.catch(() => undefined);
      client.once('connect', () => resolve({ client, connected }));
      client.once('connect_error', (err: Error) => {
        reject(err);
      });
    });
  }

  /** Registers, verifies via the captured mail, logs in. */
  async function registerVerified() {
    const u = uniqueUser();
    const reg = await api().post('/v1/auth/register').send(u);
    expect(reg.status).toBe(201);
    const msg = mailer.findLatest(u.email, 'verification');
    expect(msg).toBeDefined();
    const verify = await api()
      .post('/v1/auth/verify-email')
      .send({ token: msg!.token });
    expect(verify.status).toBe(200);
    const login = await api()
      .post('/v1/auth/login')
      .send({ identifier: u.email, password: u.password });
    expect(login.status).toBe(200);
    return {
      u,
      userId: login.body.data.user.id as string,
      accessToken: login.body.data.tokens.accessToken as string,
      refreshToken: login.body.data.tokens.refreshToken as string,
    };
  }

  it('uses the scratch database, never diceup_dev (regression)', async () => {
    // Stage 3 found every e2e suite running against diceup_dev:
    // ConfigService.get('DATABASE_URL') reads the Joi-validated env
    // store, frozen from backend/.env at import time, so the helpers'
    // process.env assignment was silently ignored (523 test users had
    // accumulated in diceup_dev). The app must use the scratch DB
    // this spec created and migrated.
    const url = (ds.options as unknown as { url: string }).url;
    expect(new URL(url).pathname.slice(1)).toBe(dbName);
    expect(dbName).not.toBe('diceup_dev');
    const count = await ds.query('SELECT count(*)::int AS n FROM users');
    expect(count[0].n).toBe(0);
  });

  it('full journey: register → verify → login → me → socket ping/pong → refresh → logout → old token dead on REST + socket', async () => {
    // 1. Register.
    const u = uniqueUser();
    const reg = await api().post('/v1/auth/register').send(u);
    expect(reg.status).toBe(201);
    expect(reg.body.success).toBe(true);
    const userId = reg.body.data.user.id as string;
    expect(reg.body.data.user.emailVerified).toBe(false);
    expect(reg.body.data.tokens.expiresIn).toBe(900);

    // 2. Verify via the log-mailer capture (no real email is sent).
    const msg = mailer.findLatest(u.email, 'verification');
    expect(msg).toBeDefined();
    const verify = await api()
      .post('/v1/auth/verify-email')
      .send({ token: msg!.token });
    expect(verify.status).toBe(200);
    expect(verify.body.success).toBe(true);

    // 3. Login.
    const login = await api()
      .post('/v1/auth/login')
      .send({ identifier: u.email, password: u.password });
    expect(login.status).toBe(200);
    const accessToken = login.body.data.tokens.accessToken as string;
    const refreshToken = login.body.data.tokens.refreshToken as string;

    // 4. Protected endpoint with the access token.
    const me = await api()
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${accessToken}`);
    expect(me.status).toBe(200);
    expect(me.body).toEqual({
      success: true,
      data: expect.objectContaining({ id: userId, email: u.email }),
    });
    expect(JSON.stringify(me.body)).not.toContain('password_hash');

    // 5. Socket.IO /game with the SAME access token, then ping/pong.
    const { client, connected } = await connect({ token: accessToken });
    await expect(connected).resolves.toMatchObject({ userId });
    // PingDto.requestId is @IsUUID() — a non-UUID is dropped by
    // validation, so the probe id must be a real UUID.
    const requestId = randomUUID();
    const pong = once<{ requestId: string; serverTime: string }>(
      client,
      'pong',
    );
    client.emit('ping', { requestId });
    await expect(pong).resolves.toMatchObject({ requestId });
    client.disconnect();

    // 6. Refresh rotates the pair.
    const refreshed = await api()
      .post('/v1/auth/refresh')
      .send({ refreshToken });
    expect(refreshed.status).toBe(200);
    expect(refreshed.body.data.accessToken).not.toBe(accessToken);
    expect(refreshed.body.data.refreshToken).not.toBe(refreshToken);
    const freshAccess = refreshed.body.data.accessToken as string;

    // The rotated-in access token works on REST and socket alike.
    const me2 = await api()
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${freshAccess}`);
    expect(me2.status).toBe(200);
    const { client: client2, connected: connected2 } = await connect({
      token: freshAccess,
    });
    await expect(connected2).resolves.toMatchObject({ userId });
    client2.disconnect();

    // 7. Logout revokes the session.
    const logout = await api()
      .post('/v1/auth/logout')
      .set('Authorization', `Bearer ${freshAccess}`);
    expect(logout.status).toBe(200);
    expect(logout.body.data).toEqual({ loggedOut: true });

    // 8. The OLD access token now fails on REST (401, §6.3 envelope)…
    const deadMe = await api()
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${freshAccess}`);
    expect(deadMe.status).toBe(401);
    expect(deadMe.body.success).toBe(false);
    expect(deadMe.body.error.code).toBe('UNAUTHORIZED');
    // …and the refresh token is dead too.
    const deadRefresh = await api()
      .post('/v1/auth/refresh')
      .send({ refreshToken: refreshed.body.data.refreshToken });
    expect(deadRefresh.status).toBe(401);
    expect(deadRefresh.body.error.code).toBe('UNAUTHORIZED');

    // 9. …and the same token fails the socket handshake (connect_error
    // carries the same §6.3 envelope in err.data).
    await expect(connect({ token: freshAccess })).rejects.toMatchObject({
      data: {
        success: false,
        error: { code: 'UNAUTHORIZED' },
      },
    });
  });

  it('refresh-token reuse revokes the whole family (REST + socket)', async () => {
    const { accessToken, refreshToken } = await registerVerified();
    const rotated = await api().post('/v1/auth/refresh').send({ refreshToken });
    expect(rotated.status).toBe(200);
    const successorAccess = rotated.body.data.accessToken as string;
    const successorRefresh = rotated.body.data.refreshToken as string;

    // Reuse of the rotated-out refresh token → 401.
    const reuse = await api().post('/v1/auth/refresh').send({ refreshToken });
    expect(reuse.status).toBe(401);
    expect(reuse.body.error.code).toBe('UNAUTHORIZED');

    // The successor pair is dead too — the family is revoked.
    const successor = await api()
      .post('/v1/auth/refresh')
      .send({ refreshToken: successorRefresh });
    expect(successor.status).toBe(401);
    const me = await api()
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${successorAccess}`);
    expect(me.status).toBe(401);
    // The pre-rotation access token is dead as well (sid check).
    const oldMe = await api()
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${accessToken}`);
    expect(oldMe.status).toBe(401);
    await expect(connect({ token: successorAccess })).rejects.toMatchObject({
      data: { success: false, error: { code: 'UNAUTHORIZED' } },
    });
  });

  it('health/readiness: 200 with all deps up', async () => {
    const health = await api().get('/v1/health');
    expect(health.status).toBe(200);
    expect(health.body).toEqual({
      success: true,
      data: { status: 'ok' },
    });
    const ready = await api().get('/v1/health/ready');
    expect(ready.status).toBe(200);
    expect(ready.body.success).toBe(true);
    expect(ready.body.data.status).toBe('ok');
    expect(ready.body.data.database).toBe('up');
    expect(ready.body.data.redis).toBe('up');
    expect(typeof ready.body.data.latencyMs.database).toBe('number');
  });

  it('readiness with Redis DOWN: 503, app still boots', async () => {
    // A second app pointed at a dead Redis port, via provider override
    // (not a process.env change — ConfigService reads backend/.env
    // before process.env, so an env override is silently ignored).
    const deadClient = new Redis('redis://127.0.0.1:6399', {
      lazyConnect: true,
      maxRetriesPerRequest: 1,
      retryStrategy: () => null,
    });
    const builder = Test.createTestingModule({ imports: [AppModule] });
    builder.overrideProvider(REDIS_CLIENT).useValue(deadClient);
    const moduleRef = await builder.compile();
    const deadApp = moduleRef.createNestApplication();
    await createApp(deadApp);
    try {
      await deadApp.init();
      // Liveness still answers — the process is up.
      const health = await request(deadApp.getHttpServer()).get('/v1/health');
      expect(health.status).toBe(200);
      // Readiness is 503 with the per-dependency status in error.data.
      const ready = await request(deadApp.getHttpServer()).get(
        '/v1/health/ready',
      );
      expect(ready.status).toBe(503);
      expect(ready.body.success).toBe(false);
      expect(ready.body.error.code).toBe('SERVICE_UNAVAILABLE');
      expect(ready.body.error.data.database).toBe('up');
      expect(ready.body.error.data.redis).toBe('down');
    } finally {
      await deadApp.close();
      deadClient.disconnect();
    }
  });

  it('login rate limit fires end-to-end (NFR-16): 5 bad logins → 6th is 429', async () => {
    const { u } = await registerVerified();
    for (let i = 0; i < 5; i++) {
      const bad = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: 'WrongPassword!1' });
      expect(bad.status).toBe(401);
      expect(bad.body.error.code).toBe('INVALID_CREDENTIALS');
    }
    // 6th attempt — even with the CORRECT password — is throttled.
    const throttled = await api()
      .post('/v1/auth/login')
      .send({ identifier: u.email, password: u.password });
    expect(throttled.status).toBe(429);
    expect(throttled.body.error.code).toBe('RATE_LIMITED');
    expect(throttled.headers['retry-after']).toBeDefined();
  });

  it('expired access token rejected on REST and socket', async () => {
    const { userId } = await registerVerified();
    // Signed with the dev private key, exp in the past (same technique
    // as the authz-matrix spec). The sid is a dummy: expiry is checked
    // before the session lookup, so the token must fail on exp alone.
    const devPrivateKey = fs.readFileSync(
      path.resolve(process.cwd(), '.keys/dev-private.pem'),
      'utf8',
    );
    const expiredToken = new JwtService({}).sign(
      {
        sub: userId,
        role: 'player',
        email_verified: true,
        sid: '00000000-0000-0000-0000-000000000000',
      },
      {
        privateKey: devPrivateKey,
        algorithm: 'RS256',
        expiresIn: -10,
        issuer: 'diceup',
      },
    );
    const me = await api()
      .get('/v1/users/me')
      .set('Authorization', `Bearer ${expiredToken}`);
    expect(me.status).toBe(401);
    expect(me.body.success).toBe(false);
    expect(me.body.error.code).toBe('UNAUTHORIZED');
    await expect(connect({ token: expiredToken })).rejects.toMatchObject({
      data: { success: false, error: { code: 'UNAUTHORIZED' } },
    });
  });

  it('no password or token appears in any log line during the journey', async () => {
    const chunks: string[] = [];
    const originalWrite = process.stdout.write.bind(process.stdout);
    process.stdout.write = ((chunk: unknown, ...args: unknown[]) => {
      chunks.push(String(chunk));
      return originalWrite(chunk as never, ...(args as never[]));
    }) as typeof process.stdout.write;
    let password = '';
    let refreshToken = '';
    let accessToken = '';
    try {
      const u = uniqueUser();
      password = u.password;
      const reg = await api().post('/v1/auth/register').send(u);
      expect(reg.status).toBe(201);
      refreshToken = reg.body.data.tokens.refreshToken as string;
      accessToken = reg.body.data.tokens.accessToken as string;
      // Verify BEFORE login/refresh: the socket requires a verified
      // account, and tokens minted pre-verification carry a stale
      // email_verified claim.
      const msg = mailer.findLatest(u.email, 'verification');
      expect(msg).toBeDefined();
      const verify = await api()
        .post('/v1/auth/verify-email')
        .send({ token: msg!.token });
      expect(verify.status).toBe(200);
      const login = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: u.password });
      expect(login.status).toBe(200);
      const refreshed = await api()
        .post('/v1/auth/refresh')
        .send({ refreshToken });
      expect(refreshed.status).toBe(200);
      const { client, connected } = await connect({
        token: refreshed.body.data.accessToken as string,
      });
      await expect(connected).resolves.toBeDefined();
      client.disconnect();
    } finally {
      process.stdout.write = originalWrite;
    }
    // Allow any async log flush to land before asserting.
    await new Promise((resolve) => setTimeout(resolve, 300));
    const output = chunks.join('');
    expect(output).not.toContain(password);
    expect(output).not.toContain(refreshToken);
    expect(output).not.toContain(accessToken);
    expect(output).not.toContain('password_hash');
  });
});
