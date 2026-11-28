# Phase 5 — Online API & Socket Supplement

**Phase:** 5 — Online Multiplayer Gameplay (Stage 9)
**Branch:** `feature/online-phase-5-gameplay`, HEAD `5d47cf7` (Stage 8)
**Supplements:** `06-rest-api.md` and `08-socket-io.md` — those two docs
describe the Phase 4 foundation unchanged; this doc adds only what Phase 5
built. The full requirement-by-requirement trace is in
`docs/PHASE-5-TRACEABILITY.md`.

Conventions (unchanged from Phase 4): base `/v1`; envelope
`{ success: true, data }` / `{ success: false, error: { code, message,
details?, correlationId } }`; `X-Request-Id` on every response; JSON bodies
≤ 100 KB, unknown fields stripped, malformed JSON → 400 `VALIDATION_FAILED`.
Switch on `error.code`, never on message text. All Phase 5 routes require an
authenticated, email-verified player (global `JwtAuthGuard` +
`AccountStatusGuard` + controller `EmailVerifiedGuard` +
`@Roles('player')`); all authenticated REST is additionally rate-limited at
100/min per user.

## 1. Rooms — REST (`/v1/rooms`)

Source: `backend/src/rooms/rooms.controller.ts`, `rooms.service.ts`,
`dto/rooms.dto.ts`, `room-code.ts`. Table `rooms` (migration 0003).

| Method + endpoint | Request | Response / errors |
|---|---|---|
| `POST /v1/rooms` | `{ maxPlayers: 2–4 }` — the **only** host choice (OD-11: frozen ruleset `RULESET_VERSION=1.0.0`, stored per room) | 201 + room `{ id, code, hostId, maxPlayers, status: 'open', rulesetVersion, members[] }`. `code` is a 6-char uppercase alphanumeric string, confusables excluded, unique among open rooms (partial unique index) |
| `POST /v1/rooms/join` | `{ code }` — 6 chars, case-insensitive | 200 + room. Errors: `ROOM_NOT_FOUND` (404), `ROOM_FULL` (409), `ROOM_STARTED` (409), `ALREADY_IN_ROOM` (409) |
| `GET /v1/rooms/:id` | — | 200 + room with `members[]` and per-member `ready`. `NOT_FOUND` for unknown id; `NOT_ROOM_MEMBER` for a non-member |
| `POST /v1/rooms/:id/leave` | — | 200. Leave before start (FR-59): host transfers to the longest-present member; the room closes when empty. Leaving a room whose match is in progress is a voluntary mid-match leave — a forfeit (FR-56, BR-15), not a room leave |

Room lifecycle: `open` → `playing` (on `match:start`) → `closed` (empty, or
match ended). Empty open rooms are swept after 10 minutes
(`rooms-cleanup.service.ts`).

## 2. Matchmaking — REST (`/v1/matchmaking`)

Source: `backend/src/matchmaking/matchmaking.controller.ts`,
`matchmaking.service.ts`. Queue: Redis sorted set `matchmaking:queue`,
score = enqueue time; one entry per player; group size **4**
(`MATCHMAKING_GROUP_SIZE = 4`, SDD default). Grouping is arrival order
only — no skill/rank/region criteria, no maximum wait, no partial-group
start (assessment G-2/G-6).

| Method + endpoint | Request | Response / errors |
|---|---|---|
| `POST /v1/matchmaking/join` | — | 200 `{ status: 'queued', queueSize, groupSize: 4 }`. Errors: `ALREADY_IN_MATCHMAKING` (409), `ALREADY_IN_ROOM` (409), `ALREADY_IN_MATCH` (409), `MATCHMAKING_UNAVAILABLE` (503, Redis down) |
| `POST /v1/matchmaking/leave` | — | 200 `{ status: 'idle', queueSize, groupSize: 4 }`. Error: `NOT_IN_MATCHMAKING` (409) |
| `GET /v1/matchmaking/status` | — | 200 `{ status: 'queued' \| 'idle', queueSize, groupSize: 4 }` |

When a group of 4 is present the service atomically pops them, creates a
room (`source: 'matchmaking'`), and notifies each player with
`matchmaking:matched { roomId, roomCode }` on their socket (or they learn
it from `GET /status`). Never groups a suspended player or a player
already in a room. Disconnect removes the queue entry.

