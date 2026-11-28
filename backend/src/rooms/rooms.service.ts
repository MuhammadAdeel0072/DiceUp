import {
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
  Optional,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DataSource, EntityManager, In } from 'typeorm';
import { ErrorCode } from '../common/errors/error-codes';
import { isUniqueViolationError } from '../common/errors/unique-violation';
import type { AppConfig } from '../config/configuration';
import { RedisService } from '../redis/redis.service';
import { Profile } from '../users/entities/profile.entity';
import { User } from '../users/entities/user.entity';
import { GameConfiguration } from './entities/game-configuration.entity';
import { Match } from './entities/match.entity';
import { MatchPlayer, SEAT_COLOURS } from './entities/match-player.entity';
import { MoveEvent } from './entities/move-event.entity';
import { Room } from './entities/room.entity';
import { RoomMember } from './entities/room-member.entity';
import { RoomBroadcaster } from './room-broadcaster';
import { generateRoomCode, normalizeRoomCode } from './room-code';

/** One member of a room, as clients see it (FR-46 readiness). */
export interface RoomMemberView {
  userId: string;
  username: string;
  displayName: string;
  isReady: boolean;
  isHost: boolean;
  joinedAt: string;
}

/** A room with its members, as returned by REST and `room:updated`. */
export interface RoomView {
  id: string;
  code: string;
  hostId: string;
  maxPlayers: number;
  status: string;
  rulesetVersion: string;
  source: string;
  createdAt: string;
  closedAt: string | null;
  members: RoomMemberView[];
  /** Set once the room has started (FR-47). */
  matchId: string | null;
}

/** The `match:started` broadcast payload (SDD §12.6). */
export interface MatchStartedView {
  matchId: string;
  roomId: string;
  seats: Array<{ userId: string; seat: number; colour: string }>;
  rulesetVersion: string;
  /** Player to move first (seat 0). */
  currentPlayerId: string;
  /** Deadline of the first turn (Stage 6, FR-52). */
  turnEndsAt: string;
}

/** Empty-room age before the sweeper closes it (FR-59, G-8). */
export const EMPTY_ROOM_MAX_AGE_MINUTES = 10;

/** Code-collision retries before create gives up (23505, near-impossible). */
const CREATE_CODE_ATTEMPTS = 8;

/**
 * RoomsService (Phase 5, Stage 3; FR-43/44/46/47/59, SDD §5.2.3).
 *
 * Concurrency discipline (assessment §12.2, same class as H-02):
 * every membership-changing operation runs in one transaction with a
 * `pessimistic_write` row lock on the room, and the checks (open?
 * full? already a member?) are re-done inside the lock — never a
 * pre-check alone. The PKs on `room_members` / `match_players` are
 * the backstop: a concurrent insert that slips past still fails
 * 23505 instead of double-seating. Room-code uniqueness is the
 * partial unique index; create retries with a fresh code on 23505.
 *
 * Broadcasting: after each committed change the service emits
 * `room:updated` (or `match:started`) through RoomBroadcaster, so
 * REST and socket callers share one notification path. The gateway
 * joins the socket.io room separately — the broadcast is addressed
 * to `room:{roomId}` and reaches every socket already in it.
 *
 * Out of scope here (recorded, not silently assumed): mid-match
 * leave/forfeit (Stage 6 — `leaveRoom` on a playing room is 409
 * INVALID_STATE), room-limit changes after creation (G-1), and
 * friend-graph invitations (FR-60–62, Stage 3 — see
 * `inviteFriend` on the Flutter side, which shares the code).
 */
@Injectable()
export class RoomsService {
  private readonly logger = new Logger(RoomsService.name);

  constructor(
    private readonly dataSource: DataSource,
    private readonly config: ConfigService,
    private readonly broadcaster: RoomBroadcaster,
    /**
     * Optional so unit tests can keep constructing the service with
     * three arguments; without it the Redis-down refusal is skipped
     * (pre-Stage 5 behaviour). In the app RedisService is global,
     * so it is always injected there.
     */
    @Optional() private readonly redis?: RedisService,
  ) {}

