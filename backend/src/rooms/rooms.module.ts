import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { GameConfiguration } from './entities/game-configuration.entity';
import { Match } from './entities/match.entity';
import { MatchPlayer } from './entities/match-player.entity';
import { MoveEvent } from './entities/move-event.entity';
import { Room } from './entities/room.entity';
import { RoomMember } from './entities/room-member.entity';
import { RoomBroadcaster } from './room-broadcaster';
import { RoomCleanupService } from './rooms-cleanup.service';
import { RoomsController } from './rooms.controller';
import { RoomsService } from './rooms.service';

/**
 * RoomsModule (Phase 5, Stage 3; SDD §5.2.3). Exports RoomsService
 * (MatchmakingModule groups through it; the gateway starts matches
 * through it) and RoomBroadcaster (the one emit surface for room /
 * matchmaking events). ScheduleModule.forRoot() lives in AuthModule
 * — this module only adds the cron provider.
 */
@Module({
  imports: [
    ConfigModule,
    TypeOrmModule.forFeature([
      Room,
      RoomMember,
      Match,
      MatchPlayer,
      MoveEvent,
      GameConfiguration,
    ]),
  ],
  controllers: [RoomsController],
  providers: [RoomsService, RoomBroadcaster, RoomCleanupService],
  exports: [RoomsService, RoomBroadcaster],
})
export class RoomsModule {}
