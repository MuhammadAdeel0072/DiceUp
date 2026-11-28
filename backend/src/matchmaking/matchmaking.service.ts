import {
  ConflictException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ErrorCode } from '../common/errors/error-codes';
import { REDIS_KEYS } from '../redis/redis-keys';
import { RedisService } from '../redis/redis.service';
import { RoomBroadcaster } from '../rooms/room-broadcaster';
import { RoomsService, type RoomView } from '../rooms/rooms.service';

/** Matchmaking group size (SDD default, C-13; OD-05: IN scope). */
export const MATCHMAKING_GROUP_SIZE = 4;

export type MatchmakingStatus =
  | {
      status: 'queued';
      position: number;
      queueSize: number;
      groupSize: number;
    }
  | {
      status: 'matched';
      roomId: string;
      roomCode: string;
      queueSize: number;
      groupSize: number;
    }
  | { status: 'idle'; queueSize: number; groupSize: number };

export type MatchmakingJoinResult =
  | {
      matched: false;
      position: number;
      queueSize: number;
      groupSize: number;
    }
  | { matched: true; room: RoomView };

/**
 * MatchmakingService (Phase 5, Stage 3; FR-45, SDD §5.2.4).
 *
 * One queue entry per player in the Redis sorted set
 * `matchmaking:queue` (score = enqueue time in ms). Arrival order
 * only — no skill/rank/region criteria (G-2). Grouping is atomic:
 * `popGroup` is one Lua script (check ≥ 4 + remove), so concurrent
 * joiners can never both pop the same four players. The popped four
 * become a room (host = earliest arrival) via RoomsService, which
 * re-checks eligibility in PostgreSQL (suspended / entered another
 * room or match since queueing); anyone ineligible is left out and
 * the eligible remainder are re-queued with a fresh score.
 *
 * No-max-wait / cancel behaviour (G-6, recorded): a queue entry
 * never expires on its own — the player waits until a group forms
 * or cancels (`leave`, or disconnect, which the gateway reports).
 * There is no partial-group start: groups form at exactly 4.
 *
 * Failure policy (SDD §9.4): Redis down → new matchmaking is refused
 * with 503 MATCHMAKING_UNAVAILABLE; REST reads from PostgreSQL keep
 * working. A queued player holds no PostgreSQL row, so a Redis loss
 * only drops waiting players (they re-join), never a match (CI-05).
 * Suspended players never group: REST is refused by the global
 * AccountStatusGuard, and grouping re-checks account status.
 */
@Injectable()
export class MatchmakingService {
  private readonly logger = new Logger(MatchmakingService.name);

  constructor(
    private readonly redis: RedisService,
    private readonly rooms: RoomsService,
    private readonly broadcaster: RoomBroadcaster,
  ) {}

  /** Join the queue; forms a group (and room) when 4 are present. */
  async join(userId: string): Promise<MatchmakingJoinResult> {
    await this.assertRedisAvailable();
    if (await this.rooms.isUserInOpenRoom(userId)) {
      throw new ConflictException({
        code: ErrorCode.AlreadyInRoom,
        message: 'You are already in a room.',
      });
    }
    if (await this.rooms.isUserInActiveMatch(userId)) {
      throw new ConflictException({
        code: ErrorCode.AlreadyInMatch,
        message: 'You are already in an active match.',
      });
    }
    const existing = await this.redis.zscore(
      REDIS_KEYS.matchmakingQueue,
      userId,
    );
    if (existing !== null) {
      throw new ConflictException({
        code: ErrorCode.AlreadyInMatchmaking,
        message: 'You are already in the matchmaking queue.',
      });
    }
    await this.redis.zaddNx(REDIS_KEYS.matchmakingQueue, Date.now(), userId);
    const formed = await this.tryFormGroup();
    if (formed) return { matched: true, room: formed };
    const position = await this.queuePosition(userId);
    const queueSize = await this.redis.zcard(REDIS_KEYS.matchmakingQueue);
    return {
      matched: false,
      position,
      queueSize,
      groupSize: MATCHMAKING_GROUP_SIZE,
    };
  }

  /** Leave the queue (cancel). True when an entry was removed. */
  async leave(userId: string): Promise<{ left: boolean }> {
    await this.assertRedisAvailable();
    const left = await this.redis.zrem(REDIS_KEYS.matchmakingQueue, userId);
    return { left };
  }

  /** Queue position / matched room / idle (for the status screen). */
  async status(userId: string): Promise<MatchmakingStatus> {
    const queueSize = await this.redis
      .zcard(REDIS_KEYS.matchmakingQueue)
      .catch(() => 0);
    const score = await this.redis
      .zscore(REDIS_KEYS.matchmakingQueue, userId)
      .catch(() => null);
    if (score !== null) {
      return {
        status: 'queued',
        position: await this.queuePosition(userId),
        queueSize,
        groupSize: MATCHMAKING_GROUP_SIZE,
      };
    }
    const roomId = await this.rooms.getOpenRoomIdForUser(userId);
    if (roomId) {
      const room = await this.rooms.findRoomView(roomId);
      if (room && room.source === 'matchmaking') {
        return {
          status: 'matched',
          roomId: room.id,
          roomCode: room.code,
          queueSize,
          groupSize: MATCHMAKING_GROUP_SIZE,
        };
      }
    }
    return { status: 'idle', queueSize, groupSize: MATCHMAKING_GROUP_SIZE };
  }

  /**
   * Remove a player from the queue without error (disconnect path —
   * the gateway calls this best-effort; a missing entry is fine).
   */
  async removeFromQueue(userId: string): Promise<void> {
    try {
      await this.redis.zrem(REDIS_KEYS.matchmakingQueue, userId);
    } catch (err) {
      this.logger.warn(
        `Failed to remove ${userId} from the matchmaking queue on disconnect: ${(err as Error).message}`,
      );
    }
  }

  /** 1-based position in the queue (arrival order). */
  private async queuePosition(userId: string): Promise<number> {
    const rank = await this.redis.zrank(REDIS_KEYS.matchmakingQueue, userId);
    return rank === null ? 0 : rank + 1;
  }

  /** Pop a group of 4 and turn it into a room; null when not enough. */
  private async tryFormGroup(): Promise<RoomView | null> {
    const group = await this.redis.popGroup(
      REDIS_KEYS.matchmakingQueue,
      MATCHMAKING_GROUP_SIZE,
    );
    if (group.length === 0) return null;
    const created = await this.rooms.createRoomForMatchmaking(group);
    if ('room' in created) {
      this.logger.log(
        `Matchmaking formed room ${created.room.code} for ${group.length} players`,
      );
      for (const userId of group) {
        this.broadcaster.emitMatchmakingMatched(userId, created.room);
      }
      return created.room;
    }
    // Someone became ineligible after queueing: re-queue the rest
    // with fresh scores (they keep waiting) and form nothing now.
    this.logger.warn(
      `Matchmaking group dissolved: ineligible players ${created.ineligible.join(', ')}`,
    );
    const eligible = group.filter((u) => !created.ineligible.includes(u));
    const now = Date.now();
    for (const userId of eligible) {
      await this.redis.zaddNx(REDIS_KEYS.matchmakingQueue, now, userId);
    }
    return null;
  }

  private async assertRedisAvailable(): Promise<void> {
    if (!(await this.redis.ping())) {
      throw new ServiceUnavailableException({
        code: ErrorCode.MatchmakingUnavailable,
        message: 'Matchmaking is temporarily unavailable.',
      });
    }
  }
}
