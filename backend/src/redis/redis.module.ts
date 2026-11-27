import { Global, Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import Redis from 'ioredis';
import { REDIS_CLIENT, RedisService } from './redis.service';

/**
 * RedisModule — global (plan §3.2). Owns the single ioredis client,
 * built from validated REDIS_URL. `maxRetriesPerRequest: 3` and a
 * bounded retry strategy keep a dead Redis from hanging requests or
 * crash-looping silently; `lazyConnect` lets the app boot when Redis
 * is down so /health can still answer and readiness reports it.
 */
@Global()
@Module({
  imports: [ConfigModule],
  providers: [
    {
      provide: REDIS_CLIENT,
      inject: [ConfigService],
      useFactory: (config: ConfigService) =>
        // NOTE (Stage 3): `app.redisUrl`, not top-level `REDIS_URL` —
        // same validated-env freeze as DatabaseModule (see its comment):
        // the top-level key is frozen from backend/.env at import time
        // and ignores a later process.env assignment.
        new Redis(config.getOrThrow<string>('app.redisUrl'), {
          lazyConnect: true,
          maxRetriesPerRequest: 3,
          retryStrategy: (times: number) => Math.min(times * 50, 2000),
        }),
    },
    RedisService,
  ],
  exports: [RedisService, REDIS_CLIENT],
})
export class RedisModule {}
