import { generateKeyPairSync } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import { ACCESS_TOKEN_TTL_SECONDS } from '../../src/auth/auth.constants';
import { hashRefreshToken, TokenService } from '../../src/auth/token.service';

function makeKeys() {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });
  return { privateKey, publicKey, issuer: 'diceup-test' };
}

describe('TokenService (NFR-15, RS256)', () => {
  const keys = makeKeys();
  const service = new TokenService(new JwtService({}), keys);

  it('signs an access token with the SDD claims and a 15-min expiry', () => {
    const token = service.signAccessToken(
      { id: 'user-1', emailVerified: false },
      'session-1',
    );
    const payload = service.verifyAccessToken(token);
    expect(payload.sub).toBe('user-1');
    expect(payload.role).toBe('player');
    expect(payload.email_verified).toBe(false);
    expect(payload.sid).toBe('session-1');
    expect(payload.iss).toBe('diceup-test');
    expect(payload.exp! - payload.iat!).toBe(ACCESS_TOKEN_TTL_SECONDS);
  });

  it('reflects email_verified in the claims', () => {
    const token = service.signAccessToken(
      { id: 'user-1', emailVerified: true },
      'session-1',
    );
    expect(service.verifyAccessToken(token).email_verified).toBe(true);
  });

  it('rejects a tampered token', () => {
    const token = service.signAccessToken(
      { id: 'user-1', emailVerified: true },
      'session-1',
    );
    const parts = token.split('.');
    const tampered = `${parts[0]}.${parts[1]}.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`;
    expect(() => service.verifyAccessToken(tampered)).toThrow(
      /Invalid or expired access token/,
    );
  });

  it('rejects a token signed with a different key (forged role included)', () => {
    const otherKeys = makeKeys();
    const other = new JwtService({});
    const forged = other.sign(
      { sub: 'user-1', role: 'admin', email_verified: true, sid: 's1' },
      {
        privateKey: otherKeys.privateKey,
        algorithm: 'RS256',
        expiresIn: 900,
        issuer: 'diceup-test',
      },
    );
    expect(() => service.verifyAccessToken(forged)).toThrow(
      /Invalid or expired access token/,
    );
  });

  it('rejects an expired token', () => {
    const jwt = new JwtService({});
    const expired = jwt.sign(
      { sub: 'user-1', role: 'player', email_verified: true, sid: 's1' },
      {
        privateKey: keys.privateKey,
        algorithm: 'RS256',
        expiresIn: -10,
        issuer: 'diceup-test',
      },
    );
    expect(() => service.verifyAccessToken(expired)).toThrow(
      /Invalid or expired access token/,
    );
  });

  it('generates opaque refresh tokens whose hashes are stable SHA-256', () => {
    const a = service.generateRefreshToken();
    const b = service.generateRefreshToken();
    expect(a.token).not.toBe(b.token);
    expect(a.token.length).toBeGreaterThanOrEqual(43);
    expect(a.hash).toBe(hashRefreshToken(a.token));
    expect(a.hash).toMatch(/^[0-9a-f]{64}$/);
    expect(a.hash).not.toBe(b.hash);
    // The stored hash never contains the token itself.
    expect(a.hash).not.toContain(a.token);
  });
});