  /** The frozen ruleset version for every Phase 5 match (OD-11). */
  get rulesetVersion(): string {
    return this.config.getOrThrow<AppConfig>('app').rulesetVersion;
  }

  /** The seeded game_configurations row (G-4/C-11 source of 30/60/3). */
  async getGameConfiguration(): Promise<GameConfiguration | null> {
    return this.dataSource
      .getRepository(GameConfiguration)
      .findOne({ where: { version: this.rulesetVersion } });
  }

  // -- Reads ---------------------------------------------------------------

  /** True when the user is a member of any open room. */
  async isUserInOpenRoom(userId: string): Promise<boolean> {
    const row = await this.dataSource.query(
      `SELECT 1 FROM "room_members" m
        JOIN "rooms" r ON r."id" = m."room_id"
       WHERE m."user_id" = $1 AND r."status" = 'open' LIMIT 1`,
      [userId],
    );
    return row.length > 0;
  }

  /** The open room the user is a member of, or null. */
  async getOpenRoomIdForUser(userId: string): Promise<string | null> {
    const rows = await this.dataSource.query(
      `SELECT m."room_id" AS "roomId" FROM "room_members" m
        JOIN "rooms" r ON r."id" = m."room_id"
       WHERE m."user_id" = $1 AND r."status" = 'open' LIMIT 1`,
      [userId],
    );
    return rows.length > 0 ? (rows[0].roomId as string) : null;
  }

  /** True when the user is a player in an in-progress match. */
  async isUserInActiveMatch(userId: string): Promise<boolean> {
    const row = await this.dataSource.query(
      `SELECT 1 FROM "match_players" p
        JOIN "matches" m ON m."id" = p."match_id"
       WHERE p."user_id" = $1 AND m."status" = 'in_progress' LIMIT 1`,
      [userId],
    );
    return row.length > 0;
  }

  /** Load a room view; null when the room does not exist. */
  async findRoomView(roomId: string): Promise<RoomView | null> {
    const room = await this.dataSource
      .getRepository(Room)
      .findOne({ where: { id: roomId } });
    if (!room) return null;
    return this.toRoomView(room);
  }

  /** A room view for a member; 403 NOT_ROOM_MEMBER otherwise. */
  async getRoomViewForMember(
    roomId: string,
    userId: string,
  ): Promise<RoomView> {
    const room = await this.dataSource
      .getRepository(Room)
      .findOne({ where: { id: roomId } });
    if (!room) {
      throw new NotFoundException({
        code: ErrorCode.RoomNotFound,
        message: 'Room not found.',
      });
    }
    const member = await this.dataSource
      .getRepository(RoomMember)
      .findOne({ where: { roomId, userId } });
    if (!member) {
      throw new ForbiddenException({
        code: ErrorCode.NotRoomMember,
        message: 'You are not a member of this room.',
      });
    }
    return this.toRoomView(room);
  }

  // -- Create / join / leave / ready / start -------------------------------

  /** Create a room (FR-43): the caller becomes host + first member. */
  async createRoom(hostId: string, maxPlayers: number): Promise<RoomView> {
    let lastError: unknown;
    for (let attempt = 0; attempt < CREATE_CODE_ATTEMPTS; attempt += 1) {
      const code = generateRoomCode();
      try {
        const room = await this.dataSource.transaction(async (manager) => {
          await this.assertCanEnterRoom(manager, hostId);
          const created = manager.getRepository(Room).create({
            code,
            hostId,
            maxPlayers,
            status: 'open',
            rulesetVersion: this.rulesetVersion,
            source: 'manual',
          });
          await manager.getRepository(Room).save(created);
          await manager.getRepository(RoomMember).save(
            manager.getRepository(RoomMember).create({
              roomId: created.id,
              userId: hostId,
              isReady: false,
              isHost: true,
            }),
          );
          return created;
        });
        const view = await this.toRoomView(room);
        this.broadcaster.emitRoomUpdated(view);
        return view;
      } catch (err) {
        // A code collision is the only retryable failure: the index
        // says this code is taken by another open room — try fresh.
        if (isUniqueViolationError(err)) {
          lastError = err;
          continue;
        }
        throw err;
      }
    }
    this.logger.error(
      `createRoom: ${CREATE_CODE_ATTEMPTS} code collisions in a row (host=${hostId})`,
    );
    throw lastError;
  }