## 3. Matches — REST (`/v1/matches`)

Source: `backend/src/match/matches.controller.ts`, `match.service.ts`.
Tables `matches`, `match_players`, `move_events` (migration 0003).

| Method + endpoint | Response |
|---|---|
| `GET /v1/matches/active` | The caller's in-progress match, if any (`{ match }` or empty) — the "return to active match" read path (UC-07 E2) |
| `GET /v1/matches/:id` | Match detail `{ id, roomId, status, rulesetVersion, winnerId, startedAt, endedAt, players[] }`. `MATCH_NOT_FOUND` (404) / `NOT_MATCH_PLAYER` (403) for non-players |
| `GET /v1/matches/:id/state` | Current authoritative snapshot — the REST form of `match:state` (see §5) |
| `GET /v1/matches/:id/events` | Ordered move log (`move_events` by `seq_no`): `{ events: [{ seqNo, type, actorId, payload, requestId }] }` |

`matches.status` is only `in_progress` / `completed` / `cancelled` — there
is no flagged/error state (C-12, recorded as unimplementable as written).

## 4. Socket.IO — namespace `/game`

Source: `backend/src/socket/game.gateway.ts`, `socket.constants.ts`,
`dto/game.dto.ts`, `dto/room.dto.ts`. Transport, auth, validation, and rate
limiting are as in `08-socket-io.md` (handshake JWT in `auth: { token }`,
per-message re-validation, 20 events/s per socket with disconnect after 5
violations, 10 KB payload cap, L-02 connection limits 120/min/IP and
20/min/user). Socket rooms inside `/game` are named `room:{roomId}`;
joining one is delivery only — membership is re-checked by the service on
every intent, never trusted from the client.

### 4.1 Client → server

| Event | Payload | Rules |
|---|---|---|
| `ping` | `{ requestId }` (UUID) | Foundation connectivity probe — not a game event. Answers `pong { requestId, serverTime }` |
| `room:join` | `{ roomCode }` | Join an open room by code (FR-44). Caller joins socket room `room:{roomId}` and receives `room:updated` directly |
| `room:leave` | `{ roomId }` | Leave before start (FR-59). If the room's match is in progress, this is a voluntary mid-match leave → forfeit (FR-56) |
| `room:ready` | `{ roomId, ready: boolean }` | Set readiness (FR-46); all members get `room:updated` |
| `match:start` | `{ roomId }` | Host only (FR-47: host + ≥ 2 present + all ready). Creates the match + seats + `match_started` event in one transaction |
| `dice:roll` | `{ matchId, requestId }` (+ optional `value`, see below) | Intent only — the server rolls (FR-49). `requestId` is a client-generated UUID (FR-53) |
| `token:move` | `{ matchId, tokenId, requestId }` | `tokenId` is `"{seat}:{tokenIndex}"` (e.g. `"0:2"`); never a position. Legality decided by the engine (FR-50) |
| `state:request` | `{ matchId, lastSeq }` | Request a full snapshot (FR-57), e.g. on a `seq` gap |

**Client-supplied dice value:** `dice:roll` may carry a `value` field, but
it is **ignored and logged** (SDD §8.8 anti-cheat). The field exists on the
DTO only so the value can be observed — the whitelist would otherwise strip
it silently. The roll always comes from the server's `CryptoDiceRoller`.

### 4.2 Server → client

Every server game event carries an increasing `seq` (FR-51), **except**
`action:rejected`, which echoes the intent's `requestId` instead. `seq`
is per match, starting at the `match_started` event.

