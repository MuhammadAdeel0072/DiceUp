import { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { DataSource } from 'typeorm';
import * as request from 'supertest';
import { AuthService } from '../../src/auth/auth.service';
import { AuthSession } from '../../src/auth/entities/auth-session.entity';
import { EmailToken } from '../../src/auth/entities/email-token.entity';
import { hashRefreshToken } from '../../src/auth/token.service';
import { LogMailerService } from '../../src/mailer/log-mailer.service';
import { Profile } from '../../src/users/entities/profile.entity';
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
 * Auth + users end-to-end (plan §10.3): real PostgreSQL 16 + real
 * Redis 7, fresh scratch database, migrations. Rate-limit counters
 * are cleared before each test (all traffic is one IP by design).
 */
describe('auth + users (real PostgreSQL + real Redis)', () => {
  let dbName: string;
  let databaseUrl: string;
  let app: INestApplication;
  let ds: DataSource;
  let mailer: LogMailerService;
  let cleaner: RateLimitCleaner;

  const api = () => request(app.getHttpServer());

  beforeAll(async () => {
    ({ name: dbName, url: databaseUrl } = await createScratchDb());
    await migrateScratchDb(databaseUrl);
    app = await bootTestApp(databaseUrl);
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
    mailer.clear();
  });

  async function register(overrides: Record<string, unknown> = {}) {
    const u = uniqueUser();
    const res = await api()
      .post('/v1/auth/register')
      .send({ ...u, ...overrides });
    return { u, res };
  }

  /** Registers, verifies via the captured mail, logs in. */
  async function registerVerified() {
    const { u, res } = await register();
    expect(res.status).toBe(201);
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

  function decodePayload(token: string): Record<string, unknown> {
    const payload = token.split('.')[1];
    return JSON.parse(
      Buffer.from(payload, 'base64url').toString('utf8'),
    ) as Record<string, unknown>;
  }

  describe('registration (FR-02)', () => {
    it('happy path: 201, user + tokens, profile + hashed email token rows', async () => {
      const { u, res } = await register();
      expect(res.status).toBe(201);
      expect(res.body).toEqual({
        success: true,
        data: {
          user: {
            id: expect.any(String),
            email: u.email,
            username: u.username,
            displayName: u.displayName,
            avatarKey: 'default',
            emailVerified: false,
          },
          tokens: {
            accessToken: expect.any(String),
            refreshToken: expect.any(String),
            expiresIn: 900,
            tokenType: 'Bearer',
          },
        },
      });
      const user = await ds
        .getRepository(User)
        .findOne({ where: { email: u.email } });
      expect(user).not.toBeNull();
      const profile = await ds
        .getRepository(Profile)
        .findOne({ where: { userId: user!.id } });
      expect(profile).not.toBeNull();
      const tokenRow = await ds
        .getRepository(EmailToken)
        .findOne({ where: { userId: user!.id, purpose: 'verify' } });
      expect(tokenRow).not.toBeNull();
      // The stored token is a hash, never the plaintext from the mail.
      const msg = mailer.findLatest(u.email, 'verification');
      expect(msg).toBeDefined();
      expect(tokenRow!.tokenHash).not.toContain(msg!.token);
      expect(tokenRow!.tokenHash).toMatch(/^[0-9a-f]{64}$/);
      // The access token carries role 'player' + a sid.
      const payload = decodePayload(res.body.data.tokens.accessToken);
      expect(payload.role).toBe('player');
      expect(payload.sid).toBeTruthy();
    });

    it('duplicate email → 409 EMAIL_TAKEN (case-insensitive)', async () => {
      const { u } = await register();
      const again = await register({
        email: u.email.toUpperCase(),
        username: uniqueUser().username,
      });
      expect(again.res.status).toBe(409);
      expect(again.res.body.error.code).toBe('EMAIL_TAKEN');
    });

    it('duplicate username → 409 USERNAME_TAKEN (case-insensitive)', async () => {
      const { u } = await register();
      const again = await register({
        email: uniqueUser().email,
        username: u.username.toUpperCase(),
      });
      expect(again.res.status).toBe(409);
      expect(again.res.body.error.code).toBe('USERNAME_TAKEN');
    });

    it('weak password / bad email / bad username → 400 with field detail', async () => {
      const weak = await register({ password: 'short' });
      expect(weak.res.status).toBe(400);
      expect(weak.res.body.error.code).toBe('VALIDATION_FAILED');
      // Stage 4, M-01: per-field details — the client can tell WHICH
      // field failed (previously everything collapsed into `_global`).
      expect(weak.res.body.error.details).toHaveProperty('password');
      expect(weak.res.body.error.details).not.toHaveProperty('_global');
      const badEmail = await register({ email: 'nope' });
      expect(badEmail.res.status).toBe(400);
      expect(badEmail.res.body.error.details).toHaveProperty('email');
      const badUsername = await register({ username: 'a!' });
      expect(badUsername.res.status).toBe(400);
      expect(badUsername.res.body.error.details).toHaveProperty('username');
    });

    it('unknown fields are stripped — a client cannot grant itself a role', async () => {
      const { res } = await register({
        role: 'admin',
        isAdmin: true,
      } as Record<string, unknown>);
      expect(res.status).toBe(201);
      const payload = decodePayload(res.body.data.tokens.accessToken);
      expect(payload.role).toBe('player');
      expect(res.body.data.user).not.toHaveProperty('role');
    });

    it('transaction rolls back when the profile insert fails (NFR-31)', async () => {
      const auth = app.get(AuthService);
      const u = uniqueUser();
      await expect(
        auth.register({ ...u, displayName: 'x'.repeat(60) }),
      ).rejects.toThrow();
      const found = await ds
        .getRepository(User)
        .findOne({ where: { email: u.email } });
      expect(found).toBeNull();
    });
  });

  describe('email verification (FR-03)', () => {
    it('valid token verifies; reuse → 409 TOKEN_ALREADY_USED', async () => {
      const { u } = await register();
      const msg = mailer.findLatest(u.email, 'verification');
      const first = await api()
        .post('/v1/auth/verify-email')
        .send({ token: msg!.token });
      expect(first.status).toBe(200);
      expect(first.body.data.user.emailVerified).toBe(true);
      const again = await api()
        .post('/v1/auth/verify-email')
        .send({ token: msg!.token });
      expect(again.status).toBe(409);
      expect(again.body.error.code).toBe('TOKEN_ALREADY_USED');
    });

    it('expired token → 410 TOKEN_EXPIRED; unknown token → 401', async () => {
      const { u, res } = await register();
      const userId = res.body.data.user.id as string;
      const msg = mailer.findLatest(u.email, 'verification');
      await ds
        .getRepository(EmailToken)
        .update({ userId }, { expiresAt: new Date(Date.now() - 1000) });
      const expired = await api()
        .post('/v1/auth/verify-email')
        .send({ token: msg!.token });
      expect(expired.status).toBe(410);
      expect(expired.body.error.code).toBe('TOKEN_EXPIRED');
      const unknown = await api()
        .post('/v1/auth/verify-email')
        .send({ token: 'not-a-real-token' });
      expect(unknown.status).toBe(401);
    });

    it('resend: unverified gets a new mail; unknown/verified get a neutral 200', async () => {
      const { u } = await register();
      const resend = await api()
        .post('/v1/auth/verify-email/resend')
        .send({ email: u.email });
      expect(resend.status).toBe(200);
      expect(
        mailer
          .getSentMessages()
          .filter((m) => m.to === u.email && m.kind === 'verification'),
      ).toHaveLength(2);
      const unknown = await api()
        .post('/v1/auth/verify-email/resend')
        .send({ email: 'nobody@example.com' });
      expect(unknown.status).toBe(200);
      expect(unknown.body).toEqual(resend.body);
      expect(
        mailer.getSentMessages().filter((m) => m.to === 'nobody@example.com'),
      ).toHaveLength(0);
    });
  });

  describe('login (FR-04, NFR-16)', () => {
    it('logs in with email and with username', async () => {
      const { u } = await registerVerified();
      const byEmail = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: u.password });
      expect(byEmail.status).toBe(200);
      expect(byEmail.body.data.tokens.expiresIn).toBe(900);
      const byUsername = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.username, password: u.password });
      expect(byUsername.status).toBe(200);
    });

    it('wrong password vs unknown account → identical 401 responses', async () => {
      const { u } = await register();
      const wrongPass = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: 'WrongPass1' });
      const unknown = await api()
        .post('/v1/auth/login')
        .send({ identifier: 'nobody@example.com', password: 'WrongPass1' });
      expect(wrongPass.status).toBe(401);
      expect(unknown.status).toBe(401);
      expect(wrongPass.body).toEqual(unknown.body);
      expect(wrongPass.body.error.code).toBe('INVALID_CREDENTIALS');
    });

    it('unverified users can log in but cannot use online routes', async () => {
      const { u, res } = await register();
      expect(res.status).toBe(201);
      const login = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: u.password });
      expect(login.status).toBe(200);
      const me = await api()
        .get('/v1/users/me')
        .set('Authorization', `Bearer ${login.body.data.tokens.accessToken}`);
      expect(me.status).toBe(403);
      expect(me.body.error.code).toBe('EMAIL_NOT_VERIFIED');
    });

    it('suspended account: correct password → 403, wrong password → 401 (no leak)', async () => {
      const { u, userId, accessToken } = await registerVerified();
      await ds
        .getRepository(User)
        .update({ id: userId }, { status: 'suspended' });
      const correct = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: u.password });
      expect(correct.status).toBe(403);
      expect(correct.body.error.code).toBe('ACCOUNT_SUSPENDED');
      const wrong = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: 'WrongPass1' });
      expect(wrong.status).toBe(401);
      const me = await api()
        .get('/v1/users/me')
        .set('Authorization', `Bearer ${accessToken}`);
      expect(me.status).toBe(403);
      expect(me.body.error.code).toBe('ACCOUNT_SUSPENDED');
    });

    it('account with a pending deletion request cannot log in', async () => {
      const { userId, accessToken } = await registerVerified();
      const del = await api()
        .delete('/v1/users/me')
        .set('Authorization', `Bearer ${accessToken}`);
      expect(del.status).toBe(200);
      const user = await ds
        .getRepository(User)
        .findOne({ where: { id: userId } });
      const loginReal = await api()
        .post('/v1/auth/login')
        .send({ identifier: user!.email, password: 'CorrectHorse!9' });
      expect(loginReal.status).toBe(403);
      expect(loginReal.body.error.code).toBe('FORBIDDEN');
    });
  });

  describe('refresh + logout (NFR-15, FR-05)', () => {
    it('refresh rotates the pair; the new pair works repeatedly', async () => {
      const { refreshToken } = await registerVerified();
      const first = await api().post('/v1/auth/refresh').send({ refreshToken });
      expect(first.status).toBe(200);
      expect(first.body.data.refreshToken).not.toBe(refreshToken);
      expect(first.body.data.expiresIn).toBe(900);
      const second = await api()
        .post('/v1/auth/refresh')
        .send({ refreshToken: first.body.data.refreshToken });
      expect(second.status).toBe(200);
      const me = await api()
        .get('/v1/users/me')
        .set('Authorization', `Bearer ${second.body.data.accessToken}`);
      expect(me.status).toBe(200);
    });

    it('reuse of a rotated refresh token revokes the whole family', async () => {
      const { refreshToken, accessToken } = await registerVerified();
      const rotated = await api()
        .post('/v1/auth/refresh')
        .send({ refreshToken });
      expect(rotated.status).toBe(200);
      const reuse = await api().post('/v1/auth/refresh').send({ refreshToken });
      expect(reuse.status).toBe(401);
      // The rotated successor is dead too — the family is revoked.
      const successor = await api()
        .post('/v1/auth/refresh')
        .send({ refreshToken: rotated.body.data.refreshToken });
      expect(successor.status).toBe(401);
      const me = await api()
        .get('/v1/users/me')
        .set('Authorization', `Bearer ${rotated.body.data.accessToken}`);
      expect(me.status).toBe(401);
      // The pre-rotation access token is dead as well (sid check).
      const oldMe = await api()
        .get('/v1/users/me')
        .set('Authorization', `Bearer ${accessToken}`);
      expect(oldMe.status).toBe(401);
    });

    it('logout revokes the session; other sessions of the user survive', async () => {
      const { u, accessToken, refreshToken } = await registerVerified();
      const secondLogin = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: u.password });
      expect(secondLogin.status).toBe(200);
      const logout = await api()
        .post('/v1/auth/logout')
        .set('Authorization', `Bearer ${accessToken}`);
      expect(logout.status).toBe(200);
      expect(logout.body.data).toEqual({ loggedOut: true });
      const refresh = await api()
        .post('/v1/auth/refresh')
        .send({ refreshToken });
      expect(refresh.status).toBe(401);
      const me = await api()
        .get('/v1/users/me')
        .set('Authorization', `Bearer ${accessToken}`);
      expect(me.status).toBe(401);
      // The other session (other family) still works.
      const otherRefresh = await api()
        .post('/v1/auth/refresh')
        .send({ refreshToken: secondLogin.body.data.tokens.refreshToken });
      expect(otherRefresh.status).toBe(200);
    });

    it('garbage and expired refresh tokens → 401', async () => {
      const { refreshToken } = await registerVerified();
      const garbage = await api()
        .post('/v1/auth/refresh')
        .send({ refreshToken: 'garbage' });
      expect(garbage.status).toBe(401);
      const session = await ds.getRepository(AuthSession).findOne({
        where: { refreshTokenHash: hashRefreshToken(refreshToken) },
      });
      expect(session).not.toBeNull();
      await ds
        .getRepository(AuthSession)
        .update(
          { id: session!.id },
          { expiresAt: new Date(Date.now() - 1000) },
        );
      const expired = await api()
        .post('/v1/auth/refresh')
        .send({ refreshToken });
      expect(expired.status).toBe(401);
    });
  });

  describe('password recovery (FR-06)', () => {
    it('forgot-password is neutral for unknown emails; reset works end-to-end', async () => {
      const { u, refreshToken, accessToken } = await registerVerified();
      const unknown = await api()
        .post('/v1/auth/forgot-password')
        .send({ email: 'nobody@example.com' });
      expect(unknown.status).toBe(200);
      expect(
        mailer.findLatest('nobody@example.com', 'password-reset'),
      ).toBeUndefined();
      const forgot = await api()
        .post('/v1/auth/forgot-password')
        .send({ email: u.email });
      expect(forgot.status).toBe(200);
      expect(forgot.body).toEqual(unknown.body);
      const msg = mailer.findLatest(u.email, 'password-reset');
      expect(msg).toBeDefined();
      const reset = await api()
        .post('/v1/auth/reset-password')
        .send({ token: msg!.token, newPassword: 'NewPassword!2' });
      expect(reset.status).toBe(200);
      // Old sessions are dead; new password works.
      const oldRefresh = await api()
        .post('/v1/auth/refresh')
        .send({ refreshToken });
      expect(oldRefresh.status).toBe(401);
      const oldMe = await api()
        .get('/v1/users/me')
        .set('Authorization', `Bearer ${accessToken}`);
      expect(oldMe.status).toBe(401);
      const login = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: 'NewPassword!2' });
      expect(login.status).toBe(200);
      // Token reuse → 409.
      const reuse = await api()
        .post('/v1/auth/reset-password')
        .send({ token: msg!.token, newPassword: 'Another!3' });
      expect(reuse.status).toBe(409);
      expect(reuse.body.error.code).toBe('TOKEN_ALREADY_USED');
    });

    it('expired reset token → 410', async () => {
      const { u } = await registerVerified();
      await api().post('/v1/auth/forgot-password').send({ email: u.email });
      const msg = mailer.findLatest(u.email, 'password-reset');
      const user = await ds
        .getRepository(User)
        .findOne({ where: { email: u.email } });
      await ds
        .getRepository(EmailToken)
        .update(
          { userId: user!.id, purpose: 'reset' },
          { expiresAt: new Date(Date.now() - 1000) },
        );
      const reset = await api()
        .post('/v1/auth/reset-password')
        .send({ token: msg!.token, newPassword: 'NewPassword!2' });
      expect(reset.status).toBe(410);
      expect(reset.body.error.code).toBe('TOKEN_EXPIRED');
    });
  });

  describe('users (FR-07/08/10/63)', () => {
    it('GET /users/me returns the own profile without password data', async () => {
      const { u, accessToken } = await registerVerified();
      const me = await api()
        .get('/v1/users/me')
        .set('Authorization', `Bearer ${accessToken}`);
      expect(me.status).toBe(200);
      expect(me.body.data).toMatchObject({
        email: u.email,
        username: u.username,
        displayName: u.displayName,
        avatarKey: 'default',
        emailVerified: true,
        status: 'active',
        matchesPlayed: 0,
        matchesWon: 0,
      });
      expect(JSON.stringify(me.body)).not.toMatch(
        /password_hash|passwordHash/i,
      );
    });

    it('PATCH /users/me updates display name + avatar; invalid values → 400', async () => {
      const { accessToken } = await registerVerified();
      const ok = await api()
        .patch('/v1/users/me')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ displayName: 'Ali Khan', avatarKey: 'gold' });
      expect(ok.status).toBe(200);
      expect(ok.body.data.displayName).toBe('Ali Khan');
      expect(ok.body.data.avatarKey).toBe('gold');
      const badAvatar = await api()
        .patch('/v1/users/me')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ avatarKey: 'not-a-key' });
      expect(badAvatar.status).toBe(400);
      const longName = await api()
        .patch('/v1/users/me')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ displayName: 'x'.repeat(51) });
      expect(longName.status).toBe(400);
    });

    it('PATCH /users/me/password: wrong old → 401; success revokes all sessions', async () => {
      const { u, accessToken, refreshToken } = await registerVerified();
      const wrong = await api()
        .patch('/v1/users/me/password')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ oldPassword: 'WrongPass1', newPassword: 'NewPassword!2' });
      expect(wrong.status).toBe(401);
      const ok = await api()
        .patch('/v1/users/me/password')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ oldPassword: u.password, newPassword: 'NewPassword!2' });
      expect(ok.status).toBe(200);
      const refresh = await api()
        .post('/v1/auth/refresh')
        .send({ refreshToken });
      expect(refresh.status).toBe(401);
      const login = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: 'NewPassword!2' });
      expect(login.status).toBe(200);
      const oldLogin = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: u.password });
      expect(oldLogin.status).toBe(401);
    });

    it('PATCH /users/me/preferences round-trips', async () => {
      const { accessToken } = await registerVerified();
      const saved = await api()
        .patch('/v1/users/me/preferences')
        .set('Authorization', `Bearer ${accessToken}`)
        .send({ emailNotifications: true, pushNotifications: false });
      expect(saved.status).toBe(200);
      expect(saved.body.data.notificationPreferences).toEqual({
        emailNotifications: true,
        pushNotifications: false,
      });
      const me = await api()
        .get('/v1/users/me')
        .set('Authorization', `Bearer ${accessToken}`);
      expect(me.body.data.notificationPreferences).toEqual({
        emailNotifications: true,
        pushNotifications: false,
      });
    });

    it('GET /users/:id/profile returns public fields only; unknown → 404', async () => {
      const { userId, accessToken } = await registerVerified();
      const pub = await api()
        .get(`/v1/users/${userId}/profile`)
        .set('Authorization', `Bearer ${accessToken}`);
      expect(pub.status).toBe(200);
      expect(pub.body.data).toEqual({
        userId,
        displayName: expect.any(String),
        avatarKey: 'default',
        matchesPlayed: 0,
        matchesWon: 0,
      });
      expect(JSON.stringify(pub.body)).not.toMatch(/email|password/i);
      const unknown = await api()
        .get('/v1/users/00000000-0000-0000-0000-000000000000/profile')
        .set('Authorization', `Bearer ${accessToken}`);
      expect(unknown.status).toBe(404);
      const badId = await api()
        .get('/v1/users/not-a-uuid/profile')
        .set('Authorization', `Bearer ${accessToken}`);
      expect(badId.status).toBe(400);
    });

    it('DELETE /users/me sets the marker and revokes sessions (FR-10 partial)', async () => {
      const { userId, accessToken, refreshToken } = await registerVerified();
      const del = await api()
        .delete('/v1/users/me')
        .set('Authorization', `Bearer ${accessToken}`);
      expect(del.status).toBe(200);
      expect(del.body.data.deletionRequestedAt).toBeTruthy();
      const user = await ds
        .getRepository(User)
        .findOne({ where: { id: userId } });
      expect(user!.deletionRequestedAt).not.toBeNull();
      const refresh = await api()
        .post('/v1/auth/refresh')
        .send({ refreshToken });
      expect(refresh.status).toBe(401);
    });
  });

  describe('rate limits (NFR-16, plan §6.5)', () => {
    it('login throttle: 5 bad logins → 6th is 429 even with the right password', async () => {
      const { u } = await register();
      for (let i = 0; i < 5; i++) {
        const res = await api()
          .post('/v1/auth/login')
          .send({ identifier: u.email, password: 'WrongPass1' });
        expect(res.status).toBe(401);
      }
      const sixth = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: u.password });
      expect(sixth.status).toBe(429);
      expect(sixth.body.error.code).toBe('RATE_LIMITED');
      expect(sixth.headers['retry-after']).toBeTruthy();
      // After the counters clear, the correct password works again.
      await cleaner.clear();
      const ok = await api()
        .post('/v1/auth/login')
        .send({ identifier: u.email, password: u.password });
      expect(ok.status).toBe(200);
    });

    it('register flood: 10/hour per IP, 11th → 429 with Retry-After', async () => {
      for (let i = 0; i < 10; i++) {
        const { res } = await register();
        expect(res.status).toBe(201);
      }
      const flooded = await register();
      expect(flooded.res.status).toBe(429);
      expect(flooded.res.body.error.code).toBe('RATE_LIMITED');
      expect(flooded.res.headers['retry-after']).toBeTruthy();
      // The service stays up.
      const health = await api().get('/v1/health');
      expect(health.status).toBe(200);
    });

    it('verify-email flood: 10/hour per IP, 11th → 429', async () => {
      for (let i = 0; i < 10; i++) {
        const res = await api()
          .post('/v1/auth/verify-email')
          .send({ token: 'garbage' });
        expect(res.status).toBe(401);
      }
      const flooded = await api()
        .post('/v1/auth/verify-email')
        .send({ token: 'garbage' });
      expect(flooded.status).toBe(429);
    });

    it('forgot-password flood: 5/hour per email, 6th → 429', async () => {
      for (let i = 0; i < 5; i++) {
        const res = await api()
          .post('/v1/auth/forgot-password')
          .send({ email: 'flood@example.com' });
        expect(res.status).toBe(200);
      }
      const flooded = await api()
        .post('/v1/auth/forgot-password')
        .send({ email: 'flood@example.com' });
      expect(flooded.status).toBe(429);
    });
  });

  it('Swagger document generates from the new DTOs', () => {
    const document = SwaggerModule.createDocument(
      app,
      new DocumentBuilder()
        .setTitle('DiceUp API')
        .setDescription('test')
        .setVersion('0.1.0')
        .build(),
    );
    expect(document.paths['/v1/auth/register']).toBeDefined();
    expect(document.paths['/v1/auth/login']).toBeDefined();
    expect(document.paths['/v1/users/me']).toBeDefined();
    expect(document.paths['/v1/users/{id}/profile']).toBeDefined();
  });
});
