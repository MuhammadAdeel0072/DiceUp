import type { PostgresConnectionOptions } from 'typeorm/driver/postgres/PostgresConnectionOptions';
import {
  DATABASE_CONNECT_TIMEOUT_MS,
  DATABASE_RETRY_ATTEMPTS,
  DATABASE_RETRY_DELAY_MS,
  PHASE4_ENTITIES,
  PHASE4_MIGRATIONS,
  buildDataSourceOptions,
} from '../../src/database/data-source';

describe('database options (plan §4.4 — synchronize NEVER on)', () => {
  it('builds options for the four Phase 4 entities only', () => {
    const opts = buildDataSourceOptions(
      'postgres://diceup:x@localhost:5432/diceup_dev',
    );
    expect(opts.type).toBe('postgres');
    expect(PHASE4_ENTITIES).toHaveLength(4);
    expect(PHASE4_ENTITIES.map((e) => e.name).sort()).toEqual([
      'AuthSession',
      'EmailToken',
      'Profile',
      'User',
    ]);
    expect(PHASE4_MIGRATIONS).toHaveLength(2);
    expect(PHASE4_MIGRATIONS.map((m) => m.name).sort()).toEqual([
      'AddProfilePreferences1764249000000',
      'InitAuth1764240000000',
    ]);
  });

  it('has synchronize === false in every environment', () => {
    for (const env of ['development', 'test', 'production']) {
      process.env.NODE_ENV = env;
      const opts = buildDataSourceOptions(
        'postgres://diceup:x@localhost:5432/diceup_dev',
      );
      expect(opts.synchronize).toBe(false);
    }
  });

  it('bounds connect time so boot against a dead DB fails fast (Stage 4, M-02)', () => {
    const opts = buildDataSourceOptions(
      'postgres://diceup:x@localhost:5432/diceup_dev',
    ) as PostgresConnectionOptions;
    // Initial connect + pool checkout both time out instead of hanging
    // on pg's no-timeout default (unreachable host) forever.
    expect(opts.connectTimeoutMS).toBe(DATABASE_CONNECT_TIMEOUT_MS);
    expect(opts.connectTimeoutMS).toBeLessThanOrEqual(5000);
    expect(opts.extra?.connectionTimeoutMillis).toBe(
      DATABASE_CONNECT_TIMEOUT_MS,
    );
    // The Nest TypeORM retry bounds (applied in DatabaseModule) are
    // small: worst-case boot failure is ~17 s, not minutes.
    expect(DATABASE_RETRY_ATTEMPTS).toBe(3);
    expect(DATABASE_RETRY_DELAY_MS).toBe(1000);
  });
});
