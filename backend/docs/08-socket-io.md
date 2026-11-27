# Socket.IO architecture

Namespace `/game` (SDD §12.6 `[Proposed]`), served by the same HTTP
server as REST — no separate port, no plain-WebSocket listener.
Gateway: `src/socket/game.gateway.ts`; module: `src/socket/socket.module.ts`.

## Transport and scaling

- `socket.io` **4.8.3** (exact — pinned to match
  `@nestjs/platform-socket.io` 11.2.12's dependency, so npm dedupes
  to a single socket.io + socket.io-adapter copy) with the
  **Redis adapter** (`@socket.io/redis-adapter` **8.2.1**, exact).
  The adapter lets multiple backend instances share broadcasts
  (verified by a two-node e2e test: a server-side emit on node A is
  received by a client connected to node B).
- The adapter runs on dedicated ioredis pub/sub clients
  (`SocketRedisClients`: one publisher, one subscriber via
  `pub.duplicate()`), separate from the `RedisService` client.
- **Shutdown ordering (load-bearing):** Nest calls
  `onModuleDestroy` *before* `dispose()` closes the Socket.IO
  server. Disconnecting pub/sub in `onModuleDestroy` killed the
  subscriber while the Redis adapter's `close()` was still issuing
  its `unsubscribe` commands — all four rejected with
  "Connection is closed" as unhandled rejections and failed every
  e2e suite. The fix: disconnect in `onApplicationShutdown` (runs
  after `dispose()`), which first awaits an explicit
  `sub.unsubscribe()` on the same connection (its ack proves the
  adapter's earlier unsubscribes completed), then `pub.quit()`
  (drains pending publishes), then `sub.disconnect()`.

## Dependencies and the CJS question

`@nestjs/websockets` + `@nestjs/platform-socket.io` are pinned to
the **11.2.12** line matching installed `@nestjs/common`/`core`
11.2.12 (v12 is ESM-only — the same trap as Stage 2b's
`@nestjs/jwt` 11.0.2 / `@nestjs/passport` 11.0.5 /
`@nestjs/schedule` 6.1.3 pins). `@socket.io/redis-adapter`
**8.2.1** was chosen over 8.3.0: both are CJS (verified from the
published tarballs — no `"type": "module"`,
`main: ./dist/index.js`), but 8.3.0 peers on `socket.io-adapter
^2.5.4` while socket.io 4.8.x bundles `~2.5.2`; 8.2.1 peers on
`^2.4.0`, satisfied by the bundled 2.5.9. All four packages were
verified to load under plain CJS `require()` before proceeding.
Re-check before any upgrade to v12 (needs an ESM migration of the
backend).

## Authentication — the same auth path as REST

Authenticated connections **only**. The handshake carries the access
token in `auth: { token }` (and optionally `appVersion`, which is
logged, not enforced).

- **Handshake auth runs in adapter middleware, not in a guard.**
  Verified in the Nest 11 source: guards do **not** run on
  `handleConnection` (`WebSocketsController.subscribeConnectionEvent`
  subscribes the lifecycle hook directly), so connection auth must be
  enforced in middleware. `createRedisSocketAdapter(app)` registers
  the middleware on both the root server and `server.of('/game')`
  (verified in the socket.io 4.8.3 source: `server.use()` registers
  middleware on the main namespace only).
- The middleware calls `WsJwtGuard.authenticate()`, which reuses the
  **one** auth path: `TokenService.verifyAccessToken` +
  `JwtStrategy.validate` (including the load-bearing `sid`
  revocation check), then the same account-status /
  deletion-request / email-verified rules with the same codes and
  messages as REST. A logged-out/revoked session fails socket auth
  immediately, same as REST.
- **Per-message re-validation:** `WsJwtGuard.canActivate()` runs on
  every message handler and re-validates the stored handshake token
  (fresh `sid` check), so a session revoked mid-connection fails the
  next event with `UNAUTHORIZED`.
- **Handshake failure shape:** the middleware error becomes a
  `connect_error`. socket.io 4.8.3 (protocol 4) sends the
  CONNECT_ERROR packet as `{ message: err.message, data: err.data }`,
  and the client builds `new Error(packet.data.message)` with
  `err.data = packet.data.data`. `SocketAuthError.toHandshakeError()`
  therefore puts the §6.3 envelope itself on `error.data`, so the
  client receives `err.message` (human-readable) and `err.data`
  (the full envelope, with the machine-readable `code`). E.g.
  no token → `err.message === 'Authentication token is required.'`,
  `err.data.error.code === 'UNAUTHORIZED'`.

## Events

### Client → server

| Event | Payload | Notes |
|---|---|---|
| `ping` | `{ requestId: string }` (UUID) | **Foundation-only connectivity/validation probe — NOT a game event.** Exists so event validation, rate limiting, and the reply path are testable before Phase 5 adds real events. |

### Server → client

| Event | Payload | Notes |
|---|---|---|
| `connected` | `{ userId, socketId, connectedAt }` | Emitted from `handleConnection` immediately after accepting the socket. Clients must register the listener **before** connecting — it can otherwise be missed (a real race the e2e tests hit). |
| `pong` | `{ requestId, serverTime }` | Answers `ping`; `requestId` echoes the client's value. |
| `exception` | §6.3 envelope `{ success: false, error: { code, message, details? } }` | Nest's standard error channel: a `WsException` payload is emitted verbatim. |

Event naming: lowercase, single-word where possible
(`SOCKET_CLIENT_EVENTS` / `SOCKET_SERVER_EVENTS` in
`src/socket/socket.constants.ts`). Payloads are JSON objects;
unknown fields are stripped by the whitelist (same rule as REST).

## Validation, rate limiting, errors

- **Event validation:** `WsValidationPipe` (the ValidationPipe
  equivalent for socket payloads) is applied at the gateway class
  level: whitelist strip, transform to the DTO, malformed payload →
  `VALIDATION_FAILED` `exception` with per-field `details`. The
  gateway never crashes on a malformed payload; the connection
  survives a validation failure.
- **Payload size:** 10 KB per event (SDD §13.4 `[Proposed]`),
  enforced by the pipe **on the raw payload, before the whitelist
  strips unknown fields** — a check after stripping could never
  trigger. Oversized → `PAYLOAD_TOO_LARGE`. `maxHttpBufferSize` is
  deliberately **not** overridden: engine.io applies it as the
  WebSocket `maxPayload`, so a 10 KB value would kill oversized
  frames at the transport with no standardised error; the default
  1 MB transport cap remains as a backstop.
- **Pipe scope fix (found by the e2e ping test):** the pipe runs for
  *every* handler parameter, including `@ConnectedSocket()`.
  `JSON.stringify` on the server-side `Socket` throws (circular
  references), which used to surface as a spurious
  `VALIDATION_FAILED` on every valid event. The size check now runs
  for body parameters only; a value that cannot be stringified is
  left for `super.transform` to skip. Locked in by a unit test.
- **Rate limit:** 20 events/s per socket (NFR-20), enforced by
  `WsRateLimitGuard` on every message handler via
  `RedisService.incrWithExpiry` on
  `ratelimit:socket:{socketId}:1s`. Over the limit → the event is
  dropped with a `RATE_LIMITED` `exception`. **5 violations**
  (`[P4 choice]` — the plan is silent on the count) → the socket
  is disconnected (SDD §12.6 "sustained abuse disconnects the
  socket"). Redis down → the guard fails closed
  (`SERVICE_UNAVAILABLE`).
- **Error format:** socket errors mirror the REST envelope exactly,
  so clients switch on `code` on both transports. Handler errors
  are emitted on `exception`; they never crash the gateway.

## Connection lifecycle

- `handleConnection`: defensive — if no principal is present (which
  the middleware should have prevented), the socket is disconnected
  immediately. Otherwise it logs `userId` + `socketId` + `appVersion`
  (no tokens, no secrets) and emits `connected`.
- `handleDisconnect`: log only. No presence update exists yet.
- **Safe disconnection:** the adapter's close sequence and the
  Redis clients' shutdown are ordered as described above; the e2e
  suite asserts a clean disconnect + reconnect with no unhandled
  rejections.

## What is foundation-only (Phase 5 owns the rest)

No rooms, no matchmaking, no gameplay, no presence tracking, no
match state, no game broadcasts. The hook point for future
room-based communication is documented in the gateway comment:
`handleConnection` is where a room-authorization check will run
once rooms exist, and `client.data.user` is the principal it will
check. The two-node e2e test uses a test-only event name
(`adapter:probe`) to prove adapter broadcast; no production event
was added for it.
