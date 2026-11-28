import { HttpException, Logger, UseGuards, UsePipes } from '@nestjs/common';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import type { Namespace } from 'socket.io';
import { MatchmakingService } from '../matchmaking/matchmaking.service';
import { MatchService } from '../match/match.service';
import { GameRejectedError } from '../match/match.errors';
import {
  RoomBroadcaster,
  toRoomUpdatedPayload,
} from '../rooms/room-broadcaster';
import { RoomsService } from '../rooms/rooms.service';
import {
  SOCKET_CLIENT_EVENTS,
  SOCKET_NAMESPACE,
  SOCKET_SERVER_EVENTS,
} from './socket.constants';
import { WsRateLimitGuard } from './ws-rate-limit.guard';
import { WsValidationPipe } from './ws-validation.pipe';
import { WsJwtGuard, type GameSocket } from './ws-jwt.guard';
import { ErrorCode } from '../common/errors/error-codes';
import { socketWsException } from './socket-error';
import {
  type ConnectedPayload,
  PingDto,
  type PongPayload,
} from './dto/ping.dto';
import { DiceRollDto, StateRequestDto, TokenMoveDto } from './dto/game.dto';
import {
  MatchStartDto,
  RoomJoinDto,
  RoomLeaveDto,
  RoomReadyDto,
} from './dto/room.dto';

/**
 * GameGateway (plan §9.1/§9.2) — foundation + Phase 5 Stage 3 rooms.
 *
 * What exists: namespace `/game`, authenticated connections (handshake
 * middleware in the adapter + WsJwtGuard on every message), the
 * connect/disconnect lifecycle with logging, the `ping`/`pong`
 * connectivity probe with validation + rate limiting, and the Redis
 * adapter wiring that lets later phases broadcast across nodes.
 *
 * Stage 3 adds the room handlers (SDD §12.6): `room:join` /
 * `room:leave` / `room:ready` / `match:start`, with the broadcasts
 * `room:updated` / `match:started` / `matchmaking:matched`. The
 * authorisation pattern is the one the foundation header prescribed:
 * every handler loads the room from PostgreSQL through RoomsService
 * and checks membership/host there — a client-claimed room id is
 * never trusted. Socket rooms are named `room:{roomId}`; every
 * socket also joins its per-user room `user:{userId}` on connect so
 * matchmaking results reach a player who is in no socket room yet.
 *
 * Stage 5 adds the gameplay handlers (SDD §12.6): `dice:roll` /
 * `token:move` / `state:request`. The gateway does no game logic
 * itself — MatchService owns authority, persistence, idempotency
 * and broadcasts; the gateway only joins the socket to the match's
 * room (after a membership check), forwards intents, delivers a
 * duplicate's original result / a snapshot to the requester, and
 * maps rejections to `action:rejected` (state unchanged) instead of
 * the `exception` channel.
 *
 * Stage 6 adds recovery (FR-54/55/56): presence writes on
 * connect and on every `ping`, disconnect → grace via
 * MatchService (only when the user has no other live socket —
 * a stale socket closing must not forfeit a reconnected player),
 * reconnect → grace cleared + `player:reconnected`, and a
 * mid-match `room:leave` → voluntary forfeit instead of the
 * pre-start leave path.
 */
@WebSocketGateway({ namespace: SOCKET_NAMESPACE })
@UseGuards(WsJwtGuard, WsRateLimitGuard)
@UsePipes(new WsValidationPipe())
export class GameGateway
  implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect
{
  private readonly logger = new Logger(GameGateway.name);

  constructor(
    private readonly rooms: RoomsService,
    private readonly matchmaking: MatchmakingService,
    private readonly matches: MatchService,
    private readonly broadcaster: RoomBroadcaster,
  ) {}

  /**
   * The `/game` Namespace object (Nest assigns the namespace, not the
   * root Server, to @WebSocketServer() on a namespaced gateway).
   * Emitting on it broadcasts to this namespace on this node and, via
   * the Redis adapter, to the same namespace on every other node.
   */
  @WebSocketServer()
  server!: Namespace;

  /**
   * Live sockets per user (Stage 6). A user may hold several
   * sockets at once (reconnect race, second device); only when
   * the LAST one closes is the player really gone, so the
   * disconnect handler consults this set before starting grace.
   */
  private readonly socketsByUser = new Map<string, Set<string>>();

