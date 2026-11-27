/**
 * Socket.IO constants (plan §9.2/§9.3). Values the SDD prescribes are
 * marked; values the SDD leaves silent are flagged [P4 choice] and are
 * one-line changes.
 */
import type { RequestUser } from '../common/guards/request-user';

/** The one Socket.IO namespace (SDD §12.6 [Proposed]). */
export const SOCKET_NAMESPACE = '/game';

/** Client → server events that exist in Phase 4 (foundation only). */
export const SOCKET_CLIENT_EVENTS = {
  /** Connectivity/validation probe — NOT a game event (see below). */
  ping: 'ping',
} as const;

/**
 * Server → client events that exist in Phase 4.
 * `connected` is a connection-lifecycle event (plan §9.1 explicitly
 * allows server broadcasts for the connection lifecycle itself);
 * `pong` answers `ping`; `exception` is Nest's standard error channel
 * (WsException payloads are emitted on it by WsExceptionsHandler).
 * No game broadcasts exist yet (room/match/dice/token events are
 * Phase 5, plan §9.3).
 */
export const SOCKET_SERVER_EVENTS = {
  connected: 'connected',
  pong: 'pong',
  exception: 'exception',
} as const;

/**
 * Per-connection event rate limit, 20 events/s (NFR-20, SDD §12.6).
 * Enforced by WsRateLimitGuard on every message handler.
 */
export const SOCKET_EVENTS_PER_SECOND = 20;
export const SOCKET_EVENT_WINDOW_SECONDS = 1;

/**
 * Sustained-abuse disconnect threshold [P4 choice]: after this many
 * rate-limit violations on one connection, the socket is disconnected
 * (SDD §12.6 "sustained abuse disconnects the socket" — the count is
 * the SDD's silence, so a small conventional value is picked).
 */
export const SOCKET_RATE_LIMIT_MAX_VIOLATIONS = 5;

/**
 * Maximum socket event payload, 10 KB (SDD §13.4 [Proposed]).
 * Enforced on the raw payload by WsValidationPipe (before the
 * whitelist strips unknown fields — a check after stripping could
 * never trigger). `maxHttpBufferSize` (set on the server in the
 * adapter) only bounds HTTP (polling handshake) traffic, not
 * WebSocket frames, so the pipe check is the real enforcement point
 * for WS traffic.
 */
export const SOCKET_MAX_EVENT_BYTES = 10 * 1024;

/**
 * Per-connection state carried on `socket.data`. Set by the handshake
 * middleware in the adapter (user + token + app version) and refreshed
 * by WsJwtGuard on every message (fresh `sid` check — see the guard).
 * Never logged (the token is a secret; the user id is the only
 * identifier that may appear in logs).
 */
export interface SocketClientData {
  /** Authenticated principal (set at handshake, refreshed per event). */
  user?: RequestUser;
  /** Raw access token, for the per-message re-validation in the guard. */
  authToken?: string;
  /** Client app version from the handshake (logged, not enforced — plan §9.2). */
  appVersion?: string;
  /** Rate-limit violations on this connection (abuse disconnect). */
  rateLimitViolations?: number;
}
