import { AddressInfo } from 'node:net';
import { randomUUID } from 'node:crypto';
import { INestApplication } from '@nestjs/common';
import { DataSource } from 'typeorm';
import * as request from 'supertest';
import { io, type Socket as ClientSocket } from 'socket.io-client';
import { RedisAdapter } from '@socket.io/redis-adapter';
import { GameGateway } from '../../src/socket/game.gateway';
import { LogMailerService } from '../../src/mailer/log-mailer.service';
import { User } from '../../src/users/entities/user.entity';
import {
  bootTestApp,
  createScratchDb,
  dropScratchDb,
  migrateScratchDb,
  RateLimitCleaner,
  uniqueUser,
} from './test-helpers';

/**
 * Socket.IO gateway end-to-end (plan §10.3): real PostgreSQL 16 +
 * real Redis 7, fresh scratch database, migrations, real HTTP listen
 * on an ephemeral port. socket.io-client connects to /game with
 * `reconnection: false` everywhere (a rejected handshake must stay
 * rejected — the client's default retry loop would otherwise spam
 * connect_error events and mask the assertions).
 *
 * What this proves: unauthenticated / bad-token / revoked / unverified
 * / suspended handshakes are refused with the §6.3 code; a valid
 * connection gets the `connected` lifecycle event; malformed and
 * oversized ping payloads are rejected with the standardized error
 * and the connection survives; disconnect is clean; the 20/s flood
 * limit drops events and disconnects on sustained abuse; the gateway
 * boots on the Redis adapter; and two gateway instances share a
 * broadcast through that adapter (NFR-24 prep).
 */