  /**
   * Create a room for a matchmaking group (FR-45). `userIds` are in
   * enqueue order; the first is host, seats follow the same order.
   * Returns the room, or the list of users who became ineligible
   * between queueing and grouping (suspended / entered another room
   * or match) — the caller re-queues the rest. No room is created
   * when anyone is ineligible.
   */
  async createRoomForMatchmaking(
    userIds: string[],
  ): Promise<{ room: RoomView } | { ineligible: string[] }> {
    const ineligible: string[] = [];
    for (const userId of userIds) {
      const [inRoom, inMatch, active] = await Promise.all([
        this.isUserInOpenRoom(userId),
        this.isUserInActiveMatch(userId),
        this.isUserActive(userId),
      ]);
      if (inRoom || inMatch || !active) ineligible.push(userId);
    }
    if (ineligible.length > 0) return { ineligible };
    const code = generateRoomCode();
    const room = await this.dataSource.transaction(async (manager) => {
      const created = manager.getRepository(Room).create({
        code,
        hostId: userIds[0],
        maxPlayers: 4,
        status: 'open',
        rulesetVersion: this.rulesetVersion,
        source: 'matchmaking',
      });
      await manager.getRepository(Room).save(created);
      // Stagger joined_at by 1 ms per member: all four rows are
      // written in one transaction (one timestamp), so without this
      // the join order — which becomes the seat order at match start
      // (G-11, DA-03) — would collapse to the user-id tiebreak.
      const base = Date.now();
      const members = userIds.map((userId, index) =>
        manager.getRepository(RoomMember).create({
          roomId: created.id,
          userId,
          isReady: false,
          isHost: index === 0,
          joinedAt: new Date(base + index),
        }),
      );
      await manager.getRepository(RoomMember).save(members);
      return created;
    });
    const view = await this.toRoomView(room);
    this.broadcaster.emitRoomUpdated(view);
    return { room: view };
  }

  /** Join an open room by code (FR-44). Idempotent for a member. */
  async joinByCode(userId: string, rawCode: string): Promise<RoomView> {
    const code = normalizeRoomCode(rawCode);
    const existing = await this.dataSource
      .getRepository(Room)
      .findOne({ where: { code } });
    if (!existing || existing.status === 'closed') {
      throw new NotFoundException({
        code: ErrorCode.RoomNotFound,
        message: 'No open room has that code.',
      });
    }
    if (existing.status === 'playing') {
      throw new ConflictException({
        code: ErrorCode.RoomStarted,
        message: 'That room has already started.',
      });
    }
    const room = await this.dataSource.transaction(async (manager) => {
      const rooms = manager.getRepository(Room);
      const locked = await rooms.findOne({
        where: { id: existing.id },
        lock: { mode: 'pessimistic_write' },
      });
      if (!locked || locked.status !== 'open') {
        throw new ConflictException({
          code: ErrorCode.RoomStarted,
          message: 'That room has already started.',
        });
      }
      const members = manager.getRepository(RoomMember);
      const already = await members.findOne({
        where: { roomId: locked.id, userId },
      });
      if (already) return locked;
      const count = await members.count({ where: { roomId: locked.id } });
      if (count >= locked.maxPlayers) {
        throw new ConflictException({
          code: ErrorCode.RoomFull,
          message: 'That room is full.',
        });
      }
      await this.assertCanEnterRoom(manager, userId);
      try {
        await members.save(
          members.create({
            roomId: locked.id,
            userId,
            isReady: false,
            isHost: false,
          }),
        );
      } catch (err) {
        // Backstop for the race the lock cannot see (a concurrent
        // join of the same user slipping past the check): the PK
        // says the membership already exists — treat as idempotent.
        if (isUniqueViolationError(err)) return locked;
        throw err;
      }
      return locked;
    });
    const view = await this.toRoomView(room);
    this.broadcaster.emitRoomUpdated(view);
    return view;
  }

