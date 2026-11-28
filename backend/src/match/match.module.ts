import { Module } from '@nestjs/common';
import { CryptoDiceRoller } from '../game/dice-roller';
import { RoomsModule } from '../rooms/rooms.module';
import { MATCH_DICE_ROLLER, MatchService } from './match.service';
import { MatchesController } from './matches.controller';

/**
 * MatchModule (Phase 5, Stage 5; FR-49–FR-53, FR-57/58).
 *
 * Owns the match aggregate: MatchService (server-authoritative
 * gameplay, checkpointing, replay, idempotency) and the read-only
 * MatchesController. Imports RoomsModule for RoomBroadcaster (the
 * one emit surface) — RoomsModule does not import MatchModule, so
 * there is no cycle. SocketModule imports this module for the
 * gateway handlers; AppModule imports it for the REST controller.
 *
 * The dice source is an injectable provider: production rolls with
 * CryptoDiceRoller; tests override MATCH_DICE_ROLLER with a
 * FixedDiceRoller for deterministic play.
 */
@Module({
  imports: [RoomsModule],
  controllers: [MatchesController],
  providers: [
    MatchService,
    { provide: MATCH_DICE_ROLLER, useClass: CryptoDiceRoller },
  ],
  exports: [MatchService],
})
export class MatchModule {}
