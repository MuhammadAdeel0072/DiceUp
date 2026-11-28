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
  /** Join an open room by code (FR-44). */
  roomJoin: 'room:join',
  /** Leave a room (FR-59). */
  roomLeave: 'room:leave',
  /** Set readiness in a room (FR-46). */
  roomReady: 'room:ready',
  /** Start the match (FR-47, host only). */
  matchStart: 'match:start',
  /** Roll the dice (FR-49): intent only, no value supplied. */
  diceRoll: 'dice:roll',
  /** Move one token (FR-50): the token id, never a position. */
  tokenMove: 'token:move',
  /** Request a full snapshot (FR-57): e.g. on a seq gap. */
  stateRequest: 'state:request',
} as const;

/**
 * Server → client events that exist in Phase 4.
 * `connected` is a connection-lifecycle event (plan §9.1 explicitly
 * allows server broadcasts for the connection lifecycle itself);
 * `pong` answers `ping`; `exception` is Nest's standard error channel
 * (WsException payloads are emitted on it by WsExceptionsHandler).
 * Phase 5, Stage 3 adds `room:updated`, `match:started` and
 * `matchmaking:matched` (SDD §12.6). Stage 5 adds the gameplay
 * events (`dice:rolled`, `token:moved`, `turn:changed`,
 * `match:state`, `match:ended`, `action:rejected`): every one
 * carries an increasing `seq` (FR-51) except `action:rejected`,
 * which reports a rejected intent (state unchanged) and echoes the
 * intent's `requestId` when one was supplied.
 */
export const SOCKET_SERVER_EVENTS = {
  connected: 'connected',
  pong: 'pong',
  exception: 'exception',
  roomUpdated: 'room:updated',
  matchStarted: 'match:started',
  matchmakingMatched: 'matchmaking:matched',
  diceRolled: 'dice:rolled',
  tokenMoved: 'token:moved',
  turnChanged: 'turn:changed',
  matchState: 'match:state',
  matchEnded: 'match:ended',
  actionRejected: 'action:rejected',
  /** A player disconnected; grace is running (Stage 6, FR-54). */
  playerDisconnected: 'player:disconnected',
  /** A player reconnected inside their grace (Stage 6, FR-55). */
  playerReconnected: 'player:reconnected',
  /** A player forfeited per BR-15 (Stage 6, FR-56). */
  playerForfeited: 'player:forfeited',
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
 * Socket CONNECTION rate limits (Stage 5, L-02). A handshake costs
 * an RS256 verify + DB lookups, and reconnecting resets the
 * per-socket event budget — so connections themselves are bounded,
 * per IP (before auth) and per user (after auth), at generous
 * values a legitimate client never approaches (a client connects
 * once per session and reconnects occasionally). Enforced in the
 * adapter handshake middleware, with an in-process fallback when
 * Redis is down (see SocketConnectionRateLimitService).
 */
export const SOCKET_CONNECTIONS_PER_MINUTE_PER_IP = 120;
export const SOCKET_CONNECTIONS_PER_MINUTE_PER_USER = 20;
export const SOCKET_CONNECTION_WINDOW_SECONDS = 60;

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
