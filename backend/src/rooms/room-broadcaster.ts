import { Inject, Injectable, Logger, Optional } from '@nestjs/common';
import type { Namespace, Socket } from 'socket.io';
import type { MatchStartedView, RoomView } from './rooms.service';
import { RedisService } from '../redis/redis.service';

/**
 * How long a Redis health verdict is cached for the broadcast gate
 * (Stage 5): one Redis PING per second at most, however many game
 * events flow through. A stale "down" verdict delays remote fan-out
 * by at most a second after Redis recovers.
 */
const BROADCAST_HEALTH_CACHE_MS = 1000;

/**
 * RoomBroadcaster — the one place that emits room/matchmaking events
 * to sockets (Phase 5, Stage 3).
 *
 * Why a separate service instead of injecting the gateway: the
 * gateway lives in SocketModule, while RoomsService (REST) and
 * MatchmakingService also need to broadcast. Injecting the gateway
 * into those modules would be a module cycle (SocketModule imports
 * them for the gateway handlers). Instead the gateway attaches the
 * `/game` Namespace here at init (`attach`), and every other service
 * emits through this narrow surface. Before attach (unit tests that
 * never boot the gateway) emits are dropped with a warning — the
 * database write they follow has already committed, so nothing is
 * lost but the notification.
 *
 * Rooms: `room:{roomId}` (members), `user:{userId}` (one player's
 * sockets — the gateway joins each socket to its user room on
 * connect, so a matchmaking result reaches a player who is not in
 * any socket room yet).
 *
 * Game broadcasts (Stage 5) go through `emitGameEvent`, which is
 * Redis-health gated (assessment risk 5): while Redis is up, the
 * event fans out through the adapter as usual; while Redis is down,
 * the adapter's publish queue would grow without bound, so the
 * event is delivered directly to the match members' LOCAL sockets
 * only and the remote fan-out is dropped + counted. In-progress
 * matches therefore continue on the node holding them, with no
 * unbounded queue. Lobby broadcasts (`room:updated`,
 * `match:started`, `matchmaking:matched`) are NOT gated — they are
 * human-paced (a few per minute at most), so their adapter queue
 * stays bounded in practice; only the machine-paced per-turn game
 * traffic needed the gate.
 */
@Injectable()
export class RoomBroadcaster {
  private readonly logger = new Logger(RoomBroadcaster.name);
  private server: Namespace | null = null;

  /** Remote game fan-outs dropped while Redis was down (gate). */
  private droppedRemoteBroadcasts = 0;
  /** Cached Redis health verdict for the gate (see above). */
  private lastHealthy = true;
  private healthyUntil = 0;

  /**
   * RedisService is optional so unit tests can keep constructing
   * `new RoomBroadcaster()` with no arguments; without it the gate
   * treats Redis as healthy (the pre-Stage 5 behaviour).
   */
  constructor(
    @Optional() @Inject(RedisService) private readonly redis?: RedisService,
  ) {}

  /** Called by the gateway in afterInit; the only writer. */
  attach(server: Namespace): void {
    this.server = server;
  }

  /** How many remote game fan-outs the gate has dropped (tests). */
  getDroppedRemoteBroadcasts(): number {
    return this.droppedRemoteBroadcasts;
  }

  /**
   * Redis health for the broadcast gate, cached for
   * BROADCAST_HEALTH_CACHE_MS. True when no RedisService was
   * injected (unit tests, pre-Stage 5 behaviour).
   */
  async isRedisHealthy(): Promise<boolean> {
    if (!this.redis) return true;
    const now = Date.now();
    if (now < this.healthyUntil) return this.lastHealthy;
    try {
      this.lastHealthy = await this.redis.ping();
    } catch {
      this.lastHealthy = false;
    }
    this.healthyUntil = now + BROADCAST_HEALTH_CACHE_MS;
    return this.lastHealthy;
  }

  /** `room:updated { room, members[], ready{} }` (SDD §12.6). */
  emitRoomUpdated(room: RoomView): void {
    this.emitToRoom(room.id, 'room:updated', toRoomUpdatedPayload(room));
  }

  /** `match:started { matchId, seats[], rulesetVersion }` (SDD §12.6). */
  emitMatchStarted(roomId: string, started: MatchStartedView): void {
    this.emitToRoom(roomId, 'match:started', started);
  }

  /** `matchmaking:matched { roomId, roomCode }` to one player. */
  emitMatchmakingMatched(userId: string, room: RoomView): void {
    this.emitToUser(userId, 'matchmaking:matched', {
      roomId: room.id,
      roomCode: room.code,
    });
  }

  emitToRoom(roomId: string, event: string, payload: unknown): void {
    if (!this.server) {
      this.logger.warn(`Dropping ${event}: gateway namespace not attached`);
      return;
    }
    this.server.to(`room:${roomId}`).emit(event, payload);
  }

  /**
   * Game event to a match's members (Stage 5; FR-51).
   *
   * Redis up: the normal adapter fan-out to `room:{roomId}` (all
   * nodes). Redis down: the adapter would queue the publish
   * unboundedly (H-01), so the event goes directly to the members'
   * LOCAL sockets only — `server.sockets` is the local map, no
   * Redis round-trip — and the dropped remote fan-out is counted
   * and logged. Membership is enforced by the caller (MatchService
   * checks it before applying) and by the recipient list: only
   * sockets whose user is in `memberUserIds` receive the event, so
   * a non-member can never be subscribed to a match.
   */
  async emitGameEvent(
    roomId: string,
    memberUserIds: string[],
    event: string,
    payload: unknown,
  ): Promise<void> {
    if (!this.server) {
      this.logger.warn(`Dropping ${event}: gateway namespace not attached`);
      return;
    }
    if (await this.isRedisHealthy()) {
      this.server.to(`room:${roomId}`).emit(event, payload);
      return;
    }
    this.droppedRemoteBroadcasts += 1;
    this.logger.warn(
      `Redis down: delivering ${event} to local match sockets only ` +
        `(room=${roomId}); remote fan-out dropped`,
    );
    const members = new Set(memberUserIds);
    for (const socket of this.server.sockets.values()) {
      const userId = (socket.data as { user?: { id?: string } } | undefined)
        ?.user?.id;
      if (userId && members.has(userId)) {
        (socket as Socket).emit(event, payload);
      }
    }
  }

  emitToUser(userId: string, event: string, payload: unknown): void {
    if (!this.server) {
      this.logger.warn(`Dropping ${event}: gateway namespace not attached`);
      return;
    }
    this.server.to(`user:${userId}`).emit(event, payload);
  }
}

/** The §12.6 `room:updated` shape (ready map derived from members). */
export function toRoomUpdatedPayload(room: RoomView): {
  room: Omit<RoomView, 'members'>;
  members: RoomView['members'];
  ready: Record<string, boolean>;
} {
  const { members, ...roomWithoutMembers } = room;
  return {
    room: roomWithoutMembers,
    members,
    ready: Object.fromEntries(members.map((m) => [m.userId, m.isReady])),
  };
}