  /**
   * Leave a room (FR-59). Host transfer goes to the longest-present
   * member (earliest joined_at, user id breaks ties); an empty room
   * closes. A playing room cannot be left here — mid-match leave is
   * a forfeit (Stage 6).
   */
  async leaveRoom(userId: string, roomId: string): Promise<RoomView> {
    const room = await this.dataSource.transaction(async (manager) => {
      const rooms = manager.getRepository(Room);
      const locked = await rooms.findOne({
        where: { id: roomId },
        lock: { mode: 'pessimistic_write' },
      });
      if (!locked) {
        throw new NotFoundException({
          code: ErrorCode.RoomNotFound,
          message: 'Room not found.',
        });
      }
      if (locked.status === 'playing') {
        throw new ConflictException({
          code: ErrorCode.InvalidState,
          message: 'You cannot leave a match that has started.',
        });
      }
      if (locked.status === 'closed') {
        throw new NotFoundException({
          code: ErrorCode.RoomNotFound,
          message: 'Room not found.',
        });
      }
      const members = manager.getRepository(RoomMember);
      const leaving = await members.findOne({
        where: { roomId, userId },
      });
      if (!leaving) {
        throw new ForbiddenException({
          code: ErrorCode.NotRoomMember,
          message: 'You are not a member of this room.',
        });
      }
      await members.delete({ roomId, userId });
      const remaining = await members.find({
        where: { roomId },
        order: { joinedAt: 'ASC', userId: 'ASC' },
      });
      if (remaining.length === 0) {
        locked.status = 'closed';
        locked.closedAt = new Date();
        await rooms.save(locked);
        return locked;
      }
      if (leaving.isHost) {
        const nextHost = remaining[0];
        nextHost.isHost = true;
        await members.save(nextHost);
        locked.hostId = nextHost.userId;
        await rooms.save(locked);
      }
      return locked;
    });
    const view = await this.toRoomView(room);
    this.broadcaster.emitRoomUpdated(view);
    return view;
  }

  /** Set one member's readiness (FR-46). */
  async setReady(
    userId: string,
    roomId: string,
    ready: boolean,
  ): Promise<RoomView> {
    const room = await this.dataSource.transaction(async (manager) => {
      const rooms = manager.getRepository(Room);
      const locked = await rooms.findOne({
        where: { id: roomId },
        lock: { mode: 'pessimistic_write' },
      });
      if (!locked || locked.status !== 'open') {
        throw new NotFoundException({
          code: ErrorCode.RoomNotFound,
          message: 'Room not found.',
        });
      }
      const members = manager.getRepository(RoomMember);
      const member = await members.findOne({
        where: { roomId, userId },
      });
      if (!member) {
        throw new ForbiddenException({
          code: ErrorCode.NotRoomMember,
          message: 'You are not a member of this room.',
        });
      }
      member.isReady = ready;
      await members.save(member);
      return locked;
    });
    const view = await this.toRoomView(room);
    this.broadcaster.emitRoomUpdated(view);
    return view;
  }

