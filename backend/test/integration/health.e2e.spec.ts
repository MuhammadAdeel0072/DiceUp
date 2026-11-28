import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import { Pool } from 'pg';
import * as request from 'supertest';
import Redis from 'ioredis';
import { AppModule } from '../../src/app.module';
import { REDIS_CLIENT, RedisService } from '../../src/redis/redis.service';
import { buildDataSourceOptions } from '../../src/database/data-source';
import { createApp } from './test-app.factory';

/**
 * Integration: app startup + health endpoints against REAL PostgreSQL 16
 * and REAL Redis 7 (plan §10.1/§10.3). Each run creates a fresh scratch
 * database (`diceup_test_<pid>_<random>`), runs all migrations, verifies
 * the schema, runs, and drops it. Never the dev database, never a
 * shared/production service, never SQLite.
 *
 * Local admin connection (role `diceup`, CREATEDB) comes from
 * TEST_ADMIN_DATABASE_URL, defaulting to the local dev cluster.
 */
const ADMIN_URL =
  process.env.TEST_ADMIN_DATABASE_URL ??
  'postgres://diceup:diceup_dev_local_only@localhost:5432/postgres';
const REDIS_URL = process.env.REDIS_URL ?? 'redis://127.0.0.1:6379';

async function createScratchDb(): Promise<string> {
  const name = `diceup_test_${process.pid}_${Math.random()
    .toString(36)
    .slice(2, 8)}`;
  const admin = new Pool({ connectionString: ADMIN_URL });
  try {
    await admin.query(`CREATE DATABASE "${name}"`);
  } finally {
    await admin.end();
  }
  return name;
}

async function dropScratchDb(name: string): Promise<void> {
  const admin = new Pool({ connectionString: ADMIN_URL });
  try {
    await admin.query(`DROP DATABASE IF EXISTS "${name}"`);
  } finally {
    await admin.end();
  }
}

async function bootApp(
  databaseUrl: string,
  redisUrl: string,
  redisClientOverride?: Redis,
) {
  process.env.NODE_ENV = 'test';
  process.env.DATABASE_URL = databaseUrl;
  process.env.REDIS_URL = redisUrl;
  process.env.PORT = '3000';
  process.env.RULESET_VERSION = '1.0.0';
  // ConfigModule reads env at module creation (below), not at import
  // time, so static imports are safe. Do NOT jest.resetModules() here:
  // it reloads a second copy of @nestjs/core and breaks DI (ModuleRef).
  const builder = Test.createTestingModule({
    imports: [AppModule],
  });
  // Provider override (not a process.env change): @nestjs/config's
  // ConfigService reads backend/.env before process.env, so an env
  // override of REDIS_URL is silently ignored while .env exists.
  // Overriding the client token is the deterministic way to point
  // one app at a dead Redis. See README "Config precedence" note.
  if (redisClientOverride) {
    builder.overrideProvider(REDIS_CLIENT).useValue(redisClientOverride);
  }
  const moduleRef = await builder.compile();
  const app = moduleRef.createNestApplication();
  await createApp(app);
  await app.init();
  return app;
}

