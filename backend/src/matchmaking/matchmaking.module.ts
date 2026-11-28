import { Module } from '@nestjs/common';
import { RedisModule } from '../redis/redis.module';
import { RoomsModule } from '../rooms/rooms.module';
import { MatchmakingController } from './matchmaking.controller';
import { MatchmakingService } from './matchmaking.service';

/**
 * MatchmakingModule (Phase 5, Stage 3; SDD §5.2.4). Groups through
 * RoomsService (room creation + eligibility) and notifies through
 * RoomBroadcaster (exported by RoomsModule). Exports the service for
 * the gateway, which removes a disconnecting socket's queue entry.
 */
@Module({
  imports: [RedisModule, RoomsModule],
  controllers: [MatchmakingController],
  providers: [MatchmakingService],
  exports: [MatchmakingService],
})
export class MatchmakingModule {}