  afterInit(): void {
    this.broadcaster.attach(this.server);
    this.logger.log(
      `Socket.IO gateway initialised on namespace ${SOCKET_NAMESPACE} (Redis adapter)`,
    );
  }

  async handleConnection(client: GameSocket): Promise<void> {
    const user = client.data.user;
    if (!user) {
      // Defence in depth: the handshake middleware authenticates every
      // connection before it reaches here. An unauthenticated socket
      // must never stay connected — if it somehow did, drop it.
      this.logger.warn(
        `Socket ${client.id} connected without a principal — disconnecting`,
      );
      client.disconnect(true);
      return;
    }
    // Per-user room (Stage 3): matchmaking results are addressed to
    // `user:{userId}`, so they reach a player who is in no game room.
    void client.join(`user:${user.id}`);
    let userSockets = this.socketsByUser.get(user.id);
    if (!userSockets) {
      userSockets = new Set();
      this.socketsByUser.set(user.id, userSockets);
    }
    userSockets.add(client.id);
    // Stage 6: a heartbeat (presence, TTL 30 s) + a reconnect
    // check — a player returning inside their grace is cleared
    // here, before any game intent, and the other players hear
    // `player:reconnected`. Both are best-effort: a failure is
    // logged, never a refused connection.
    await this.matches.markPresence(user.id).catch((err: unknown) => {
      this.logger.warn(
        `Presence write failed on connect (user=${user.id}): ${(err as Error).message}`,
      );
    });
    await this.matches.handlePlayerConnected(user.id).catch((err: unknown) => {
      this.logger.warn(
        `Reconnect handling failed (user=${user.id}): ${(err as Error).message}`,
      );
    });
    this.logger.log(
      `Socket connected: user=${user.id} socket=${client.id} ` +
        `appVersion=${client.data.appVersion ?? 'unknown'}`,
    );
    const payload: ConnectedPayload = {
      userId: user.id,
      socketId: client.id,
      connectedAt: new Date().toISOString(),
    };
    client.emit(SOCKET_SERVER_EVENTS.connected, payload);
  }

  async handleDisconnect(client: GameSocket): Promise<void> {
    // A disconnect drops the player from the matchmaking queue (FR-45:
    // remove on disconnect). Room membership survives a disconnect —
    // grace / reconnection is Stage 6, and dropping membership here
    // would forfeit a player for a transient network blip.
    const userId = client.data.user?.id;
    if (userId) {
      const userSockets = this.socketsByUser.get(userId);
      userSockets?.delete(client.id);
      if (userSockets?.size === 0) this.socketsByUser.delete(userId);
      void this.matchmaking.removeFromQueue(userId);
      // Stage 6 (FR-54): only when the user's LAST socket closed
      // does the grace start. A stale socket closing after a
      // reconnect must not mark a live player disconnected. The
      // presence key is cleared so the heartbeat sweeper agrees.
      if (!userSockets || userSockets.size === 0) {
        await this.matches.clearPresence(userId).catch(() => undefined);
        await this.matches
          .handlePlayerDisconnected(userId)
          .catch((err: unknown) => {
            this.logger.warn(
              `Disconnect handling failed (user=${userId}): ${(err as Error).message}`,
            );
          });
      }
    }
    this.logger.log(
      `Socket disconnected: user=${userId ?? 'unknown'} socket=${client.id}`,
    );
  }

  /**
   * Connectivity probe (NOT a game event). The payload was validated
   * by WsValidationPipe (malformed → `VALIDATION_FAILED` exception;
   * >10 KB → `PAYLOAD_TOO_LARGE` exception) and rate-limited by
   * WsRateLimitGuard before this handler runs. Replies `pong` with
   * the echoed `requestId` so the client can match the reply.
   */
  @SubscribeMessage(SOCKET_CLIENT_EVENTS.ping)
  handlePing(
    @ConnectedSocket() client: GameSocket,
    @MessageBody() payload: PingDto,
  ): void {
    const reply: PongPayload = {
      requestId: payload.requestId,
      serverTime: new Date().toISOString(),
    };
    client.emit(SOCKET_SERVER_EVENTS.pong, reply);
    // Stage 6: `ping` is the client heartbeat — refresh presence
    // (the per-message guard refresh covers every other event).
    const userId = client.data.user?.id;
    if (userId) void this.matches.touchPresence(userId);
  }