describe('health + startup (real PostgreSQL + real Redis)', () => {
  let dbName: string;
  let databaseUrl: string;
  let app: INestApplication;

  beforeAll(async () => {
    dbName = await createScratchDb();
    databaseUrl = `postgres://diceup:diceup_dev_local_only@localhost:5432/${dbName}`;
    // Migrate the scratch DB first, exactly as a release step would.
    const ds = new DataSource(buildDataSourceOptions(databaseUrl));
    await ds.initialize();
    try {
      const executed = await ds.runMigrations();
      expect(executed.map((m) => m.name)).toContain('InitAuth1764240000000');
      // Schema verification: the SDD §9.2 tables exist (Phase 4's four
      // + Phase 5 Stage 3's six), nothing else except TypeORM's own
      // `migrations` version table (§4.4).
      const tables = await ds.query(
        `SELECT table_name FROM information_schema.tables
         WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
         ORDER BY table_name`,
      );
      expect(tables.map((t: { table_name: string }) => t.table_name)).toEqual([
        'auth_sessions',
        'email_tokens',
        'game_configurations',
        'match_players',
        'matches',
        'migrations',
        'move_events',
        'profiles',
        'room_members',
        'rooms',
        'users',
      ]);
      // citest extension + key columns, incl. the two [P4 choice] columns.
      const cols = await ds.query(
        `SELECT table_name, column_name, data_type, udt_name FROM information_schema.columns
         WHERE table_schema = 'public' ORDER BY table_name, column_name`,
      );
      const colSet = new Set(
        cols.map(
          (c: { table_name: string; column_name: string }) =>
            `${c.table_name}.${c.column_name}`,
        ),
      );
      for (const expected of [
        'users.id',
        'users.email',
        'users.username',
        'users.password_hash',
        'users.status',
        'users.email_verified_at',
        'users.deletion_requested_at',
        'users.created_at',
        'users.updated_at',
        'profiles.user_id',
        'profiles.display_name',
        'profiles.avatar_key',
        'profiles.matches_played',
        'profiles.matches_won',
        'auth_sessions.id',
        'auth_sessions.refresh_token_hash',
        'auth_sessions.family_id',
        'auth_sessions.device_label',
        'auth_sessions.expires_at',
        'auth_sessions.revoked_at',
        'email_tokens.id',
        'email_tokens.purpose',
        'email_tokens.token_hash',
        'email_tokens.expires_at',
        'email_tokens.used_at',
      ]) {
        expect(colSet.has(expected)).toBe(true);
      }
      const emailType = cols.find(
        (c: { table_name: string; column_name: string }) =>
          c.table_name === 'users' && c.column_name === 'email',
      );
      // information_schema reports CITEXT as data_type USER-DEFINED;
      // udt_name is the real type name.
      expect(emailType.udt_name).toBe('citext');
      expect(emailType.data_type).toBe('USER-DEFINED');
      // Partial unique index on live email tokens (SDD §9.2).
      const indexes = await ds.query(
        `SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public'`,
      );
      const defs = indexes.map(
        (i: { indexdef: string }) => i.indexdef,
      ) as string[];
      expect(
        defs.some(
          (d) =>
            d.includes('email_tokens') &&
            d.includes('used_at') &&
            d.includes('UNIQUE'),
        ),
      ).toBe(true);
      expect(
        defs.some((d) => d.includes('users') && d.includes('status')),
      ).toBe(true);
      // Re-running migrations is a no-op.
      const second = await ds.runMigrations();
      expect(second).toHaveLength(0);
    } finally {
      await ds.destroy();
    }
    app = await bootApp(databaseUrl, REDIS_URL);
  }, 120000);

  afterAll(async () => {
    if (app) await app.close();
    if (dbName) await dropScratchDb(dbName);
  });

  it('GET /v1/health — liveness 200, envelope, no dependency details', async () => {
    const res = await request(app.getHttpServer()).get('/v1/health');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      success: true,
      data: { status: 'ok' },
    });
    expect(JSON.stringify(res.body)).not.toMatch(/postgres|redis|5432|6379/i);
    expect(res.headers['x-request-id']).toBeTruthy();
  });

  it('a client-supplied X-Request-Id is never adopted (Stage 4, M-04)', async () => {
    const res = await request(app.getHttpServer())
      .get('/v1/health')
      .set('X-Request-Id', 'spoofed-id');
    expect(res.status).toBe(200);
    expect(res.headers['x-request-id']).toBeTruthy();
    expect(res.headers['x-request-id']).not.toBe('spoofed-id');
  });

  it('GET /v1/health/ready — 200 when PostgreSQL + Redis are up', async () => {
    const res = await request(app.getHttpServer()).get('/v1/health/ready');
    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.status).toBe('ok');
    expect(res.body.data.database).toBe('up');
    expect(res.body.data.redis).toBe('up');
    expect(typeof res.body.data.latencyMs.database).toBe('number');
    expect(typeof res.body.data.latencyMs.redis).toBe('number');
    expect(JSON.stringify(res.body)).not.toMatch(
      /diceup|postgres:\/\/|redis:\/\/|localhost:5432/i,
    );
  });

  it('unknown route returns the error envelope, not a stack trace', async () => {
    const res = await request(app.getHttpServer()).get('/v1/nope');
    expect(res.status).toBe(404);
    expect(res.body.success).toBe(false);
    expect(res.body.error.code).toBeTruthy();
    expect(JSON.stringify(res.body)).not.toMatch(/stack|at .*\.ts:/i);
  });

  it('GET /v1/health/ready — 503 with per-dependency status when Redis is down', async () => {
    // A second app pointed at a dead Redis port: distinguishes the
    // dependencies without stopping the shared local Redis.
    const deadClient = new Redis('redis://127.0.0.1:6399', {
      lazyConnect: true,
      maxRetriesPerRequest: 3,
      retryStrategy: (times: number) => Math.min(times * 50, 2000),
    });
    const deadApp = await bootApp(databaseUrl, REDIS_URL, deadClient);
    try {
      const res = await request(deadApp.getHttpServer()).get(
        '/v1/health/ready',
      );
      expect(res.status).toBe(503);
      expect(res.body.success).toBe(false);
      expect(res.body.error.code).toBe('SERVICE_UNAVAILABLE');
      expect(res.body.error.data.database).toBe('up');
      expect(res.body.error.data.redis).toBe('down');
      expect(res.body.error.data.status).toBe('degraded');
    } finally {
      await deadApp.close();
    }
  });

  it('RedisService works against real Redis: incr + lock round-trip', async () => {
    const redis = app.get(RedisService);
    await expect(redis.ping()).resolves.toBe(true);
    const key = `test:health:${process.pid}`;
    await redis.del(key);
    await expect(redis.incrWithExpiry(key, 60)).resolves.toBe(1);
    await expect(redis.incrWithExpiry(key, 60)).resolves.toBe(2);
    const token = await redis.acquireLock(`${key}:lock`, 10);
    expect(token).toBeTruthy();
    await expect(redis.acquireLock(`${key}:lock`, 10)).resolves.toBeNull();
    await expect(
      redis.releaseLock(`${key}:lock`, token as string),
    ).resolves.toBe(true);
    await redis.del(key);
  });
});
