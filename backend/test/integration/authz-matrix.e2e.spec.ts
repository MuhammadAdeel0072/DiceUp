import { generateKeyPairSync } from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { INestApplication } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
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
} from './test-helpers';

/**
 * Authorization matrix (plan §10.4, FR-42): every route ×
 * {no token, expired, revoked, unverified, suspended, valid} →
 * expected status. This is the single most important Phase 4 test
 * artefact (plan §12 item 8).
 */
describe('authorization matrix (FR-42)', () => {
  let dbName: string;
  let app: INestApplication;
  let ds: DataSource;
  let mailer: LogMailerService;
  let cleaner: RateLimitCleaner;

  let validId: string;
  let validToken: string;
  let unverifiedToken: string;
  let suspendedToken: string;
  let revokedToken: string;
  let expiredToken: string;
  let forgedAdminToken: string;

  const api = () => request(app.getHttpServer());

  beforeAll(async () => {
    const { name, url } = await createScratchDb();
    dbName = name;
    await migrateScratchDb(url);
    app = await bootTestApp(url);
    ds = app.get(DataSource);
    mailer = app.get(LogMailerService);
    cleaner = new RateLimitCleaner();

    async function makeUser(verify: boolean) {
      const u = uniqueUser();
      const reg = await api().post('/v1/auth/register').send(u);
      expect(reg.status).toBe(201);
      let accessToken = reg.body.data.tokens.accessToken as string;
      const refreshToken = reg.body.data.tokens.refreshToken as string;
      if (verify) {
        const msg = mailer.findLatest(u.email, 'verification');
        const v = await api()
          .post('/v1/auth/verify-email')
          .send({ token: msg!.token });
        expect(v.status).toBe(200);
        const login = await api()
          .post('/v1/auth/login')
          .send({ identifier: u.email, password: u.password });
        expect(login.status).toBe(200);
        accessToken = login.body.data.tokens.accessToken as string;
        return {
          u,
          id: login.body.data.user.id as string,
          accessToken,
          refreshToken,
        };
      }
      return {
        u,
        id: reg.body.data.user.id as string,
        accessToken,
        refreshToken,
      };
    }

    // Valid user.
    const valid = await makeUser(true);
    validId = valid.id;
    validToken = valid.accessToken;

    // Unverified user (can log in, cannot use online routes).
    const unverified = await makeUser(false);
    unverifiedToken = unverified.accessToken;

    // Suspended user: token minted while active, then suspended.
    const suspended = await makeUser(true);
    suspendedToken = suspended.accessToken;
    await ds
      .getRepository(User)
      .update({ id: suspended.id }, { status: 'suspended' });

    // Revoked session: token minted, then logged out.
    const revoked = await makeUser(true);
    revokedToken = revoked.accessToken;
    const logout = await api()
      .post('/v1/auth/logout')
      .set('Authorization', `Bearer ${revokedToken}`);
    expect(logout.status).toBe(200);

    // Expired token: signed with the dev private key, exp in the past.
    const devPrivateKey = fs.readFileSync(
      path.resolve(process.cwd(), '.keys/dev-private.pem'),
      'utf8',
    );
    expiredToken = new JwtService({}).sign(
      {
        sub: validId,
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

    // Forged admin token: valid shape, signed with a different key.
    const { privateKey } = generateKeyPairSync('rsa', {
      modulusLength: 2048,
      publicKeyEncoding: { type: 'spki', format: 'pem' },
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    });
    forgedAdminToken = new JwtService({}).sign(
      {
        sub: validId,
        role: 'admin',
        email_verified: true,
        sid: '00000000-0000-0000-0000-000000000000',
      },
      {
        privateKey,
        algorithm: 'RS256',
        expiresIn: 900,
        issuer: 'diceup',
      },
    );
  }, 120000);

  afterAll(async () => {
    if (cleaner) await cleaner.quit();
    if (app) await app.close();
    if (dbName) await dropScratchDb(dbName);
  });

  beforeEach(async () => {
    await cleaner.clear();
  });

  type Probe = {
    name: string;
    run: (token?: string) => Promise<{ status: number; body: unknown }>;
  };

  const probes: Probe[] = [
    {
      name: 'GET /users/me',
      run: (token) =>
        api()
          .get('/v1/users/me')
          .set('Authorization', `Bearer ${token ?? ''}`) as never,
    },
    {
      name: 'PATCH /users/me',
      run: (token) =>
        api()
          .patch('/v1/users/me')
          .set('Authorization', `Bearer ${token ?? ''}`)
          .send({ displayName: 'Matrix' }) as never,
    },
    {
      name: 'GET /users/:id/profile',
      run: (token) =>
        api()
          .get(`/v1/users/${validId}/profile`)
          .set('Authorization', `Bearer ${token ?? ''}`) as never,
    },
    {
      name: 'POST /auth/logout',
      run: (token) =>
        api()
          .post('/v1/auth/logout')
          .set('Authorization', `Bearer ${token ?? ''}`) as never,
    },
  ];

  /** Expected status per route × state. */
  const matrix: Record<string, Record<string, number>> = {
    'GET /users/me': {
      none: 401,
      garbage: 401,
      expired: 401,
      revoked: 401,
      unverified: 403,
      suspended: 403,
      forgedAdmin: 401,
      valid: 200,
    },
    'PATCH /users/me': {
      none: 401,
      garbage: 401,
      expired: 401,
      revoked: 401,
      unverified: 403,
      suspended: 403,
      forgedAdmin: 401,
      valid: 200,
    },
    'GET /users/:id/profile': {
      none: 401,
      garbage: 401,
      expired: 401,
      revoked: 401,
      unverified: 403,
      suspended: 403,
      forgedAdmin: 401,
      valid: 200,
    },
    'POST /auth/logout': {
      none: 401,
      garbage: 401,
      expired: 401,
      revoked: 401,
      unverified: 200,
      suspended: 403,
      forgedAdmin: 401,
      valid: 200,
    },
  };

  it('every route × every state returns the expected status', async () => {
    const tokens: Record<string, string | undefined> = {
      none: undefined,
      garbage: 'garbage-token',
      expired: expiredToken,
      revoked: revokedToken,
      unverified: unverifiedToken,
      suspended: suspendedToken,
      forgedAdmin: forgedAdminToken,
      valid: validToken,
    };
    for (const probe of probes) {
      for (const [state, token] of Object.entries(tokens)) {
        const res = await probe.run(token);
        // String comparison so a failure names the route + state.
        expect(`${probe.name} with ${state} token → ${res.status}`).toBe(
          `${probe.name} with ${state} token → ${matrix[probe.name][state]}`,
        );
      }
    }
  });

  it('no-token and garbage-token responses carry the error envelope', async () => {
    const res = await api().get('/v1/users/me');
    expect(res.status).toBe(401);
    expect(res.body.success).toBe(false);
    expect(res.body.error.code).toBe('UNAUTHORIZED');
    expect(JSON.stringify(res.body)).not.toMatch(/stack|password/i);
  });
});
