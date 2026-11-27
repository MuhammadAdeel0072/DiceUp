import { INestApplication } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import type { Server, ServerOptions, Socket } from 'socket.io';
import { ErrorCode } from '../common/errors/error-codes';
import { SOCKET_NAMESPACE, type SocketClientData } from './socket.constants';
import { SocketAuthError } from './socket-error';
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
      const user = await this.guard.authenticate(socket.handshake.auth);
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
  );
}