| Event | Payload | Notes |
|---|---|---|
| `connected` | `{ userId, socketId, connectedAt }` | Emitted on connect; register the listener **before** connecting |
| `pong` | `{ requestId, serverTime }` | Answers `ping` |
| `exception` | §6.3 envelope | Nest's standard error channel (validation, rate-limit, non-game errors) |
| `room:updated` | `{ room, members[], ready{} }` | Room + membership + readiness after any room change. `room` carries `id, code, hostId, maxPlayers, status, rulesetVersion` |
| `match:started` | `{ matchId, seats[], rulesetVersion }` | `seats[]` is `{ userId, seat, colour }` in join order (seat = join order, SDD DA-03) |
| `matchmaking:matched` | `{ roomId, roomCode }` | Sent to each grouped player individually |
| `dice:rolled` | `{ matchId, playerId, value, seq }` | `value` is the server roll (1–6) |
| `token:moved` | `{ matchId, tokenId, landing, captured[], extraTurn, winner, seq, turn: { playerId, turnEndsAt } }` | `landing` is `{ kind, index }`; `captured[]` is token ids; `turn.turnEndsAt` is the deadline (ISO) of the turn current **after** this move, null only when the match ended with the move |
| `turn:changed` | `{ matchId, playerId, turnEndsAt, seq }` | `turnEndsAt` is the deadline of the turn that just started; null only when the match ended |
| `match:state` | `{ matchId, snapshot, seq, seats, turn: { playerId, turnEndsAt }, players[] }` | Full snapshot — replaces the client mirror wholesale (FR-57). `players[]` carries per-player presence: `{ userId, seat, colour, disconnected, graceEndsAt, missedTurns, result }` |
| `match:ended` | `{ matchId, winnerId, standings[], seq }` | `standings[]` is `{ userId, seat, colour, rank, result: 'win' \| 'loss' \| 'forfeit', tokensHome }` — winner rank 1; others by tokens home (desc), then total steps (desc), then seat (asc) |
| `action:rejected` | `{ matchId, requestId?, code, message }` | The intent was rejected; **state is unchanged**. `code` is one of §6; the rejection is logged server-side with code + account (no tokens). Clients surface it without changing local state |
| `player:disconnected` | `{ matchId, playerId, graceEndsAt, seq }` | Grace is running (60 s from disconnect) |
| `player:reconnected` | `{ matchId, playerId, seq }` | Player reconnected inside grace; followed by a fresh `match:state` |
| `player:forfeited` | `{ matchId, playerId, seq }` | Player forfeited (BR-15): tokens removed, recorded as a loss; the match continues if ≥ 2 remain, else the sole remaining player wins |

**Not built:** `invitation:received` (SDD §12.6, FR-62) — Stage 3 scope;
no emission exists in Phase 5.

### 4.3 `seq` / `requestId` discipline (FR-51, FR-53)

- Clients apply server game broadcasts **in `seq` order** and ignore any
  event whose `seq` is not exactly `last + 1`. On a gap they send
  `state:request { matchId, lastSeq }` and replace their mirror with the
  returned `match:state`. (Flutter: `OrderedEventBuffer` in
  `diceup_app/lib/data/online/game_socket_client.dart`.)
- Every client mutating intent carries a client-generated UUID
  `requestId`. The server stores it on the `move_events` row
  (`UNIQUE (match_id, request_id) WHERE request_id IS NOT NULL`):
  a duplicate `requestId` returns the **original result with the
  original `seq`s** — never a second transition. Stale requests are
  rejected with `STALE_STATE`. A follow-up row (turn change / match end)
  shares the primary row's `requestId` implicitly: the follow-up is
  re-emitted from the primary row's stored payload (see
  `socketEventsForStoredIntent` in `match-payloads.ts`).
- `seq` layout: the primary row first (`dice_rolled`, then `token_moved`),
  one follow-up row (turn change or match end) at last primary `seq + 1`.

### 4.4 Error codes (`action:rejected` and `exception`)

Game codes (all in `backend/src/common/errors/error-codes.ts`; REST codes
are in `06-rest-api.md`):

| Code | HTTP* | Meaning |
|---|---|---|
| `ROOM_NOT_FOUND` | 404 | No open room with that code / id |
| `ROOM_FULL` | 409 | Room already at its player limit |
| `ROOM_STARTED` | 409 | Room already started a match |
| `NOT_ROOM_MEMBER` | 403 | Caller is not a member of the room |
| `NOT_ROOM_HOST` | 403 | Caller is not the host (e.g. `match:start`) |
| `ALREADY_IN_ROOM` | 409 | Caller is already in a room |
| `ALREADY_IN_MATCH` | 409 | Caller is already in a match |
| `ALREADY_IN_MATCHMAKING` | 409 | Caller is already queued |
| `NOT_IN_MATCHMAKING` | 409 | Caller is not queued (leave/status) |
| `MATCHMAKING_UNAVAILABLE` | 503 | Matchmaking needs Redis and it is down |
| `MATCH_NOT_FOUND` | 404 | No such match |
| `NOT_MATCH_PLAYER` | 403 | Caller is not a player of the match |
| `NOT_YOUR_TURN` | 409 | It is not the caller's turn |
| `ILLEGAL_MOVE` | 409 | Engine rejected the move (incl. wrong phase) |
| `MATCH_FINISHED` | 409 | Match already ended |
| `STALE_STATE` | 409 | Stale / duplicate-superseded request |
| `MATCH_UNAVAILABLE` | 503 | Match needs Redis and it is down |

