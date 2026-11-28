import { INestApplication } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import type { Server, ServerOptions, Socket } from 'socket.io';
import type { AppConfig } from '../config/configuration';
import { ErrorCode } from '../common/errors/error-codes';
import { SOCKET_NAMESPACE, type SocketClientData } from './socket.constants';
import { SocketAuthError } from './socket-error';
import { SocketConnectionRateLimitService } from './socket-connection-rate-limit.service';
import { SocketRedisClients } from './socket-redis-clients.service';
import {
  extractHandshakeAppVersion,
  extractHandshakeToken,
  WsJwtGuard,
} from './ws-jwt.guard';

/**
 * RedisSocketIoAdapter (plan §9.2/§9.4, NFR-24) — the Socket.IO server
 * adapter for the whole app. Two jobs:
 *
 * 1. Redis adapter: `server.adapter(createAdapter(pub, sub))` wires
 *    the @socket.io/redis-adapter (8.2.1, CJS — see the Stage 2c deps
 *    commit) so broadcasts fan out through Redis pub/sub. A single
 *    node works without it; with it, two gateway instances share a
 *    broadcast (proven by the two-node e2e test), which is the
 *    foundation horizontal scaling needs. No game traffic exists yet
 *    to broadcast — the wiring is the deliverable.
 * 2. Handshake auth: namespace middleware runs WsJwtGuard.authenticate()
 *    on every `/game` handshake BEFORE the connection is accepted.
 *    This is the enforcement point for connection auth, because Nest
 *    guards do not run on `handleConnection` (the WebSocketsController
 *    subscribes the lifecycle hook directly). A failure calls
 *    `next(err)` and the client receives `connect_error` with the
 *    §6.3 envelope in `err.data` (see SocketAuthError).
 *
 * `maxHttpBufferSize` is deliberately NOT overridden here (see
 * createIOServer): engine.io applies it as the WebSocket
 * `maxPayload`, so a 10 KB value would kill oversized frames at the
 * transport instead of letting WsValidationPipe reject them with the
 * standardized PAYLOAD_TOO_LARGE error.
 */
export class RedisSocketIoAdapter extends IoAdapter {
  constructor(
    app: INestApplication,
    private readonly guard: WsJwtGuard,
    private readonly clients: SocketRedisClients,
    private readonly connLimiter: SocketConnectionRateLimitService,
    /**
     * The validated `trust proxy` setting: only when it is on may
     * the first `X-Forwarded-For` entry be trusted as the client IP
     * for the connection limit (otherwise an attacker could spoof
     * the header to dodge the per-IP budget).
     */
    private readonly trustProxy: boolean | number | string,
  ) {
    super(app);
  }

  createIOServer(port: number, options?: ServerOptions): Server {
    // No `maxHttpBufferSize` override here on purpose: engine.io
    // applies it as the WebSocket `maxPayload`, so a 10 KB value
    // would kill oversized frames at the transport — the client
    // would never receive the standardized PAYLOAD_TOO_LARGE error
    // (and the connection could die with the frame). The 10 KB
    // per-event limit is enforced by WsValidationPipe instead, which
    // rejects the event with the §6.3 envelope and keeps the
    // connection alive. The default 1 MB transport cap remains as a
    // backstop against absurd frames.
    const server = super.createIOServer(port, options);
    server.adapter(createAdapter(this.clients.pub, this.clients.sub));
    // NOTE: `server.use()` registers middleware on the MAIN namespace
    // only (`this.sockets.use(fn)` — socket.io keeps one middleware
    // chain per namespace). A gateway on `/game` would never see it,
    // so the handshake middleware is registered on the `/game`
    // namespace explicitly (and on the root namespace too, so a
    // client connecting to `/` is authenticated the same way even
    // though no gateway listens there).
    const handshake = (socket: Socket, next: (err?: Error) => void) => {
      void this.authenticateHandshake(socket, next);
    };
    server.use(handshake);
    server.of(SOCKET_NAMESPACE).use(handshake);
    return server;
  }

  private async authenticateHandshake(
    socket: Socket,
    next: (err?: Error) => void,
  ): Promise<void> {
    try {
      // L-02: bound handshake floods BEFORE the RS256 verify + DB
      // lookups. The per-IP check runs first (unauthenticated), the
      // per-user check after auth (one account, bounded connections).
      // A limit hit refuses the handshake with RATE_LIMITED; the
      // limiter never throws (Redis-down falls back in-process).
      const ip = extractHandshakeIp(socket, this.trustProxy);
      const ipCheck = await this.connLimiter.checkIp(ip);
      if (!ipCheck.allowed) {
        next(
          new SocketAuthError(
            ErrorCode.RateLimited,
            'Too many connections from this address. Slow down.',
          ).toHandshakeError(),
        );
        return;
      }
      const user = await this.guard.authenticate(socket.handshake.auth);
      const userCheck = await this.connLimiter.checkUser(user.id);
      if (!userCheck.allowed) {
        next(
          new SocketAuthError(
            ErrorCode.RateLimited,
            'Too many connections for this account. Slow down.',
          ).toHandshakeError(),
        );
        return;
      }
      const data = socket.data as SocketClientData;
      data.user = user;
      data.authToken = extractHandshakeToken(socket.handshake.auth);
      data.appVersion = extractHandshakeAppVersion(socket.handshake.auth);
      next();
    } catch (err) {
      if (err instanceof SocketAuthError) {
        next(err.toHandshakeError());
        return;
      }
      // Unexpected failure (e.g. the database is unreachable for the
      // `sid` lookup): refuse the handshake, but do not misreport it
      // as bad credentials.
      next(
        new SocketAuthError(
          ErrorCode.ServiceUnavailable,
          'Authentication is temporarily unavailable.',
        ).toHandshakeError(),
      );
    }
  }
}

/**
 * Build the adapter for an application (main.ts and the e2e
 * test-app factory both use this — the two must stay in sync).
 * WsJwtGuard and SocketRedisClients come from SocketModule, so this
 * must be called after the application context exists.
 */
export function createRedisSocketAdapter(
  app: INestApplication,
): RedisSocketIoAdapter {
  return new RedisSocketIoAdapter(
    app,
    app.get(WsJwtGuard),
    app.get(SocketRedisClients),
    app.get(SocketConnectionRateLimitService),
    app.get(ConfigService).getOrThrow<AppConfig>('app').trustProxy,
  );
}

/**
 * Client IP for the connection limit (L-02): the first
 * `X-Forwarded-For` entry only when the trust-proxy setting is on,
 * otherwise the socket's remote address. Never trusts the header
 * blindly — with trust proxy off, a spoofed header must not buy a
 * fresh per-IP budget.
 */
export function extractHandshakeIp(
  socket: Socket,
  trustProxy: boolean | number | string,
): string {
  if (trustProxy) {
    const forwarded = socket.handshake.headers['x-forwarded-for'];
    const first =
      typeof forwarded === 'string'
        ? forwarded.split(',')[0]?.trim()
        : undefined;
    if (first) return first;
  }
  return socket.handshake.address || 'unknown';
}
