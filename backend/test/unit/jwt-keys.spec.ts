import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { generateKeyPairSync } from 'node:crypto';
import { JwtService } from '@nestjs/jwt';
import { resolveJwtKey } from '../../src/config/configuration';
import type { AppConfig } from '../../src/config/configuration';
import { buildJwtKeys } from '../../src/auth/jwt-keys';

describe('JWT key resolution (NFR-15)', () => {
  it('inline PEM wins over a file', () => {
    expect(resolveJwtKey('INLINE', './does-not-exist.pem')).toBe('INLINE');
  });

  it('reads a key from a file', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'diceup-keys-'));
    const file = path.join(dir, 'key.pem');
    fs.writeFileSync(file, '  -----BEGIN PUBLIC KEY-----\nabc\n');
    try {
      expect(resolveJwtKey(undefined, file)).toBe(
        '-----BEGIN PUBLIC KEY-----\nabc',
      );
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  });

  it('missing/unreadable file resolves to undefined (never throws)', () => {
    expect(resolveJwtKey(undefined, './does-not-exist.pem')).toBeUndefined();
    expect(resolveJwtKey(undefined, undefined)).toBeUndefined();
  });

  it('buildJwtKeys uses configured keys', () => {
    const keys = buildJwtKeys({
      nodeEnv: 'development',
      port: 3000,
      logLevel: 'info',
      databaseUrl: 'postgres://x',
      redisUrl: 'redis://127.0.0.1:6379',
      rulesetVersion: '1.0.0',
      corsOrigins: [],
      trustProxy: false,
      jwtPrivateKey: 'PRIVATE',
      jwtPublicKey: 'PUBLIC',
      jwtIssuer: 'diceup',
    });
    expect(keys.privateKey).toBe('PRIVATE');
    expect(keys.publicKey).toBe('PUBLIC');
    expect(keys.issuer).toBe('diceup');
  });

  it('buildJwtKeys fails fast in production without keys', () => {
    expect(() =>
      buildJwtKeys({
        nodeEnv: 'production',
        port: 3000,
        logLevel: 'info',
        databaseUrl: 'postgres://x',
        redisUrl: 'redis://127.0.0.1:6379',
        rulesetVersion: '1.0.0',
        corsOrigins: ['https://diceup.example'],
        trustProxy: false,
        jwtIssuer: 'diceup',
      }),
    ).toThrow(/Production JWT configuration error/);
  });

  it('buildJwtKeys fails fast when only one half of the pair is present (Stage 4, M-07)', () => {
    const base: AppConfig = {
      nodeEnv: 'development',
      port: 3000,
      logLevel: 'info',
      databaseUrl: 'postgres://x',
      redisUrl: 'redis://127.0.0.1:6379',
      rulesetVersion: '1.0.0',
      corsOrigins: [],
      trustProxy: false,
      jwtIssuer: 'diceup',
    };
    expect(() => buildJwtKeys({ ...base, jwtPrivateKey: 'PRIVATE' })).toThrow(
      /must be configured together/,
    );
    expect(() => buildJwtKeys({ ...base, jwtPublicKey: 'PUBLIC' })).toThrow(
      /must be configured together/,
    );
  });

  it('buildJwtKeys generates a usable ephemeral pair in dev/test', () => {
    const keys = buildJwtKeys({
      nodeEnv: 'test',
      port: 3000,
      logLevel: 'info',
      databaseUrl: 'postgres://x',
      redisUrl: 'redis://127.0.0.1:6379',
      rulesetVersion: '1.0.0',
      corsOrigins: [],
      trustProxy: false,
      jwtIssuer: 'diceup',
    });
    expect(keys.privateKey).toContain('PRIVATE KEY');
    expect(keys.publicKey).toContain('PUBLIC KEY');
    // The pair actually signs and verifies.
    const jwt = new JwtService({});
    const token = jwt.sign(
      { sub: 'u1' },
      {
        privateKey: keys.privateKey,
        algorithm: 'RS256',
        expiresIn: 60,
        issuer: 'diceup',
      },
    );
    expect(
      jwt.verify(token, {
        publicKey: keys.publicKey,
        algorithms: ['RS256'],
        issuer: 'diceup',
      }).sub,
    ).toBe('u1');
  });
});

describe('generateKeyPairSync sanity (dev keypair generation)', () => {
  it('openssl-equivalent RSA-2048 generation works on this runtime', () => {
    const { privateKey, publicKey } = generateKeyPairSync('rsa', {
      modulusLength: 2048,
      publicKeyEncoding: { type: 'spki', format: 'pem' },
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    });
    expect(privateKey).toContain('PRIVATE KEY');
    expect(publicKey).toContain('PUBLIC KEY');
  });
});