describe('socket gateway (real PostgreSQL + real Redis)', () => {
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

  /**
   * Connect a client; resolves on `connect`, rejects on `connect_error`.
   * The `connected` promise is registered BEFORE the handshake can
   * complete: the server emits `connected` from handleConnection
   * immediately after accepting the socket, so a listener attached
   * only after `connect` resolves can miss it (a real race — the
   * first version of this spec hit it). Clients must register their
   * `connected` listener before connecting, same as here.
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

  async function registerUser(targetApp: INestApplication = app): Promise<{
    email: string;
    password: string;
    userId: string;
  }> {
    const u = uniqueUser();
    const res = await request(targetApp.getHttpServer())
      .post('/v1/auth/register')
      .send(u);
    expect(res.status).toBe(201);
    return {
      email: u.email,
      password: u.password,
      userId: res.body.data.user.id as string,
    };
  }

  async function verifyUser(
    email: string,
    targetApp: INestApplication = app,
    targetMailer: LogMailerService = mailer,
  ): Promise<void> {
    const msg = targetMailer.findLatest(email, 'verification');
    expect(msg).toBeDefined();
    const res = await request(targetApp.getHttpServer())
      .post('/v1/auth/verify-email')
      .send({ token: msg!.token });
    expect(res.status).toBe(200);
  }

  async function login(
    email: string,
    password: string,
    targetApp: INestApplication = app,
  ): Promise<string> {
    const res = await request(targetApp.getHttpServer())
      .post('/v1/auth/login')
      .send({ identifier: email, password });
    expect(res.status).toBe(200);
    return res.body.data.tokens.accessToken as string;
  }

  async function verifiedAccessToken(): Promise<{
    accessToken: string;
    userId: string;
  }> {
    const u = await registerUser();
    await verifyUser(u.email);
    const accessToken = await login(u.email, u.password);
    return { accessToken, userId: u.userId };
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
  }, 120000);

  afterAll(async () => {
    for (const client of clients) {
      try {
        client.disconnect();
      } catch {
        // Already gone.
      }
    }
    if (cleaner) await cleaner.quit();
    if (app) await app.close();
    if (dbName) await dropScratchDb(dbName);
  });

  beforeEach(async () => {
    await cleaner.clear();
    mailer.clear();
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

  it('boots the gateway on the Redis adapter', () => {
    const gateway = app.get(GameGateway);
    expect(gateway.server).toBeDefined();
    // @WebSocketServer() on a namespaced gateway is the Namespace
    // object (not the root Server) — its adapter is the Redis adapter.
    const adapter = gateway.server.adapter;
    expect(adapter).toBeInstanceOf(RedisAdapter);
  });

  it('refuses a connection with no token (UNAUTHORIZED connect_error)', async () => {
    const err = await connect().then(
      () => {
        throw new Error('should have been refused');
      },
      (e: unknown) => e as Error & { data?: unknown },
    );
    expect(err.message).toBe('Authentication token is required.');
    const envelope = err.data as {
      success: boolean;
      error: { code: string };
    };
    expect(envelope.success).toBe(false);
    expect(envelope.error.code).toBe('UNAUTHORIZED');
  });

  it('refuses a connection with a bad token (UNAUTHORIZED)', async () => {
    const err = await connect({ token: 'not-a-real-token' }).then(
      () => {
        throw new Error('should have been refused');
      },
      (e: unknown) => e as Error & { data?: unknown },
    );
    const envelope = err.data as { error: { code: string } };
    expect(envelope.error.code).toBe('UNAUTHORIZED');
  });

  it('accepts an authenticated connection and emits connected + answers ping', async () => {
    const { accessToken, userId } = await verifiedAccessToken();
    const { client, connected } = await connect({ token: accessToken });
    const info = await connected;
    expect(info.userId).toBe(userId);
    expect(info.socketId).toBe(client.id);
    const requestId = randomUUID();
    const pong = once<{ requestId: string; serverTime: string }>(
      client,
      'pong',
    );
    client.emit('ping', { requestId });
    await expect(pong).resolves.toMatchObject({ requestId });
  });

  it('refuses a revoked (logged-out) session with UNAUTHORIZED', async () => {
    const u = await registerUser();
    await verifyUser(u.email);
    const accessToken = await login(u.email, u.password);
    const logout = await api()
      .post('/v1/auth/logout')
      .set('Authorization', `Bearer ${accessToken}`);
    expect(logout.status).toBe(200);
    // The 15-min access JWT is still cryptographically valid, but its
    // sid row is revoked — the handshake must fail anyway.
    const err = await connect({ token: accessToken }).then(
      () => {
        throw new Error('should have been refused');
      },
      (e: unknown) => e as Error & { data?: unknown },
    );
    const envelope = err.data as { error: { code: string } };
    expect(envelope.error.code).toBe('UNAUTHORIZED');
  });

  it('refuses an unverified user with EMAIL_NOT_VERIFIED', async () => {
    const u = await registerUser();
    // Deliberately NOT verified — login still works (the user needs a
    // session to resend verification), but online access is refused.
    const accessToken = await login(u.email, u.password);
    const err = await connect({ token: accessToken }).then(
      () => {
        throw new Error('should have been refused');
      },
      (e: unknown) => e as Error & { data?: unknown },
    );
    const envelope = err.data as { error: { code: string } };
    expect(envelope.error.code).toBe('EMAIL_NOT_VERIFIED');
  });

  it('refuses a suspended user with ACCOUNT_SUSPENDED', async () => {
    const { accessToken, userId } = await verifiedAccessToken();
    await ds.getRepository(User).update(userId, { status: 'suspended' });
    const err = await connect({ token: accessToken }).then(
      () => {
        throw new Error('should have been refused');
      },
      (e: unknown) => e as Error & { data?: unknown },
    );
    const envelope = err.data as { error: { code: string } };
    expect(envelope.error.code).toBe('ACCOUNT_SUSPENDED');
  });

  it('rejects malformed ping payloads with VALIDATION_FAILED and stays connected', async () => {
    const { accessToken } = await verifiedAccessToken();
    const { client, connected } = await connect({ token: accessToken });
    await connected;

    const errors: unknown[] = [];
    client.on('exception', (data: unknown) => errors.push(data));
    client.emit('ping', {});
    client.emit('ping', { requestId: 'not-a-uuid' });
    client.emit('ping', 'just-a-string');

    // Wait for all three rejections (polling, not a fixed sleep), then
    // prove the connection survived by getting a pong for a valid ping.
    const deadline = Date.now() + 5000;
    while (errors.length < 3 && Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 50));
    }
    expect(errors.length).toBe(3);
    for (const data of errors) {
      const body = data as {
        success: boolean;
        error: { code: string; details?: Record<string, string[]> };
      };
      expect(body.success).toBe(false);
      expect(body.error.code).toBe('VALIDATION_FAILED');
    }
    const requestId = randomUUID();
    const pong = once<{ requestId: string }>(client, 'pong');
    client.emit('ping', { requestId });
    await expect(pong).resolves.toMatchObject({ requestId });
  });

  it('rejects an oversized ping payload with PAYLOAD_TOO_LARGE', async () => {
    const { accessToken } = await verifiedAccessToken();
    const { client, connected } = await connect({ token: accessToken });
    await connected;
    const exception = once<{
      success: boolean;
      error: { code: string };
    }>(client, 'exception');
    client.emit('ping', {
      requestId: randomUUID(),
      pad: 'x'.repeat(11 * 1024),
    });
    await expect(exception).resolves.toMatchObject({
      success: false,
      error: { code: 'PAYLOAD_TOO_LARGE' },
    });
  });

  it('handles disconnect cleanly — a fresh connection still works', async () => {
    const { accessToken } = await verifiedAccessToken();
    const first = await connect({ token: accessToken });
    await first.connected;
    const disconnected = once(first.client, 'disconnect');
    first.client.disconnect();
    await expect(disconnected).resolves.toBeDefined();
    const second = await connect({ token: accessToken });
    await expect(second.connected).resolves.toBeDefined();
  });

  it('rate-limits a ping burst: the 21st event is dropped with RATE_LIMITED', async () => {
    const { accessToken } = await verifiedAccessToken();
    const { client, connected } = await connect({ token: accessToken });
    await connected;
    const pongs: unknown[] = [];
    const errors: unknown[] = [];
    client.on('pong', (data: unknown) => pongs.push(data));
    client.on('exception', (data: unknown) => errors.push(data));
    for (let i = 0; i < 21; i++) {
      client.emit('ping', { requestId: randomUUID() });
    }
    // One violation only — below the abuse-disconnect threshold, so
    // the connection stays up and the error is delivered.
    const deadline = Date.now() + 5000;
    while ((pongs.length < 20 || errors.length < 1) && Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 50));
    }
    expect(pongs.length).toBe(20);
    expect(errors.length).toBe(1);
    expect(
      (errors[0] as { success: boolean; error: { code: string } }).error.code,
    ).toBe('RATE_LIMITED');
    expect(client.connected).toBe(true);
  });

  it('disconnects on sustained abuse: sequential flood, 20 pongs then disconnect', async () => {
    const { accessToken } = await verifiedAccessToken();
    const { client, connected } = await connect({ token: accessToken });
    await connected;
    // Sequential pings (one reply at a time) so the server processes
    // them in order: a 30-event burst is processed concurrently, and
    // the abuse disconnect can land before in-flight pongs flush,
    // which makes an exact pong count unassertable for a burst. The
    // burst shape is covered by the 21-event test above; this test
    // proves the disconnect itself.
    let disconnected = false;
    client.on('disconnect', () => {
      disconnected = true;
    });
    const pingAndWait = (): Promise<'pong' | 'exception' | 'disconnect'> =>
      new Promise((resolve) => {
        const timer = setTimeout(() => resolve('disconnect'), 5000);
        const done = (v: 'pong' | 'exception' | 'disconnect') => {
          clearTimeout(timer);
          client.off('pong', onPong);
          client.off('exception', onException);
          client.off('disconnect', onDisconnect);
          resolve(v);
        };
        const onPong = () => done('pong');
        const onException = () => done('exception');
        const onDisconnect = () => done('disconnect');
        client.once('pong', onPong);
        client.once('exception', onException);
        client.once('disconnect', onDisconnect);
        client.emit('ping', { requestId: randomUUID() });
      });
    const results: string[] = [];
    for (let i = 0; i < 30 && !disconnected; i++) {
      results.push(await pingAndWait());
    }
    // First 20 events are in budget (pong); 21st–24th are dropped
    // with RATE_LIMITED; the 25th records the 5th violation and the
    // socket is disconnected (its own exception may or may not arrive
    // before the disconnect — either is accepted).
    expect(results.filter((r) => r === 'pong').length).toBe(20);
    expect(
      results.filter((r) => r === 'exception').length,
    ).toBeGreaterThanOrEqual(4);
    expect(disconnected).toBe(true);
  });

  it('shares a broadcast between two gateway instances via the Redis adapter', async () => {
    // Second node: its own scratch database, its own port, same Redis.
    const second = await createScratchDb();
    await migrateScratchDb(second.url);
    const appB = await bootTestApp(second.url);
    await appB.listen(0);
    const portB = (appB.getHttpServer().address() as AddressInfo).port;
    try {
      // The user must exist in node B's database (each node boots its
      // own scratch DB): register + verify + login against node B.
      const mailerB = appB.get(LogMailerService);
      const uB = await registerUser(appB);
      await verifyUser(uB.email, appB, mailerB);
      const accessToken = await login(uB.email, uB.password, appB);
      const clientB = io(`http://127.0.0.1:${portB}/game`, {
        auth: { token: accessToken },
        reconnection: false,
        timeout: 5000,
      });
      clients.push(clientB);
      await once(clientB, 'connected');
      // Emit from node A's server: the Redis adapter must carry it to
      // node B's connected client. 'adapter:probe' is a test-only event
      // name — no production event is added for this.
      const probe = once<{ from: string }>(clientB, 'adapter:probe');
      // gateway.server IS the /game Namespace — emitting on it
      // broadcasts to that namespace on this node and, via the Redis
      // adapter, to the same namespace on every other node.
      app.get(GameGateway).server.emit('adapter:probe', {
        from: 'node-a',
      });
      await expect(probe).resolves.toEqual({ from: 'node-a' });
    } finally {
      await appB.close();
      await dropScratchDb(second.name);
    }
  });
});