  // -- Rooms (Stage 3, SDD §12.6) -------------------------------------------
  //
  // Every handler re-validates through RoomsService, which loads the
  // room from PostgreSQL and checks membership/host under a row lock.
  // Service errors are HttpExceptions carrying the §6.3 code; Nest's
  // WsExceptionsHandler turns an uncaught one into an `exception`
  // event only when it is a WsException — so each handler maps the
  // service error to a WsException with the same envelope (see
  // socketWsException), keeping the socket error shape identical to
  // REST. The joiner gets the fresh `room:updated` directly as well
  // as via the room broadcast (they join the socket room after the
  // service broadcast, so a direct emit is the only copy they see).

  /** Join an open room by code (FR-44), then join its socket room. */
  @SubscribeMessage(SOCKET_CLIENT_EVENTS.roomJoin)
  async handleRoomJoin(
    @ConnectedSocket() client: GameSocket,
    @MessageBody() payload: RoomJoinDto,
  ): Promise<void> {
    const user = client.data.user!;
    const room = await toWsError(() =>
      this.rooms.joinByCode(user.id, payload.roomCode),
    );
    await client.join(`room:${room.id}`);
    client.emit(SOCKET_SERVER_EVENTS.roomUpdated, toRoomUpdatedPayload(room));
  }

  /**
   * Leave a room (FR-59), then leave its socket room. Stage 6:
   * leaving a room whose match is in progress is a voluntary
   * mid-match leave — a forfeit (FR-56, BR-15), not a room leave.
   * The UX copy/confirmation is Stage 7; this is the trigger.
   */
  @SubscribeMessage(SOCKET_CLIENT_EVENTS.roomLeave)
  async handleRoomLeave(
    @ConnectedSocket() client: GameSocket,
    @MessageBody() payload: RoomLeaveDto,
  ): Promise<void> {
    const user = client.data.user!;
    const active = await toWsError(() => this.matches.getActiveMatch(user.id));
    if (active && active.roomId === payload.roomId) {
      await toWsError(() => this.matches.leaveMatch(user.id));
      await client.leave(`room:${payload.roomId}`);
      return;
    }
    await toWsError(() => this.rooms.leaveRoom(user.id, payload.roomId));
    await client.leave(`room:${payload.roomId}`);
  }

  /** Set readiness (FR-46); the service broadcasts `room:updated`. */
  @SubscribeMessage(SOCKET_CLIENT_EVENTS.roomReady)
  async handleRoomReady(
    @ConnectedSocket() client: GameSocket,
    @MessageBody() payload: RoomReadyDto,
  ): Promise<void> {
    const user = client.data.user!;
    await toWsError(() =>
      this.rooms.setReady(user.id, payload.roomId, payload.ready),
    );
  }

  /**
   * Start the match (FR-47, host only). The service creates the
   * match + seats + `match_started` event in one transaction and
   * broadcasts `match:started` + `room:updated` to the room.
   */
  @SubscribeMessage(SOCKET_CLIENT_EVENTS.matchStart)
  async handleMatchStart(
    @ConnectedSocket() client: GameSocket,
    @MessageBody() payload: MatchStartDto,
  ): Promise<void> {
    const user = client.data.user!;
    await toWsError(() => this.rooms.startMatch(user.id, payload.roomId));
  }

  // -- Gameplay (Stage 5, SDD §12.6) --------------------------------------
  //
  // Every handler runs through runGameIntent: a GameRejectedError
  // (not a member, not your turn, illegal move, match finished,
  // stale state) becomes `action:rejected` to the requester only,
  // with the state unchanged; any other HTTP error keeps the
  // shared `exception` mapping. Fresh transitions are broadcast by
  // MatchService to the match's room; a duplicate's original result
  // is re-emitted to the requester only, and a snapshot likewise.

  /**
   * Join the socket to the match's room for game broadcasts, after
   * a membership check. Members who joined via `room:join` are
   * already there; members who arrived via matchmaking join here on
   * their first game intent. The service re-checks membership on
   * every intent — the join is delivery, never authorisation.
   */
  private async ensureInMatchRoom(
    client: GameSocket,
    matchId: string,
    userId: string,
  ): Promise<void> {
    const { roomId } = await this.matches.getMatchRoom(matchId, userId);
    await client.join(`room:${roomId}`);
  }

