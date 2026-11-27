import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import { Pool } from 'pg';
import Redis from 'ioredis';
import { AppModule } from '../../src/app.module';
import { buildDataSourceOptions } from '../../src/database/data-source';
import { createApp } from './test-app.factory';

/**
 * Shared e2e helpers (plan §10.1/§10.3): real PostgreSQL 16 + real
 * Redis 7, fresh scratch database per spec file, migrations run as a
 * release step would, dropped afterwards. Never the dev database,
 * never a shared/production service, never SQLite.
 *
 * Local admin connection (role `diceup`, CREATEDB) comes from
 * TEST_ADMIN_DATABASE_URL, defaulting to the local dev cluster.
 */
export const ADMIN_URL =
  process.env.TEST_ADMIN_DATABASE_URL ??
  'postgres://diceup:diceup_dev_local_only@localhost:5432/postgres';
export const REDIS_URL = process.env.REDIS_URL ?? 'redis://127.0.0.1:6379';

export async function createScratchDb(): Promise<{
  name: string;
  url: string;
}> {
  const name = `diceup_test_${process.pid}_${Math.random()
    .toString(36)
    .slice(2, 8)}`;
  const admin = new Pool({ connectionString: ADMIN_URL });
  try {
    await admin.query(`CREATE DATABASE "${name}"`);
  } finally {
    await admin.end();
  }
  return {
    name,
    url: `postgres://diceup:diceup_dev_local_only@localhost:5432/${name}`,
  };
}

export async function dropScratchDb(name: string): Promise<void> {
  const admin = new Pool({ connectionString: ADMIN_URL });
  try {
    await admin.query(`DROP DATABASE IF EXISTS "${name}"`);
  } finally {
    await admin.end();
  }
}

export async function migrateScratchDb(databaseUrl: string): Promise<void> {
  const ds = new DataSource(buildDataSourceOptions(databaseUrl));
  await ds.initialize();
  try {
    await ds.runMigrations();
  } finally {
    await ds.destroy();
  }
}

export async function bootTestApp(
  databaseUrl: string,
  overrides?: { redisUrl?: string },
): Promise<INestApplication> {
  process.env.NODE_ENV = 'test';
  process.env.DATABASE_URL = databaseUrl;
  process.env.REDIS_URL = overrides?.redisUrl ?? REDIS_URL;
  process.env.PORT = '3000';
  process.env.RULESET_VERSION = '1.0.0';
  // ConfigModule reads env at module creation (below), not at import
  // time, so static imports are safe. Do NOT jest.resetModules() here:
  // it reloads a second copy of @nestjs/core and breaks DI (ModuleRef).
  const moduleRef = await Test.createTestingModule({
    imports: [AppModule],
  }).compile();
  const app = moduleRef.createNestApplication();
  await createApp(app);
  await app.init();
  return app;
}

/**
 * Clears all rate-limit / login-throttle counters in the shared local
 * Redis. Every spec file clears them in beforeEach: all supertest
 * traffic comes from one IP, so without this the per-IP limits would
 * leak between tests (by design — the limits are real). Rate-limit
 * tests then build their flood inside a single test.
 */
export class RateLimitCleaner {
  private readonly redis = new Redis(REDIS_URL, {
    lazyConnect: true,
    maxRetriesPerRequest: 3,
    retryStrategy: (times: number) => Math.min(times * 50, 2000),
  });

  async clear(): Promise<void> {
    const keys = await this.redis.keys('ratelimit:*');
    if (keys.length > 0) await this.redis.del(...keys);
  }

  async quit(): Promise<void> {
    this.redis.disconnect();
  }
}

let counter = 0;

/** A unique user per call (unique email + username, valid password). */
export function uniqueUser(): {
  email: string;
  username: string;
  password: string;
  displayName: string;
} {
  counter += 1;
  const tag = `${counter}${Math.random().toString(36).slice(2, 8)}`;
  return {
    email: `u${tag}@example.com`,
    username: `u_${tag}`,
    password: 'CorrectHorse!9',
    displayName: `User ${counter}`,
  };
}
