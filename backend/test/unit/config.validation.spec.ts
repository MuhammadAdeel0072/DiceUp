import { validateProductionConfig } from '../../src/config/config.validation';
import type { AppConfig } from '../../src/config/configuration';

function makeConfig(overrides: Partial<AppConfig> = {}): AppConfig {
  return {
    nodeEnv: 'development',
    port: 3000,
    logLevel: 'info',
    databaseUrl: 'postgres://diceup:x@localhost:5432/diceup_dev',
    redisUrl: 'redis://127.0.0.1:6379',
    rulesetVersion: '1.0.0',
    corsOrigins: ['http://localhost:3000'],
    trustProxy: false,
    jwtPrivateKey:
      '-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----',
    jwtPublicKey: '-----BEGIN PUBLIC KEY-----\ntest\n-----END PUBLIC KEY-----',
    jwtIssuer: 'diceup',
    mailerProvider: 'log',
    ...overrides,
  };
}

describe('validateProductionConfig (plan §8.1 fail-fast)', () => {
  it('does nothing in development/test even without JWT keys', () => {
    expect(() =>
      validateProductionConfig(
        makeConfig({
          nodeEnv: 'development',
          jwtPrivateKey: undefined,
          jwtPublicKey: undefined,
        }),
      ),
    ).not.toThrow();
    expect(() =>
      validateProductionConfig(makeConfig({ nodeEnv: 'test' })),
    ).not.toThrow();
  });

  it('passes in production when everything is present', () => {
    expect(() =>
      validateProductionConfig(
        makeConfig({
          nodeEnv: 'production',
          databaseUrl: 'postgres://diceup:x@db.example:5432/diceup',
          redisUrl: 'redis://cache.example:6379',
        }),
      ),
    ).not.toThrow();
  });

  it('fails in production and names the missing variables (never values)', () => {
    expect(() =>
      validateProductionConfig(
        makeConfig({
          nodeEnv: 'production',
          jwtPrivateKey: undefined,
          jwtPublicKey: undefined,
          corsOrigins: [],
        }),
      ),
    ).toThrow(/Missing required production configuration/);
    expect(() =>
      validateProductionConfig(
        makeConfig({
          nodeEnv: 'production',
          jwtPrivateKey: undefined,
        }),
      ),
    ).toThrow(/JWT_PRIVATE_KEY/);
    // The error must not contain a secret value.
    expect(() =>
      validateProductionConfig(
        makeConfig({
          nodeEnv: 'production',
          jwtPrivateKey: undefined,
          databaseUrl: 'postgres://diceup:SECRET@localhost:5432/x',
        }),
      ),
    ).toThrow(/JWT_PRIVATE_KEY/);
  });

  it('rejects a localhost DATABASE_URL in production', () => {
    expect(() =>
      validateProductionConfig(makeConfig({ nodeEnv: 'production' })),
    ).toThrow(/must not point at localhost/);
  });

  it('rejects loopback by IP too — 127.0.0.1 / ::1, for both URLs (Stage 4, M-06)', () => {
    // 127.0.0.1 database (the old check only caught the literal
    // 'localhost' string).
    expect(() =>
      validateProductionConfig(
        makeConfig({
          nodeEnv: 'production',
          databaseUrl: 'postgres://diceup:x@127.0.0.1:5432/diceup',
          redisUrl: 'redis://cache.example:6379',
        }),
      ),
    ).toThrow(/DATABASE_URL must not point at localhost/);
    // Loopback Redis (the old check never looked at REDIS_URL).
    expect(() =>
      validateProductionConfig(
        makeConfig({
          nodeEnv: 'production',
          databaseUrl: 'postgres://diceup:x@db.example:5432/diceup',
          redisUrl: 'redis://127.0.0.1:6379',
        }),
      ),
    ).toThrow(/REDIS_URL must not point at localhost/);
    expect(() =>
      validateProductionConfig(
        makeConfig({
          nodeEnv: 'production',
          databaseUrl: 'postgres://diceup:x@db.example:5432/diceup',
          redisUrl: 'redis://[::1]:6379',
        }),
      ),
    ).toThrow(/REDIS_URL must not point at localhost/);
  });
});