  /**
   * Start the match (FR-47): host only, ≥ 2 present, all ready.
   * Creates the match + match_players seats in join order (G-11,
   * DA-03) + the `match_started` move event (seq 1) in one
   * transaction, then flips the room to playing. Stage 6 arms the
   * first turn timer in the same transaction (deadline = now +
   * turn seconds from the seeded config, epoch 1) — the sweeper
   * fires it; the first player is seat 0.
   */
  async startMatch(hostId: string, roomId: string): Promise<MatchStartedView> {
    // Stage 5 (assessment risk 5): a new online match needs the
    // per-match Redis lock and the Redis adapter for broadcasts, so
    // while Redis is down no new match may start. In-progress
    // matches are unaffected — they continue on the node holding
    // them (MatchService's local-mutex fallback).
    if (this.redis && !(await this.redis.ping())) {
      throw new ServiceUnavailableException({
        code: ErrorCode.MatchUnavailable,
        message:
          'Online matches are unavailable while Redis is down. Try again later.',
      });
    }
    const gameConfig = await this.getGameConfiguration();
    const turnSeconds = gameConfig?.turnTimerSeconds ?? 30;
    const firstDeadline = new Date(Date.now() + turnSeconds * 1000);
    const result = await this.dataSource.transaction(async (manager) => {
      const rooms = manager.getRepository(Room);
      const locked = await rooms.findOne({
        where: { id: roomId },
        lock: { mode: 'pessimistic_write' },
      });
      if (!locked) {
        throw new NotFoundException({
          code: ErrorCode.RoomNotFound,
          message: 'Room not found.',
        });
      }
      if (locked.hostId !== hostId) {
        throw new ForbiddenException({
          code: ErrorCode.NotRoomHost,
          message: 'Only the host can start the match.',
        });
      }
      if (locked.status !== 'open') {
        throw new ConflictException({
          code: ErrorCode.InvalidState,
          message: 'That room has already started.',
        });
      }
      const members = await manager.getRepository(RoomMember).find({
        where: { roomId },
        order: { joinedAt: 'ASC', userId: 'ASC' },
      });
      if (members.length < 2) {
        throw new ConflictException({
          code: ErrorCode.InvalidState,
          message: 'At least 2 players are needed to start.',
        });
      }
      if (members.some((m) => !m.isReady)) {
        throw new ConflictException({
          code: ErrorCode.InvalidState,
          message: 'Every player must be ready before the match starts.',
        });
      }
      const match = await manager.getRepository(Match).save(
        manager.getRepository(Match).create({
          roomId,
          rulesetVersion: locked.rulesetVersion,
          status: 'in_progress',
          turnEndsAt: firstDeadline,
          turnEpoch: 1,
        }),
      );
      const seats = members.map((m, index) => ({
        userId: m.userId,
        seat: index,
        colour: SEAT_COLOURS[index],
      }));
      await manager.getRepository(MatchPlayer).save(
        seats.map((s) =>
          manager.getRepository(MatchPlayer).create({
            matchId: match.id,
            userId: s.userId,
            seat: s.seat,
            colour: s.colour,
          }),
        ),
      );
      await manager.getRepository(MoveEvent).save(
        manager.getRepository(MoveEvent).create({
          matchId: match.id,
          seqNo: 1,
          actorId: hostId,
          type: 'match_started',
          payload: {
            roomId,
            rulesetVersion: locked.rulesetVersion,
            seats,
          },
          requestId: null,
        }),
      );
      locked.status = 'playing';
      await rooms.save(locked);
      return { match, seats, rulesetVersion: locked.rulesetVersion };
    });
    const started: MatchStartedView = {
      matchId: result.match.id,
      roomId,
      seats: result.seats,
      rulesetVersion: result.rulesetVersion,
      currentPlayerId: result.seats[0].userId,
      turnEndsAt: firstDeadline.toISOString(),
    };
    const view = await this.toRoomView(roomId);
    if (view) this.broadcaster.emitRoomUpdated(view);
    this.broadcaster.emitMatchStarted(roomId, started);
    return started;
  }