\* HTTP column is the REST mapping; on the socket the same `code` arrives
in `action:rejected` / `exception` with no HTTP status. `VALIDATION_FAILED`
(400), `UNAUTHORIZED` (401), `RATE_LIMITED` (429) and `PAYLOAD_TOO_LARGE`
(413) behave as in `08-socket-io.md`.

## 5. Reconnect / recovery contract (FR-54–FR-57, NFR-32/33)

- **Presence.** `presence:user:{userId}` (Redis String, TTL 30 s) is
  refreshed on heartbeat. A connected-but-idle client with no heartbeat
  for ~30 s is marked DISCONNECTED — the socket may still be alive; the
  mark is about liveness, not the transport. Grace protects the player
  (see below).
- **Disconnect.** On disconnect the server marks the player
  DISCONNECTED, broadcasts `player:disconnected { graceEndsAt }`, and
  starts the **60 s grace** (seeded `gracePeriodSeconds`). The match
  continues; the disconnected player's turns auto-play on timer expiry
  and count as missed turns.
- **Reconnect.** Same account, any socket: re-authenticate (handshake JWT
  + per-message re-validation), re-join the match room, receive a full
  `match:state` (snapshot + turn deadline + per-player presence) plus
  `player:reconnected`. Target: restore within 5 s p95 (NFR-32). The
  Flutter client auto-reconnects with back-off
  (`game_socket_client.dart`) and shows a "Reconnecting" state.
- **Forfeit (BR-15).** Grace expiry, **3 consecutive missed turns**, or
  voluntary mid-match leave → forfeit: the player's tokens leave the
  board (back to the yard), the loss is recorded, `player:forfeited` is
  broadcast, and the turn skips forfeited players. The match continues
  if ≥ 2 players remain; otherwise the sole remaining player wins and
  `match:ended` carries forfeit standings.
- **Turn deadlines (FR-52).** The turn timer is **30 s** (seeded
  `turnTimerSeconds`), server-side only. On expiry the server auto-rolls
  (if needed) and auto-moves with the **first legal move in engine
  order**, or skips if no legal move exists; each expiry counts as a
  missed turn. Exactly one timeout transition per turn (per-match Redis
  lock + `turn_epoch`). The deadline is persisted on the stored intent
  payload (`turnEndsAt`) so a duplicate `requestId` re-emits the exact
  original result and a restart re-arms the same deadline.
- **Restart recovery (NFR-33).** Each in-progress match is restored from
  persisted state (`move_events` replay via `match-replay.ts`, checkpoint
  snapshot on the latest row) or cleanly cancelled without corrupting
  results. No data in Redis is the sole copy of a final match result
  (CI-05): the result + participants + ruleset + ordered move log are
  persisted atomically in one transaction (FR-58) and no edit path exists.
- **Redis down.** New online matches are refused with a clear error
  (`MATCH_UNAVAILABLE` / `MATCHMAKING_UNAVAILABLE`); REST reads keep
  serving from PostgreSQL; in-progress matches continue on the node
  holding them (state checkpointed in PostgreSQL after every transition).
  Verified by `backend/test/integration/redis-down-gameplay.e2e.spec.ts`.

## 6. Timers — seeded values

| Value | Seconds | Source |
|---|---|---|
| Turn timer | 30 | `game_configurations.turn_timer_seconds` (default 30) |
| Grace period | 60 | `game_configurations.grace_period_seconds` (default 60) |
| Missed-turn limit | 3 | `game_configurations.missed_turn_limit` (default 3) |
| Max room players | 4 | `game_configurations.max_room_players` (default 4) |

Seeded from the `game_configurations` row (migration 0003, entity
`game-configuration.entity.ts`). There is **no admin writer** in Phase 5
(FR-79 is Stage 3); the values are the phase's seeded defaults, not
per-match configuration.
