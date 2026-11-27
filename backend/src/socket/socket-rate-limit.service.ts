import {
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { RedisService } from '../redis/redis.service';
import { REDIS_KEYS } from '../redis/redis-keys';
import {
  SOCKET_EVENTS_PER_SECOND,
  SOCKET_EVENT_WINDOW_SECONDS,
} from './socket.constants';

/**
 * SocketRateLimitService (NFR-20, SDD §12.6) — the 20 events/s per
 * connection limiter. One Redis counter per socket id, via the same
 * atomic `incrWithExpiry` primitive the REST limiter uses (plan §5.2),
 * so the window cannot be extended by concurrent increments.
 *
 * Failure policy: fail CLOSED (throws ServiceUnavailableException).
 * The limiter is a security control — running socket events
 * unthrottled because Redis is down would silently drop it (plan
 * §5.2, same rule as the auth-endpoint REST limits). The guard maps
 * the throw to a SERVICE_UNAVAILABLE socket error.
 */
@Injectable()
export class SocketRateLimitService {
  private readonly logger = new Logger(SocketRateLimitService.name);

  constructor(private readonly redis: RedisService) {}

  /** True when this event is within the per-connection budget. */
  async check(socketId: string): Promise<{ allowed: boolean }> {
    let count: number;
    try {
      count = await this.redis.incrWithExpiry(
        REDIS_KEYS.socketRateLimit(socketId),
        SOCKET_EVENT_WINDOW_SECONDS,
      );
    } catch (err) {
      this.logger.error(
        `Socket rate limit unavailable (Redis): ${(err as Error).message}`,
      );
      throw new ServiceUnavailableException(
        'This service is temporarily unavailable. Try again later.',
      );
    }
    return { allowed: count <= SOCKET_EVENTS_PER_SECOND };
  }
}
