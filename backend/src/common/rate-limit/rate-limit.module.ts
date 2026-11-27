import { Module } from '@nestjs/common';
import { RedisModule } from '../../redis/redis.module';
import { RateLimitService } from './rate-limit.service';

/** Provides RateLimitService (plan §6.5) to the auth/user modules. */
@Module({
  imports: [RedisModule],
  providers: [RateLimitService],
  exports: [RateLimitService],
})
export class RateLimitModule {}
