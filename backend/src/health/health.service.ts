import { Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { RedisService } from '../redis/redis.service';

export type DependencyStatus = 'up' | 'down';

export interface ReadinessStatus {
  status: 'ok' | 'degraded';
  database: DependencyStatus;
  redis: DependencyStatus;
  /** Per-check latency in ms (plan §6.6). No infra details. */
  latencyMs: { database: number; redis: number };
}

/**
 * HealthService — the dependency probes behind GET /v1/health/ready
 * (plan §6.6). PostgreSQL: `SELECT 1` via the TypeORM pool.
 * Redis: PING via RedisService. Each check is timed and reported
 * separately; a failure in one never masks the other, and no
 * credential, connection string, hostname, or stack trace is returned.
 */
@Injectable()
export class HealthService {
  constructor(
    private readonly dataSource: DataSource,
    private readonly redis: RedisService,
  ) {}

  async checkReadiness(): Promise<ReadinessStatus> {
    const dbStart = Date.now();
    let database: DependencyStatus = 'down';
    try {
      await this.dataSource.query('SELECT 1');
      database = 'up';
    } catch {
      database = 'down';
    }
    const dbLatency = Date.now() - dbStart;

    const redisStart = Date.now();
    const redisUp = await this.redis.ping();
    const redis: DependencyStatus = redisUp ? 'up' : 'down';
    const redisLatency = Date.now() - redisStart;

    return {
      status: database === 'up' && redis === 'up' ? 'ok' : 'degraded',
      database,
      redis,
      latencyMs: { database: dbLatency, redis: redisLatency },
    };
  }
}
