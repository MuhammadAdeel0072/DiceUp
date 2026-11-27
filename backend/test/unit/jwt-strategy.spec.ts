import { generateKeyPairSync } from 'node:crypto';
import { UnauthorizedException } from '@nestjs/common';
import { JwtStrategy } from '../../src/auth/strategies/jwt.strategy';
import { AuthSession } from '../../src/auth/entities/auth-session.entity';
import { User } from '../../src/users/entities/user.entity';

function makeKeys() {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });
  return { privateKey, publicKey, issuer: 'diceup-test' };
}

describe('JwtStrategy (sid revocation check, plan §7.1)', () => {
  const keys = makeKeys();
  const now = new Date();
  const liveSession = {
    id: 'session-1',
    userId: 'user-1',
    revokedAt: null,
    expiresAt: new Date(now.getTime() + 3600_000),
  } as AuthSession;
  const liveUser = {
    id: 'user-1',
    email: 'ali@example.com',
    username: 'ali_plays',
    status: 'active',
    emailVerifiedAt: new Date(),
    deletionRequestedAt: null,
  } as User;

  function makeStrategy(session: AuthSession | null, user: User | null) {
    const sessions = { findOne: jest.fn().mockResolvedValue(session) };
    const users = { findOne: jest.fn().mockResolvedValue(user) };
    return new JwtStrategy(keys, sessions as never, users as never);
  }

  const payload = {
    sub: 'user-1',
    role: 'player' as const,
    email_verified: true,
    sid: 'session-1',
  };

  it('attaches the principal for a live session', async () => {
    const strategy = makeStrategy(liveSession, liveUser);
    const user = await strategy.validate(payload);
    expect(user.id).toBe('user-1');
    expect(user.sessionId).toBe('session-1');
    expect(user.role).toBe('player');
    expect(user.emailVerified).toBe(true);
    expect(user.status).toBe('active');
  });

  it('rejects a revoked session (logout must take effect)', async () => {
    const strategy = makeStrategy(
      { ...liveSession, revokedAt: new Date() },
      liveUser,
    );
    await expect(strategy.validate(payload)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects an expired session', async () => {
    const strategy = makeStrategy(
      { ...liveSession, expiresAt: new Date(now.getTime() - 1000) },
      liveUser,
    );
    await expect(strategy.validate(payload)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects a session belonging to another user', async () => {
    const strategy = makeStrategy(
      { ...liveSession, userId: 'user-2' },
      liveUser,
    );
    await expect(strategy.validate(payload)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects an unknown session id', async () => {
    const strategy = makeStrategy(null, liveUser);
    await expect(strategy.validate(payload)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects when the user no longer exists', async () => {
    const strategy = makeStrategy(liveSession, null);
    await expect(strategy.validate(payload)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('rejects a payload with a forged role', async () => {
    const strategy = makeStrategy(liveSession, liveUser);
    await expect(
      strategy.validate({ ...payload, role: 'admin' as never }),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a payload without a sid', async () => {
    const strategy = makeStrategy(liveSession, liveUser);
    const { sid: _sid, ...noSid } = payload;
    await expect(strategy.validate(noSid as never)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });
});
