import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { MatchmakingModule } from '../matchmaking/matchmaking.module';
import { MatchModule } from '../match/match.module';
import { RoomsModule } from '../rooms/rooms.module';
import { GameGateway } from './game.gateway';
import { SocketConnectionRateLimitService } from './socket-connection-rate-limit.service';
import { SocketRateLimitService } from './socket-rate-limit.service';
import { SocketRedisClients } from './socket-redis-clients.service';
import { WsJwtGuard } from './ws-jwt.guard';
import { WsRateLimitGuard } from './ws-rate-limit.guard';

/**
 * SocketModule (plan §3.2/§9) — Socket.IO foundation + Stage 3 rooms.
 * Imports AuthModule for the ONE auth path (TokenService +
 * JwtStrategy, exported there) and the global RedisModule for
 * RedisService. Exports WsJwtGuard so main.ts / the e2e test-app
 * factory can build the Redis adapter with it (the adapter's
 * handshake middleware authenticates through the guard).
 * Stage 3: also imports RoomsModule + MatchmakingModule so the
 * gateway can run room handlers and drop queue entries on disconnect.
 * Stage 5: also imports MatchModule so the gateway can run the
 * gameplay handlers, and provides the connection rate limiter (L-02)
 * the adapter handshake enforces. No presence or match-state
 * provider lives here — those are Phase 5/6.
 */
@Module({
  imports: [AuthModule, RoomsModule, MatchmakingModule, MatchModule],
  providers: [
    GameGateway,
    WsJwtGuard,
    WsRateLimitGuard,
    SocketRateLimitService,
    SocketConnectionRateLimitService,
    SocketRedisClients,
  ],
  exports: [GameGateway, WsJwtGuard, SocketConnectionRateLimitService],
})
export class SocketModule {}