  /**
   * Close open rooms that have sat empty for 10+ minutes (FR-59,
   * G-8). Returns the number closed. Called by the sweeper cron and
   * directly by tests. Only empty rooms close — a room with members
   * never ages out, however old it is.
   */
  async sweepEmptyRooms(): Promise<number> {
    const result = await this.dataSource
      .getRepository(Room)
      .createQueryBuilder()
      .update(Room)
      .set({ status: 'closed', closedAt: () => 'now()' })
      .where(`"status" = 'open'`)
      .andWhere(`"created_at" < now() - make_interval(mins => :minutes)`, {
        minutes: EMPTY_ROOM_MAX_AGE_MINUTES,
      })
      .andWhere(
        `NOT EXISTS (SELECT 1 FROM "room_members" m WHERE m."room_id" = "rooms"."id")`,
      )
      .execute();
    const closed = result.affected ?? 0;
    if (closed > 0) {
      this.logger.log(`Empty-room sweeper closed ${closed} room(s)`);
    }
    return closed;
  }

  // -- Helpers ---------------------------------------------------------------

  /** A user may enter a room only when in no open room / active match. */
  private async assertCanEnterRoom(
    manager: EntityManager,
    userId: string,
  ): Promise<void> {
    const inRoom = await manager
      .getRepository(RoomMember)
      .createQueryBuilder('m')
      .innerJoin(Room, 'r', 'r.id = m.roomId')
      .where('m.userId = :userId', { userId })
      .andWhere(`r.status = 'open'`)
      .getCount();
    if (inRoom > 0) {
      throw new ConflictException({
        code: ErrorCode.AlreadyInRoom,
        message: 'You are already in a room.',
      });
    }
    const inMatch = await manager
      .getRepository(MatchPlayer)
      .createQueryBuilder('p')
      .innerJoin(Match, 'm', 'm.id = p.matchId')
      .where('p.userId = :userId', { userId })
      .andWhere(`m.status = 'in_progress'`)
      .getCount();
    if (inMatch > 0) {
      throw new ConflictException({
        code: ErrorCode.AlreadyInMatch,
        message: 'You are already in an active match.',
      });
    }
  }

  /** True when the user's account is active (matchmaking re-check). */
  private async isUserActive(userId: string): Promise<boolean> {
    const user = await this.dataSource
      .getRepository(User)
      .findOne({ where: { id: userId } });
    return user?.status === 'active';
  }

  /** Build the client view of a room (members in join order). */
  private async toRoomView(room: Room | string): Promise<RoomView> {
    const full =
      typeof room === 'string'
        ? await this.dataSource
            .getRepository(Room)
            .findOne({ where: { id: room } })
        : room;
    if (!full) {
      throw new NotFoundException({
        code: ErrorCode.RoomNotFound,
        message: 'Room not found.',
      });
    }
    const members = await this.dataSource.getRepository(RoomMember).find({
      where: { roomId: full.id },
      order: { joinedAt: 'ASC', userId: 'ASC' },
    });
    const userIds = members.map((m) => m.userId);
    const users =
      userIds.length > 0
        ? await this.dataSource
            .getRepository(User)
            .find({ where: { id: In(userIds) } })
        : [];
    const profiles =
      userIds.length > 0
        ? await this.dataSource
            .getRepository(Profile)
            .find({ where: { userId: In(userIds) } })
        : [];
    const userById = new Map(users.map((u) => [u.id, u]));
    const profileById = new Map(profiles.map((p) => [p.userId, p]));
    const match = await this.dataSource
      .getRepository(Match)
      .findOne({ where: { roomId: full.id } });
    return {
      id: full.id,
      code: full.code,
      hostId: full.hostId,
      maxPlayers: full.maxPlayers,
      status: full.status,
      rulesetVersion: full.rulesetVersion,
      source: full.source,
      createdAt: full.createdAt.toISOString(),
      closedAt: full.closedAt ? full.closedAt.toISOString() : null,
      members: members.map((m) => ({
        userId: m.userId,
        username: userById.get(m.userId)?.username ?? 'unknown',
        displayName:
          profileById.get(m.userId)?.displayName ??
          userById.get(m.userId)?.username ??
          'unknown',
        isReady: m.isReady,
        isHost: m.isHost,
        joinedAt: m.joinedAt.toISOString(),
      })),
      matchId: match ? match.id : null,
    };
  }
}