  /**
   * Run one game intent: rejections become `action:rejected` (with
   * the code + account logged, no tokens — SDD §13.5); anything
   * else keeps the shared `exception` mapping.
   */
  private async runGameIntent<T>(
    client: GameSocket,
    matchId: string,
    requestId: string | undefined,
    fn: () => Promise<T>,
  ): Promise<T | undefined> {
    try {
      return await fn();
    } catch (err) {
      if (err instanceof GameRejectedError) {
        this.logger.warn(
          `action:rejected code=${err.code} match=${matchId} ` +
            `user=${client.data.user?.id ?? 'unknown'} ` +
            `requestId=${requestId ?? 'none'}`,
        );
        client.emit(SOCKET_SERVER_EVENTS.actionRejected, {
          matchId,
          ...(requestId ? { requestId } : {}),
          code: err.code,
          message: err.message,
        });
        return undefined;
      }
      throw mapHttpToWs(err);
    }
  }

  /** Roll the dice (FR-49): intent only — the server rolls. */
  @SubscribeMessage(SOCKET_CLIENT_EVENTS.diceRoll)
  async handleDiceRoll(
    @ConnectedSocket() client: GameSocket,
    @MessageBody() payload: DiceRollDto,
  ): Promise<void> {
    const user = client.data.user!;
    await this.runGameIntent(
      client,
      payload.matchId,
      payload.requestId,
      async () => {
        await this.ensureInMatchRoom(client, payload.matchId, user.id);
        const result = await this.matches.rollDice(
          payload.matchId,
          user.id,
          payload.requestId,
          payload.value,
        );
        for (const event of result.events) {
          client.emit(event.event, event.payload);
        }
      },
    );
  }

  /** Move one token (FR-50): legality is decided by the engine. */
  @SubscribeMessage(SOCKET_CLIENT_EVENTS.tokenMove)
  async handleTokenMove(
    @ConnectedSocket() client: GameSocket,
    @MessageBody() payload: TokenMoveDto,
  ): Promise<void> {
    const user = client.data.user!;
    await this.runGameIntent(
      client,
      payload.matchId,
      payload.requestId,
      async () => {
        await this.ensureInMatchRoom(client, payload.matchId, user.id);
        const result = await this.matches.moveToken(
          payload.matchId,
          user.id,
          payload.tokenId,
          payload.requestId,
        );
        for (const event of result.events) {
          client.emit(event.event, event.payload);
        }
      },
    );
  }

  /** Request a full snapshot (FR-57): e.g. on a seq gap. */
  @SubscribeMessage(SOCKET_CLIENT_EVENTS.stateRequest)
  async handleStateRequest(
    @ConnectedSocket() client: GameSocket,
    @MessageBody() payload: StateRequestDto,
  ): Promise<void> {
    const user = client.data.user!;
    await this.runGameIntent(client, payload.matchId, undefined, async () => {
      await this.ensureInMatchRoom(client, payload.matchId, user.id);
      const state = await this.matches.requestState(
        payload.matchId,
        user.id,
        payload.lastSeq,
      );
      client.emit(SOCKET_SERVER_EVENTS.matchState, state);
    });
  }
}

/**
 * Map a service HttpException (carrying the §6.3 `code` in its
 * response body) to a WsException with the same envelope, so a
 * socket client receives `exception` with the same code REST would
 * return (ROOM_NOT_FOUND, NOT_ROOM_HOST, …) instead of Nest's
 * generic "Internal server error" for non-WsExceptions. WsExceptions
 * (validation / rate limit / auth) pass through untouched.
 */
function mapHttpToWs(err: unknown): unknown {
  if (err instanceof HttpException) {
    const body = err.getResponse();
    if (typeof body === 'object' && body !== null) {
      const b = body as { code?: unknown; message?: unknown };
      if (typeof b.code === 'string') {
        return socketWsException(
          b.code as ErrorCode,
          typeof b.message === 'string' ? b.message : err.message,
        );
      }
    }
    return socketWsException(ErrorCode.InternalError, err.message);
  }
  return err;
}

async function toWsError<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (err) {
    throw mapHttpToWs(err);
  }
}
