import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { GameGateway } from './game.gateway';
import { SocketRateLimitService } from './socket-rate-limit.service';
import { SocketRedisClients } from './socket-redis-clients.service';
import { WsJwtGuard } from './ws-jwt.guard';
import { WsRateLimitGuard } from './ws-rate-limit.guard';

/**
 * SocketModule (plan §3.2/§9) — Socket.IO foundation only.
 * Imports AuthModule for the ONE auth path (TokenService +
 * JwtStrategy, exported there) and the global RedisModule for
 * RedisService. Exports WsJwtGuard so main.ts / the e2e test-app
 * factory can build the Redis adapter with it (the adapter's
 * handshake middleware authenticates through the guard).
 *
 * No game, room, matchmaking, presence, or match-state provider
 * lives here — those are Phase 5/6.
 */
@Module({
  imports: [AuthModule],
  providers: [
    GameGateway,
    WsJwtGuard,
    WsRateLimitGuard,
    SocketRateLimitService,
    SocketRedisClients,
  ],
  exports: [GameGateway, WsJwtGuard],
})
export class SocketModule {}
