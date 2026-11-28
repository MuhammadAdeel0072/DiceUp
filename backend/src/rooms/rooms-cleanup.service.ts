import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { RoomsService } from './rooms.service';

/**
 * RoomCleanupService (FR-59, G-8) — follows the AuthCleanupService
 * pattern (daily cron there; here every minute, because the rule is
 * "empty for 10 minutes"). Only rooms with zero members age out; a
 * room with members never closes on a timer, however old it is.
 * The cron is the safety net for orphaned rooms (e.g. a create whose
 * client vanished, UC-06 E1); normal leaves close an emptied room
 * immediately in RoomsService.
 */
@Injectable()
export class RoomCleanupService {
  private readonly logger = new Logger(RoomCleanupService.name);

  constructor(private readonly rooms: RoomsService) {}

  @Cron('*/1 * * * *')
  async sweepEmptyRooms(): Promise<number> {
    const closed = await this.rooms.sweepEmptyRooms();
    if (closed > 0) {
      this.logger.log(`Empty-room sweeper closed ${closed} room(s)`);
    }
    return closed;
  }
}
