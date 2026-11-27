import { Logger, UseGuards, UsePipes } from '@nestjs/common';
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
import {
  SOCKET_CLIENT_EVENTS,
  SOCKET_NAMESPACE,
  SOCKET_SERVER_EVENTS,
} from './socket.constants';
import { WsRateLimitGuard } from './ws-rate-limit.guard';
import { WsValidationPipe } from './ws-validation.pipe';
import { WsJwtGuard, type GameSocket } from './ws-jwt.guard';
import {
  type ConnectedPayload,
  PingDto,
  type PongPayload,
} from './dto/ping.dto';

/**
 * GameGateway (plan §9.1/§9.2) — FOUNDATION ONLY.
 *
 * What exists: namespace `/game`, authenticated connections (handshake
 * middleware in the adapter + WsJwtGuard on every message), the
 * connect/disconnect lifecycle with logging, the `ping`/`pong`
 * connectivity probe with validation + rate limiting, and the Redis
 * adapter wiring that lets later phases broadcast across nodes.
 *
 * What deliberately does NOT exist: rooms, matchmaking, gameplay,
 * presence, invitations, or any server broadcast beyond the
 * connection lifecycle (`connected`) and the `pong` reply. There is
 * no `room:join` / `room:leave` / `room:ready` / `match:start` /
 * `dice:roll` / `token:move` / `state:request` handler and no
 * `room:updated` / `match:started` / `dice:rolled` / `token:moved` /
 * `turn:changed` / `player:*` / `match:state` / `match:ended` /
 * `action:rejected` emission — those are Phase 5 (plan §9.3 names
 * them so Phase 5 does not re-decide the conventions).
 *
 * Room-based communication hook point (for Phase 5): authorization
 * for joining a room will be a guard on the `room:join` handler that
 * loads the room from PostgreSQL, checks membership/host, and only
 * then calls `client.join('room:{roomId}')`. The per-message
 * WsJwtGuard already attached here is the pattern it follows — the
 * room guard will read `client.data.user` (set at handshake) and
 * must never trust a room id the client claims to own.
 */
@WebSocketGateway({ namespace: SOCKET_NAMESPACE })
@UseGuards(WsJwtGuard, WsRateLimitGuard)
@UsePipes(new WsValidationPipe())
export class GameGateway
  implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect
{
  private readonly logger = new Logger(GameGateway.name);

  /**
   * The `/game` Namespace object (Nest assigns the namespace, not the
   * root Server, to @WebSocketServer() on a namespaced gateway).
   * Emitting on it broadcasts to this namespace on this node and, via
   * the Redis adapter, to the same namespace on every other node.
   */
  @WebSocketServer()
  server!: Namespace;

  afterInit(): void {
    this.logger.log(
      `Socket.IO gateway initialised on namespace ${SOCKET_NAMESPACE} (Redis adapter)`,
    );
  }

  handleConnection(client: GameSocket): void {
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

  handleDisconnect(client: GameSocket): void {
    // No room membership exists yet, so there is nothing to release —
    // the log line is the whole disconnect handling (NFR-37).
    // Phase 5 adds: leave rooms, start the grace timer, broadcast
    // `player:disconnected` to the match.
    this.logger.log(
      `Socket disconnected: user=${client.data.user?.id ?? 'unknown'} socket=${client.id}`,
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
  }
}
