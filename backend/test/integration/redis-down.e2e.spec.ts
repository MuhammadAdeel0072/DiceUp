import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import {
  bootTestApp,
  createScratchDb,
  dropScratchDb,
  migrateScratchDb,
  uniqueUser,
} from './test-helpers';

/**
 * Dead-Redis boot (Stage 4, H-01 — regression test).
 *
 * Before the fix the process DIED at boot with an uncaught
 * MaxRetriesPerRequestError when Redis was down: the Socket.IO Redis
 * adapter issues SUBSCRIBE on its pub/sub clients internally without
 * a rejection handler, so ioredis flushing the queued SUBSCRIBE
 * killed the process in <1 s and /health could never answer. The fix
 * (maxRetriesPerRequest: null on the adapter clients) lets the app
 * boot degraded: liveness answers, readiness reports redis down, and
 * auth writes fail CLOSED (503) instead of running unthrottled.
 *
 * Uses a dead port (6399 — nothing listens there) as the Redis URL,
 * with a real scratch PostgreSQL database.
 */
describe('dead-Redis boot (real PostgreSQL, Redis down)', () => {
  let dbName: string;
  let app: INestApplication;

  const api = () => request(app.getHttpServer());

  beforeAll(async () => {
    const { name, url } = await createScratchDb();
    dbName = name;
    await migrateScratchDb(url);
    app = await bootTestApp(url, {
      redisUrl: 'redis://127.0.0.1:6399',
    });
  }, 120000);

  afterAll(async () => {
    if (app) await app.close();
    if (dbName) await dropScratchDb(dbName);
    // bootTestApp overwrote process.env.REDIS_URL with the dead URL;
    // restore the shared default so later spec files boot against the
    // real Redis (each file also sets it in its own bootTestApp call,
    // but do not leave the dead value behind regardless).
    process.env.REDIS_URL = 'redis://127.0.0.1:6379';
  });

  it('boots and answers liveness with Redis down', async () => {
    const res = await api().get('/v1/health');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      success: true,
      data: { status: 'ok' },
    });
  });

  it('readiness reports redis down (and database up) with 503', async () => {
    const res = await api().get('/v1/health/ready');
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('SERVICE_UNAVAILABLE');
    expect(res.body.error.data.database).toBe('up');
    expect(res.body.error.data.redis).toBe('down');
  });

  it('auth writes fail CLOSED (503), never unthrottled', async () => {
    const u = uniqueUser();
    const res = await api().post('/v1/auth/register').send(u);
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe('SERVICE_UNAVAILABLE');
  });
});
