import {
  CanActivate,
  ExecutionContext,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { WsException } from '@nestjs/websockets';
import { ErrorCode } from '../common/errors/error-codes';
import { SOCKET_RATE_LIMIT_MAX_VIOLATIONS } from './socket.constants';
import { socketErrorEnvelope } from './socket-error';
import { SocketRateLimitService } from './socket-rate-limit.service';
import type { GameSocket } from './ws-jwt.guard';

/**
 * WsRateLimitGuard (NFR-20, SDD §12.6) — 20 events/s per connection.
 * Runs on every message handler (after WsJwtGuard: an unauthenticated
 * socket never reaches the limiter, and the limiter never sees a
 * principal it cannot attribute). The counter is keyed by socket id,
 * so each connection gets its own budget.
 *
 * Over the limit the event is dropped and the client receives a
 * RATE_LIMITED `exception` with the §6.3 envelope; sustained abuse
 * (SOCKET_RATE_LIMIT_MAX_VIOLATIONS violations on one connection)
 * disconnects the socket (SDD §12.6). The disconnect happens on the
 * violating event, so that event's own `exception` may not arrive —
 * the client still receives the earlier violations' errors plus the
 * `disconnect`, which is the deterministic signal tests assert on.
 */
@Injectable()
export class WsRateLimitGuard implements CanActivate {
  constructor(private readonly limiter: SocketRateLimitService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const client = context.switchToWs().getClient<GameSocket>();
    let allowed: boolean;
    try {
      ({ allowed } = await this.limiter.check(client.id));
    } catch (err) {
      if (err instanceof ServiceUnavailableException) {
        throw new WsException(
          socketErrorEnvelope(
            ErrorCode.ServiceUnavailable,
            'This service is temporarily unavailable. Try again later.',
          ),
        );
      }
      throw err;
    }
    if (allowed) return true;
    const violations = (client.data.rateLimitViolations ?? 0) + 1;
    client.data.rateLimitViolations = violations;
    if (violations >= SOCKET_RATE_LIMIT_MAX_VIOLATIONS) {
      client.disconnect(true);
    }
    throw new WsException(
      socketErrorEnvelope(
        ErrorCode.RateLimited,
        'Too many socket events. Slow down.',
      ),
    );
  }
}
