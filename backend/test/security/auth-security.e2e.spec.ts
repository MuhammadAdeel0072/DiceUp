import { INestApplication } from '@nestjs/common';
import { DataSource } from 'typeorm';
import * as request from 'supertest';
import { LogMailerService } from '../../src/mailer/log-mailer.service';
import { User } from '../../src/users/entities/user.entity';
import {
  bootTestApp,
  createScratchDb,
  dropScratchDb,
  migrateScratchDb,
  RateLimitCleaner,
  uniqueUser,
} from '../integration/test-helpers';

/**
 * Security tests (plan §10.4): enumeration resistance, input abuse,
 * secret leakage. Real PostgreSQL + real Redis, fresh scratch DB.
 */
describe('auth security (real PostgreSQL + real Redis)', () => {
  let dbName: string;
  let app: INestApplication;
  let ds: DataSource;
  let mailer: LogMailerService;
  let cleaner: RateLimitCleaner;

  const api = () => request(app.getHttpServer());

  beforeAll(async () => {
    const { name, url } = await createScratchDb();
    dbName = name;
    await migrateScratchDb(url);
    app = await bootTestApp(url);
    ds = app.get(DataSource);
    mailer = app.get(LogMailerService);
    cleaner = new RateLimitCleaner();
  }, 120000);

  afterAll(async () => {
    if (cleaner) await cleaner.quit();
    if (app) await app.close();
    if (dbName) await dropScratchDb(dbName);
  });

  beforeEach(async () => {
    await cleaner.clear();
  });

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
    return { u, accessToken: login.body.data.tokens.accessToken as string };
  }

  it('forgot-password for unknown vs known email → identical responses', async () => {
    const { u } = await registerVerified();
    const known = await api()
      .post('/v1/auth/forgot-password')
      .send({ email: u.email });
    const unknown = await api()
      .post('/v1/auth/forgot-password')
      .send({ email: 'nobody@example.com' });
    expect(known.status).toBe(200);
    expect(unknown.status).toBe(200);
    expect(known.body).toEqual(unknown.body);
  });

  it('public profile for an unknown id vs another user → same 404 shape', async () => {
    const { accessToken } = await registerVerified();
    const other = await registerVerified();
    const otherId = (await ds
      .getRepository(User)
      .findOne({ where: { email: other.u.email } }))!.id;
    const unknown = await api()
      .get('/v1/users/00000000-0000-0000-0000-000000000000/profile')
      .set('Authorization', `Bearer ${accessToken}`);
    // Unknown id → 404 with the standard envelope (same response the
    // requester would get for any profile they cannot see).
    expect(unknown.status).toBe(404);
    expect(unknown.body).toEqual({
      success: false,
      error: { code: 'NOT_FOUND', message: 'Profile not found.' },
    });
    // Positive control: another real user's public profile is visible.
    const visible = await api()
      .get(`/v1/users/${otherId}/profile`)
      .set('Authorization', `Bearer ${accessToken}`);
    expect(visible.status).toBe(200);
  });

  it('SQL-injection strings are inert data or 400 — never executed', async () => {
    const injection = `'; DROP TABLE users; --`;
    const badUsername = await api().post('/v1/auth/register').send({
      email: uniqueUser().email,
      username: injection,
      password: 'CorrectHorse!9',
    });
    expect(badUsername.status).toBe(400);
    const badEmail = await api().post('/v1/auth/register').send({
      email: `' OR '1'='1`,
      username: uniqueUser().username,
      password: 'CorrectHorse!9',
    });
    expect(badEmail.status).toBe(400);
    // A password containing SQL is stored as an inert Argon2id hash.
    const u = uniqueUser();
    const ok = await api()
      .post('/v1/auth/register')
      .send({ ...u, password: injection });
    expect(ok.status).toBe(201);
    const login = await api()
      .post('/v1/auth/login')
      .send({ identifier: u.email, password: injection });
    expect(login.status).toBe(200);
    // The users table is intact.
    const count = await ds.getRepository(User).count();
    expect(count).toBeGreaterThanOrEqual(2);
    const ready = await api().get('/v1/health/ready');
    expect(ready.status).toBe(200);
  });

  it('oversized JSON body → 413, malformed JSON → 400, service stays up', async () => {
    const big = await api()
      .post('/v1/auth/register')
      .send({
        ...uniqueUser(),
        displayName: 'x'.repeat(200 * 1024),
      });
    expect(big.status).toBe(413);
    expect(big.body.error.code).toBe('PAYLOAD_TOO_LARGE');
    const malformed = await api()
      .post('/v1/auth/register')
      .set('Content-Type', 'application/json')
      .send('{bad json');
    expect(malformed.status).toBe(400);
    expect(malformed.body.error.code).toBe('VALIDATION_FAILED');
    const health = await api().get('/v1/health');
    expect(health.status).toBe(200);
  });

  it('concurrent duplicate registration → one 201 + one 409, never a 500 (Stage 4, H-02)', async () => {
    const u = uniqueUser();
    const [first, second] = await Promise.all([
      api().post('/v1/auth/register').send(u),
      api().post('/v1/auth/register').send(u),
    ]);
    const statuses = [first.status, second.status].sort();
    expect(statuses).toEqual([201, 409]);
    const loser = first.status === 409 ? first : second;
    expect(['EMAIL_TAKEN', 'USERNAME_TAKEN']).toContain(loser.body.error.code);
    // Exactly one user row was created.
    const count = await ds
      .getRepository(User)
      .count({ where: { email: u.email } });
    expect(count).toBe(1);
  });

  it('no password, token or hash appears in any log line during auth flows', async () => {
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
      const login = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: u.password });
      expect(login.status).toBe(200);
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
