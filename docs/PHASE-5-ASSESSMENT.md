# DiceUp Phase 5 — Implementation Assessment

**Date:** 2026-11-28 (PKT)
**Base:** `implementation/foundation-phase-2-3` tip `ba0d37c5a3b9864de3ec0cb6121f4e824dc13b18`
("feat(phase4): complete online phase 4 backend foundation"), parent `102884a`
**Branch (staged, unpushed):** `feature/online-phase-5-gameplay`
**Sources:** SRS v0.1 (2026-11-16, Draft — not approved), SDD v1.0 (2026-11-21,
Draft — not approved), `docs/TRACEABILITY.md`, `docs/ruleset.md`,
`docs/PHASE-4-PLAN.md`, `backend/docs/01–10`, full `backend/src` and
`diceup_app/lib` trees at the base commit.
**Method:** read-only audit (four parallel workers + coordinator synthesis).
No test suite was executed in this audit; test counts below are as documented
in the tree (`backend/docs/09-testing.md`) or counted from files read, and are
labelled as such. They must be re-measured by running the suites in Stage 8.

## Verdict

Phase 5 is **buildable on Phase 4, with no rework of the foundation required** —
but **all gameplay is unbuilt**. Authentication, guards, the Socket.IO shell,
Redis adapter, rate limiting, the vector loader, and the transaction pattern are
verified in the base and reusable as-is. Every FR-43–FR-59 requirement, all
online tables, the TypeScript engine, timers, reconnection/forfeit, and all
Flutter online screens are absent and must be written.

Six scope decisions must be resolved before or with implementation (they are
not code questions — they change what gets built): OD-05 (is matchmaking Stage 2
or Stage 3?), OD-11 (host-selectable rule options online?), the Stage 2/3
boundary for friend invitations (FR-48 vs FR-60–62) and for history/stats/
ranking (FR-64–67), the source of the 30/60/3 timer values without FR-79 admin
config, and the UC-09 E2 "flagged match" state (no such status exists in the
schema). The brief assumes Stage 2 scope; anything Stage 3 must be explicitly
scoped out or explicitly commissioned.

The governing rule conflicts are settled, not open: the Dart engine wins over
the docs wherever they disagree (D-20: 51+4+1 home path, release to step 1,
BR-11 not BR-25, three-phase turn machine). The TypeScript engine must copy
the Dart engine, not the SDD pseudocode.

## 1. Existing completed functionality

**Backend — Phase 4 (verified in base):**
- NestJS 11 + TypeScript, global prefix `/v1`; TypeORM + PostgreSQL 16;
  ioredis + Redis 7; Socket.IO 4.8.3 with Redis adapter (two-node broadcast
  proven by e2e test).
- Auth: register/login/refresh/logout, email verification + resend,
  forgot/reset password, Argon2id (64 MiB/3/1), RS256 JWT (15-min access,
  30-day rotating opaque refresh, family revocation on reuse), per-request
  DB re-check of user/`sid`/status, daily cleanup cron.
- Guards: global REST chain Jwt → AccountStatus → Roles → RateLimit;
  `EmailVerifiedGuard` on users routes; `WsJwtGuard` per handshake and per
  socket message; socket rate limit 20 events/s, disconnect after 5 violations.
- Users: profile view/edit, password change, preferences, deletion-request
  marker (anonymisation NOT implemented, awaits OD-08).
- Health: liveness + readiness (PostgreSQL `SELECT 1` + Redis `PING`).
- Mailer interface + log/SMTP transports; `PushSender` interface only.
- 16 REST endpoints (health ×2, auth ×8, users ×6). No rooms/matches/
  matchmaking/friends/leaderboard/admin routes exist.
- Socket: namespace `/game`, handshake JWT auth, `connected`/`ping`/`pong`/
  `exception` only. The gateway header states rooms, matchmaking, gameplay,
  presence, and invitations do **not** exist.
- Config: Joi-validated env, fail-fast in production; `RULESET_VERSION=1.0.0`
  pinned; `TRUST_PROXY` (H-03); 100 KB REST / 10 KB socket payload caps;
  response envelope `{success, data | error{code, message, details, correlationId}}`;
  per-field validation `details`; Pino logging with secret redaction.
- Security review Stage 4 closed H-01 (dead Redis boot crash), H-02
  (concurrent duplicate registration 500 → 409), H-03 (trust proxy), and
  M-01–M-08 (per-field errors, DB fail-fast, throttle reset, request-id,
  token length caps, loopback check, JWT keypair half-config, .gitignore).

**Offline Flutter (Phases 1–3 + M1–M4, verified in base):**
- Full offline Ludo: Dart engine (`LudoGame`, `Board`, `Token`, `RulesetConfig`,
  `GameState`, strict JSON), AI (Easy/Medium/Hard), Riverpod composition root,
  SQLite persistence (5 tables), settings, statistics, history, results,
  premium design system, accessibility (reduced motion, 48 dp minimums).
- Shared rule vectors: single `diceup_app/test/vectors/rules.json`, 23 cases,
  Dart runner enforces ≥14-case gate + BR-04…BR-13 coverage gate.
- Home screen carries the only online affordance: a "Play Online" row opening
  a login-prompt dialog ("online play arrives in Phase 5"); mode selection has
  a matching inert online card.

## 2. Missing functionality (all of Phase 5's build)

| Area | Missing |
|---|---|
| Rooms | Module, REST `POST /rooms`, tables, socket `room:join/leave/ready`, host transfer, 10-min empty-room sweeper, code generation/validation |
| Matchmaking | Queue, endpoints, grouping, cancel, disconnect/stale handling (only the Redis key name exists) |
| TS engine | Entire `backend/src/game/` (or equivalent): Board, Token, RulesetConfig, GameState, LudoGame, dice (crypto-secure RNG), move validation, captures, win |
| Timers | Turn timer (30 s), grace (60 s), missed-turn limit (3), heartbeat detection (10 s proposed), auto-play (first legal move, proposed) |
| Reconnection | Grace handling, `match:state` serving, presence writes, restart recovery (replay from `move_events` or clean cancel) |
| Persistence | `rooms`, `room_members`, `matches`, `match_players`, `move_events`, `game_configurations` tables (+ `rankings` only if Stage 3 is in scope) |
| Socket events | All game/room events in §6 (only `ping`/`pong` exist) |
| Flutter online | Auth screens + API client + socket client + secure token storage + rooms/lobby/matchmaking screens + `OnlineGameController` + connection/reconnection UI + deep links (go_router adoption recorded as the prerequisite) |
| Tests | All Phase 5 suites (§8); load/concurrency tests; parity run of the TS engine against the 23 vectors |
| Docs | Phase 5 plan, API + socket event docs, traceability updates |

## 3. Reusable Phase 4 components

| Component | Location | Use in Phase 5 |
|---|---|---|
| Auth service, token service, JWT keys/strategy, login throttle, email tokens, password hasher | `backend/src/auth/` | As-is; game routes need no `@Public()` — the global JWT guard covers them |
| Guards + `RequestUser` / `@CurrentUser()` | `backend/src/common/guards/`, `backend/src/socket/ws-jwt.guard.ts`, `ws-rate-limit.guard.ts` | Reuse per-message socket auth; the planned `room:join` authorisation guard follows the same pattern (load room from PostgreSQL, check membership/host, never trust a client-claimed room id) |
| Validation | Global `ValidationPipe` (`main.ts`), `flatten-validation-errors.ts`, `WsValidationPipe` | Every new REST DTO and socket event DTO |
| Redis service + keys + per-match lock | `backend/src/redis/redis.service.ts`, `redis-keys.ts` | `incrWithExpiry`, `acquireLock`/`releaseLock` (Lua, token-checked) — already written and unit-tested, no caller yet; key names `matchmaking:queue`, `match:lock:{matchId}`, `match:state:{matchId}`, `room:code:{code}` are reserved — do not invent conflicting names |
| Socket infra | `backend/src/socket/socket-io.adapter.ts`, `game.gateway.ts`, `socket.constants.ts`, `socket.module.ts`, `socket-redis-clients.service.ts`, `socket-rate-limit.service.ts`, `socket-error.ts` | Namespace `/game`, handshake auth, Redis adapter, 20/s limiter, 10 KB cap, `seq` + `requestId` conventions |
| Error codes + envelope + filter + interceptors | `backend/src/common/errors/`, `filters/`, `interceptors/` | New game errors extend the `ErrorCode` enum; socket errors mirror the REST envelope |
| Config / logging / health | `backend/src/config/`, `common/logging/`, `backend/src/health/` | `RULESET_VERSION` is the frozen-at-match-start version each match stores |
| Transaction discipline | `AuthService` (register, refresh rotation with row lock) | Model for the FR-58 atomic match-result transaction; "no edit" rule is structural |
| Test harness | `backend/test/integration/test-app.factory.ts`, `test-helpers.ts` (scratch DB `diceup_test_<pid>_<random>`, all migrations, then drop; real PostgreSQL + Redis) | Phase 5 game e2e specs run on the same factory |
| Vector loader | `backend/test/vectors/rules-vectors.loader.ts` | Conformance harness for the TS engine (NFR-39) — currently schema/coherence validation only; must be extended to the full case shape (`dice`, `steps`, `expectFinal`) |
| Design system + board/dice widgets | `diceup_app/lib/core/design_system/`, `presentation/widgets/ludo_board.dart`, `dice_widget.dart` | Reused by online screens and the online game screen |
| Offline engine (reference) | `diceup_app/lib/domain/engine/` | Behavioural reference for the TS port; do NOT modify it to make the TS engine pass |
| Test seams | `test_providers.dart`, in-memory repository fakes, `FixedDiceRoller` | Model for online fakes/mocks in Flutter tests |

## 4. Required database changes (PostgreSQL, SDD §9.2)

All new in Phase 5 — Phase 4 has only 2 migrations / 4 tables
(`users`, `profiles`, `auth_sessions`, `email_tokens`). Expand-then-contract
from migration 0003 onward (SDD §15.4); `synchronize` stays off.

| Table | Key columns / constraints |
|---|---|
| `rooms` | `id` UUID PK; `code VARCHAR(6)` UNIQUE among open (partial index `WHERE status='open'`); `host_id` FK; `max_players INT CHECK 2–4`; `status CHECK (open/playing/closed)`; `ruleset_version TEXT NOT NULL`; `created_at`, `closed_at` |
| `room_members` | PK `(room_id, user_id)`; `is_ready BOOLEAN DEFAULT FALSE`; `joined_at`; `is_host BOOLEAN` (denormalised for host transfer) |
| `matches` | `id` UUID PK; `room_id` FK (UNIQUE in this baseline [Proposed] — 1 room → 0..1 match); `ruleset_version`; `status CHECK (in_progress/completed/cancelled)`; `winner_id NULL`; `started_at`, `ended_at` |
| `match_players` | PK `(match_id, user_id)`; `seat INT CHECK 0–3`; `colour`; `result CHECK (win/loss/forfeit) NULL`; `finish_rank INT NULL`; `missed_turns INT DEFAULT 0` |
| `move_events` | `id` UUID PK; `match_id`; `seq_no INT NOT NULL`; `actor_id NULL`; `type CHECK (dice_rolled/token_moved/turn_changed/player_forfeited/match_started/match_ended)`; `payload JSONB NOT NULL`; `request_id UUID NULL`; `UNIQUE (match_id, seq_no)`; `UNIQUE (match_id, request_id) WHERE request_id IS NOT NULL` (the FR-53 idempotency guarantee) |
| `game_configurations` | `id` UUID PK; `version TEXT UNIQUE`; `turn_timer_seconds DEFAULT 30`; `grace_period_seconds DEFAULT 60`; `missed_turn_limit DEFAULT 3`; `max_room_players DEFAULT 4`; `created_by`; `effective_from` |
| `rankings` | Only if Stage 3 is in scope (FR-67): `user_id` PK/FK; `points`; `matches_played`, `wins`; rank derived by `ORDER BY points DESC`, not stored |

Indexes (SDD §9.3): `matches (winner_id, ended_at)`, `match_players (user_id, match_id)`,
`move_events (match_id, seq_no)`.

**Redis (SDD §9.4):** keys already reserved in `redis-keys.ts` — wire them now:
`presence:user:{userId}` (String, TTL 30 s), `matchmaking:queue` (sorted set,
score = enqueue time), `match:lock:{matchId}` (TTL 10 s, NX),
`match:state:{matchId}` (Hash/JSON, TTL 5 min, snapshot cache only),
`room:code:{code}` (String → roomId, TTL = room lifetime, optional).
Failure policy: Redis down → refuse new online matches with a clear error, keep
serving REST reads from PostgreSQL; in-progress matches continue on the node
holding them (state checkpointed in PostgreSQL after every transition).
CI-05: no data in Redis shall be the sole copy of a final match result.
No new SQLite tables on device (CI-06: SQLite stores history/statistics/
settings only, never rules or credentials).

## 5. Required backend changes

- **New module `Rooms`** (`backend/src/rooms/` or `backend/src/game/` per SDD
  §5.2.3): `POST /rooms` (create, host chooses limit 2–4 + permitted rule
  options per UC-06 — see decision OD-11), room-code generation (6-char
  uppercase alphanumerics excluding confusables, SDD §8.3 DA-02), join by code
  with `ROOM_NOT_FOUND` / `ROOM_FULL` / `ROOM_STARTED` errors, leave,
  host transfer to longest-present member (or close if empty, FR-59),
  10-min empty-room sweeper, membership/readiness state.
- **New module `Matchmaking`** (SDD §5.2.4): `POST /matchmaking/join|leave`,
  `GET /matchmaking/status`; one queue entry per player in the Redis sorted
  set; when the group size is present, atomically pop them, create a room,
  notify each; remove on cancel/disconnect; never group a suspended player or
  a player already in a room. Group size: SDD proposes 4 (see conflict C-13).
- **New module `Game` / TS engine** (`backend/src/game/`): mirror of the Dart
  engine with the same names/responsibilities (SDD §10.4) — `Board` (52-track
  geometry, start/star/safe sets, `cellAt`), `Token` (`stepsTaken` 0–56,
  `canMove`), `RulesetConfig` (8 fields, defaults, `validate()`), `GameState`
  (immutable snapshot, strict `fromJson`/`toJson`), `LudoGame` (`newMatch`,
  `fromState`/`restore`, `rollDice`, `legalMoves`, `applyMove` returning
  `MoveResult`, `nextTurn`), `Move`, `DiceRoller` (production: cryptographically
  secure RNG, no modulo bias; fixed-sequence roller for vector replay).
  Error taxonomy preserved distinctly: setup errors, `StateError` (wrong
  phase/finished), `ArgumentError` (illegal move), `FormatException`
  (malformed snapshot).
- **Match aggregate + persistence:** in-memory match under the per-match Redis
  lock (multi-node), checkpointed to PostgreSQL after every accepted
  transition — the `move_events` row *is* the checkpoint; replay reproduces
  state (SDD §8.6). Match end persists result + participants + ruleset
  version + ordered move log in a single atomic transaction (FR-58, NFR-31);
  no client/admin may edit a result (BR-17, NFR-31).
- **Timers:** server-side only. Turn timer 30 s (FR-52, BR-20); on expiry
  auto-roll (if needed) + auto-move with the **first legal move in engine
  order** (SDD §8.5, [Proposed] DA-04 — "the server must not play 'well'"),
  or skip if no legal move; each expiry counts as a missed turn (SDD §8.7).
  Exactly one timeout transition per turn; duplicate timeout processing
  prevented (per-match lock). Heartbeat detection 10 s [Proposed].
- **Reconnection:** disconnect → mark DISCONNECTED, broadcast
  `player:disconnected {graceEndsAt}`, start 60 s grace; reconnect = same
  account, any socket, re-authenticate, full current state sent (FR-55,
  NFR-32: restore within 5 s p95); grace expiry, 3 consecutive missed turns,
  or voluntary leave → forfeit per BR-15 (tokens removed, recorded as loss;
  match continues if ≥ 2 remain, else sole remaining player wins). Restart:
  each in-progress match restored from persisted state or cleanly cancelled
  without corrupting results/rankings (NFR-33).
- **Security (SDD §8.8 anti-cheat table):** client-sent dice value ignored +
  logged; only the server declares the winner; turn/token-ownership checks;
  `requestId` de-dup returns the original result; stale requests rejected;
  server-side timers only; per-match Redis lock across nodes. Log every
  `action:rejected` with code + account (no tokens/passwords, SDD §13.5).
  Address residuals L-01 (global per-IP limit for unauthenticated requests to
  protected routes, exempting health) and L-02 (per-IP/per-user socket
  **connection** rate limit) — both are Phase 5 recommendations in
  `backend/docs/10-security.md`. Re-test `redis-down` with game traffic:
  the H-01 adapter publish queue is unbounded while Redis is down and was
  "bounded in Phase 4 (no broadcast traffic yet)".
- **Config:** seed a `game_configurations` row (or equivalent) for the 30/60/3
  defaults — the only writer is FR-79 admin config (Stage 3); no Phase 5
  mechanism exists (gap G-4). `RULESET_VERSION` stays the frozen version.

## 6. Required Socket.IO events (SDD §12.6, namespace `/game`)

SRS §5.4 states event names are illustrative and "shall be finalized in the
design phase"; SDD §12.6 finalises them. Client events express intent only;
server events carry authoritative results; every server game event carries an
increasing `seq` (FR-51); every client mutating intent carries a
client-generated UUID `requestId` (FR-53 idempotency). Clients apply broadcasts
in sequence order and ignore any event whose `seq` is not exactly last+1,
requesting a snapshot on a gap.

| Direction | Event | Payload / rule |
|---|---|---|
| C→S | `room:join` | `{ roomCode }` |
| C→S | `room:leave` | `{ roomId }` |
| C→S | `room:ready` | `{ roomId, ready: boolean }` |
| C→S | `match:start` | `{ roomId }`, host only |
| C→S | `dice:roll` | `{ matchId, requestId }`, **no value supplied** |
| C→S | `token:move` | `{ matchId, tokenId, requestId }` |
| C→S | `state:request` | `{ matchId, lastSeq }` |
| S→C | `room:updated` | `{ room, members[], ready{} }` |
| S→C | `match:started` | `{ matchId, seats[], rulesetVersion }` |
| S→C | `dice:rolled` | `{ matchId, playerId, value, seq }` |
| S→C | `token:moved` | `{ matchId, tokenId, landing, captured[], extraTurn, winner, seq }` (+ `turn: {playerId, turnEndsAt}` per example) |
| S→C | `turn:changed` | `{ matchId, playerId, turnEndsAt, seq }` |
| S→C | `player:disconnected` / `player:reconnected` / `player:forfeited` | `{ matchId, playerId, graceEndsAt? }` |
| S→C | `match:state` | `{ matchId, snapshot, seq }` — full snapshot, replaces client mirror wholesale |
| S→C | `match:ended` | `{ matchId, winnerId, standings[], seq }` |
| S→C | `action:rejected` | `{ matchId, requestId?, code, message }`, state unchanged |
| S→C | `invitation:received` | `{ roomCode, fromUser }` (FR-62; SDD addition, not in SRS §5.4) |

Existing (Phase 4, keep): `connected` (`{userId, socketId, connectedAt}`),
`ping`/`pong` (`{requestId}` / `{requestId, serverTime}`), `exception`.
Rooms are Socket.IO rooms inside `/game`, named `room:{roomId}`; joining
authorisation is a guard on `room:join` that loads the room from PostgreSQL,
checks membership/host, then calls `client.join(...)`.

## 7. Required Flutter changes

- **Dependencies (new, `pubspec.yaml`):** HTTP client, Socket.IO client,
  secure token storage, deep-link routing (`go_router` adoption — recorded in
  `app_routes.dart` as deferred to Phase 5 when room invitations land).
  Currently present: only `flutter`, `flutter_localizations`,
  `cupertino_icons`, `sqflite`, `path`, `flutter_riverpod`. Absent (verified):
  `http`/`dio`, `socket_io_client`/`web_socket_channel`,
  `flutter_secure_storage`/`shared_preferences`, `go_router`, any auth package.
- **Auth:** login / register / forgot-password / verification screens (UI-05),
  auth state provider, session persistence via secure storage (FR-09: tokens
  only in platform secure storage, never SQLite), silent refresh +
  re-handshake on mid-match expiry, logout (FR-05), expired/invalid-credential
  handling, loading/success/error states. Backend endpoints already exist.
- **API client:** base URL / environment config, REST client, request/response
  models, error mapping from the envelope `code`, retry/timeout policy.
  Never store tokens in SQLite (the DB layer explicitly holds no tokens).
- **Socket client:** connection manager, JWT handshake auth, event
  subscription/emitting with `requestId`, server-event application in `seq`
  order, snapshot request on a gap, auto-reconnect with back-off (NFR-32).
- **Rooms / lobby / matchmaking (UI-07):** create (limit 2–4 + ruleset
  summary → 6-char code with copy/share), join (code entry + specific
  errors), member list + ready toggles, invite-friend button (see C-8 scope),
  host Start (enabled only when FR-47 holds: host + ≥ 2 present + all ready),
  Leave. `GameRoomModule` API per SDD §5.1.8: `createRoom(maxPlayers)`,
  `joinRoom(code)`, `leaveRoom()`, `setReady(ready)`, `startMatch()`,
  `inviteFriend(userId)`.
- **Online game screen (UI-03, SDD §3.2):** one game screen, two controllers —
  new `OnlineGameController` rendering server snapshots and sending intents;
  board/dice/token widgets reused once. Connection state + turn timer /
  countdown ring on the board; grace state; "Reconnecting" state (UC-10);
  `action:rejected` surfaced without changing local state; optimistic move
  shown only as a transient "pending" shimmer (SDD §4.6). Mid-game leave →
  forfeit warning (SDD §11.2, online equivalent of FR-28).
- **Navigation:** deep link from invitation opens Lobby with the code
  pre-filled; a link requiring login routes through Login first (SDD §11.2).
  New routes for auth, lobby, matchmaking, online game; `app_routes.dart`
  extended (named routes today, no go_router).
- **History/statistics:** online half (segmented Local/Online, UI-09) is
  FR-64/Stage 3 — out of scope unless commissioned; local screens stay
  SQLite-only (BR-18).
- **Preserve:** offline gameplay untouched (same engine, controller, screens);
  design system, theme, 48 dp minimums, reduced-motion handling, string
  discipline (`check_strings.sh`), boundary rules (`check_boundaries.sh` —
  new online providers/controllers must respect the domain purity rule and
  the provider-graph construction rule).

## 8. Existing test coverage

**Backend (counts as documented in `backend/docs/09-testing.md`, Stage 5
re-measured 2026-11-27 — NOT re-run in this read-only audit; re-measure in
Stage 8):** 30 spec files — 22 unit, 6 integration, 1 security, 1 vectors.
Documented: unit 156 tests / 22 suites; e2e 73 tests / 8 suites; **229/229
passing, 0 failed**. Suites: auth flows, authz matrix (4/7 guarded routes —
known gap G-1), full-journey (register → socket `ping` → refresh → logout →
revocation), health, redis-down (H-01), socket (auth refusals, `ping`/`pong`,
rate-limit bursts, two-node broadcast), auth-security (enumeration, H-02
concurrent register). Vectors spec: 4 tests, schema/coherence only.
**Zero tests exist for** rooms, matchmaking, engine, timers, reconnection,
game socket events, or load. `backend/test/load/` does not exist. No CI
(`.github/workflows/` absent — Workflows permission 403); the vectors CI job
is staged locally, unpushed.

**Flutter (file counts from reading; no tests run):** 48 Dart files +
`rules.json` — root 20, `data/local` 6, `domain` 1, `engine` 8,
`repositories` 2 + 7 fakes, `usecases` 3, `vectors` 1 + fixture. All offline.
**Zero test files exist for** auth, API, socket, online gameplay, rooms, or
matchmaking. Check gates (`diceup_app/tool/check.sh`): `flutter pub get` →
`dart format` → `flutter analyze --no-fatal-infos` → `flutter test` →
`check_boundaries.sh` → `check_strings.sh`. Flutter 3.50.1 required.

**Shared vectors (`diceup_app/test/vectors/rules.json`, 72,239 bytes):**
23 cases, 46 replay steps (25 `roll`, 20 `move`, 1 `moveIllegal`). All 23 are
2-player red-vs-green, both human, starting `currentPlayerIndex: 0`,
`awaitingRoll`. 17 default-ruleset cases; 6 single-field variants.
Coverage by rule label: BR-06: 6, BR-10: 6, BR-08: 5, BR-04: 3, BR-07: 3,
BR-09: 2, BR-13: 2, BR-05: 1, BR-11: 1, BR-12: 1, FR-21: 1.
**Vector gaps (verified absences):** no 3- or 4-player case; no AI seat; no
case starting mid-turn (`awaitingMove`) or with pre-set `consecutiveSixes > 0`;
no release-on-1-only config; no `maxConsecutiveSixes` other than 3 or 0; no
combined-variant case; no capture spanning two different opponents; no
no-legal-move case with track tokens blocked by exact finish; no `nextTurn()` /
`StateError` / wrong-player vectors; no snapshot round-trip vector. BR-01/02/03/
14 are covered only by Dart unit tests (125 `test(` calls across
`test/engine/`), not by shared vectors. Forfeit (BR-15), blockade, and
continue-to-rank have no vectors because they have no Dart engine
implementation — they need design decisions first.

**Phase 5 test work required (brief §16):** backend unit (room service,
validation, matchmaking, engine, turns, dice, legal moves, captures, win,
timers, reconnection, transitions); API integration (auth flows, rooms,
matchmaking, lifecycle, unauthorised/invalid); Socket.IO (auth, subscriptions,
join/leave, start, dice/move/capture/turn sync, invalid/duplicate/simultaneous,
disconnect/reconnect, completion); parity (same vectors, Dart + TS, exact
coverage reported); multiplayer scenarios (full matches, lobby, turns, captures,
disconnects, reconnects, timeouts, completion); Flutter (auth, session restore,
navigation, rooms, matchmaking, socket handling, reconnection, online state,
error/loading states); offline regression (full existing suite stays green);
load/concurrency per NFR-05/06/24 (k6 if appropriate — no k6 script exists
today; the 200-user / 500-player bars are BLOCKED/deferred to Phase 5).

## 9. SRS/SDD requirements mapped to implementation tasks

Stage 2 = FR-42–FR-59 (online multiplayer). Stage 3 = FR-60–69 (social),
FR-70–82 (admin). Anything Stage 3 is out of Phase 5 scope unless explicitly
commissioned (see §11).

| Requirement | Task | Stage | Status at base |
|---|---|---|---|
| FR-42 online only for authenticated players; guests prompted; offline unaffected | Wire guards into rooms/matches; Flutter prompt already exists (M2.10) | 2 | Backend verified; Flutter wiring |
| FR-02/03/04/05/06 registration, verification, login, logout, recovery | Flutter auth screens + session restore (backend done) | 2 | Backend verified; Flutter new |
| FR-07/08 profile, password change, preferences | Flutter account screens (backend done) | 2 | Backend verified; Flutter new |
| FR-09 session persists; tokens only in secure storage | Secure-storage session layer + silent refresh | 2 | Backend verified; Flutter new |
| FR-10 account deletion | Out of scope except existing request marker | 3 | Partial (request only; anonymisation awaits OD-08) |
| FR-43 create room (limit 2–4, unique code, host) | Rooms module + `rooms` table + `POST /rooms` + Flutter create UI | 2 | New |
| FR-44 join by code (open, not full, specific errors) | Join validation + `room:join` + Flutter join UI | 2 | New |
| FR-45 matchmaking queue + auto-grouping [Proposed] | Matchmaking module + Redis queue + endpoints + UI | 2/3? | New — decide OD-05 |
| FR-46 readiness per member, shown to all | `room:ready` + `room:updated` + lobby UI | 2 | New |
| FR-47 start: host + ≥ 2 present + all ready | `match:start` + match creation + seat assignment (join order) | 2 | New |
| FR-48 invite friend to room | Room-code sharing (minimum); friend invite needs FR-60/62 | 2/3 | New — decide C-8 |
| FR-49 server generates all dice | TS engine RNG + `dice:roll` (no client value) | 2 | New |
| FR-50 server verifies turn/roll/move legality; reject with code, state unchanged | Engine validation + `action:rejected` + per-match lock | 2 | New |
| FR-51 broadcast in order with increasing `seq` | `seq` on every server game event; client gap → snapshot | 2 | New |
| FR-52 turn timer 30 s; expiry auto-roll + legal move or skip | Timer service + auto-play (first legal move, proposed) | 2 | New |
| FR-53 at-most-once processing; dedupe/stale rejection | `requestId` + `UNIQUE (match_id, request_id)` + lock | 2 | Seams only |
| FR-54/55/56 disconnect detection, grace 60 s, reconnect, forfeit | Presence + grace + `match:state` + forfeit (BR-15) | 2 | New |
| FR-57 single authoritative state; resend on request | `state:request` + `match:state` + checkpointing | 2 | Design only |
| FR-58 atomic persist of result + participants + ruleset + move log | `matches`/`match_players`/`move_events` + one transaction | 2 | Pattern only |
| FR-59 leave before start; host transfer / close if empty | Leave handling + host transfer + sweeper | 2 | New |
| FR-60/61/62 friends, friend list, invitations | **Stage 3 — out of scope** (code-share invite is the Phase 5 minimum) | 3 | Not built |
| FR-64/65/66/67 online history, statistics, leaderboard, ranking | **Stage 3 — out of scope** (FR-58 records; FR-67 does not run) | 3 | Not built |
| FR-68 notifications / FR-79 game config | **Stage 3 / Phase 7** — provider + admin UI not in Phase 5 | 3 | Not built |
| NFR-05/06/24 load + latency + 500 concurrent players | k6/multi-client load tests; measure, do not claim | 2 | Blocked |
| NFR-12 1,000-match AI sim | Offline; blocked on OD-M4-01 (M4.1) — only affects TS conformance sim construction | 2 | Blocked |
| NFR-14/17/18/20/21/37 security | Negative tests (NFR-18), L-01/L-02 limits, `action:rejected` logging | 2 | Partial (Phase 4 verified base; NFR-18 tests new) |
| NFR-31 atomic results, no edits | FR-58 transaction; structural "no edit" | 2 | Pattern only |
| NFR-32/33 reconnect ≤ 5 s p95; restart restore-or-cancel | Reconnection + replay/cancel design | 2 | New |
| NFR-39 shared Dart/TS vectors in CI | Extend TS loader to full case shape; TS replay harness; run both suites on the same `rules.json` | 2 | Foundation only |
| BR-01–BR-20 rules | TS engine mirrors Dart (see §10 for the settled deviations) | 2 | Dart verified; TS new |
| UI-01/03/05/07/09, SDD §3.2/§4.6/§5.1.7/§5.1.8/§11.2 | Flutter online screens + `OnlineGameController` + deep links | 2 | New (UI-09 online half is Stage 3) |

## 10. Conflicts — settled, follow the engine (do not re-litigate)

| ID | Conflict | Governing rule for Phase 5 |
|---|---|---|
| C-1 | Docs say home path is 5 cells; engine implements 51+4+1 = 56 steps | **Engine wins (D-20).** TS engine implements 51 track + 4 home-path + home. SDD §6.2 still needs its re-issue amendment. |
| C-2 | SDD §6.5 pseudocode releases a yard token to step 6 (`stepsTaken += roll`) | **Engine wins.** Release lands on step 1, spending the roll. |
| C-3 | SDD §6.5 cites "BR-25 / FR-25" for winning | No BR-25 exists. Winning is **BR-11**. Never cite BR-25. |
| C-4 | SDD §6.4 turn machine has a MOVING phase | **Engine wins.** Phases are `awaitingRoll`, `awaitingMove`, `finished`. |
| C-5 | NFR-12 "AI-only" sim vs BR-01 "≥ 1 human" per match | Open OD-M4-01 (M4.1). TS conformance sim needs an explicit exemption or human-seat stub. |
| C-6 | SDD §1.4 claims no SRS/SDD disagreements were found | False on its own evidence (C-1–C-4). The rule in force is D-20 / `ruleset.md` §5 ("the engine wins"), not "SRS governs" applied literally. |
| C-7 | AI pacing 600–1,200 ms (SRS FR-40, proposed) vs 700–1,199 ms implemented (D-31) | D-31 governs; offline-only anyway (online is human-only, A-10). |
| C-8 | SRS Stage 2 lists "friend play" but FR-60/61/62 are Stage 3 | Room-code sharing is the Phase 5 minimum; friend-based invite needs Stage 3 scope or an explicit decision. |
| C-9 | UC-09 step 7 / SDD §8.7 update rankings on match end, but FR-64–67 are Stage 3 | FR-58 records the result; FR-67 does not run in Phase 5 unless commissioned. Ranking algorithm OD-06 is open; DA-08 simple points is proposed, D-08 forbids hard-coding it. |
| C-10 | Host chooses rule options (SRS §7.4, UC-06) vs SDD §8.4 match uses config version | Decide OD-11: fixed config-version ruleset, or host-selectable options within an admin-approved set (needs FR-79). |
| C-11 | Timer values "configurable via FR-79" (Stage 3 / Phase 7) | Phase 5 needs a source for 30/60/3 (seed a config row or equivalent) — see G-4. |
| C-12 | UC-09 E2 "flagged match" has no designed state | `matches.status` is only `in_progress/completed/cancelled`. Either add a flagged/error state or record E2 as unimplementable as written. |
| C-13 | Matchmaking group size: SRS silent, SDD proposes 4 | SDD default is 4. A brief assuming 2-player matchmaking groups contradicts it. |
| C-14 | SRS §5.4 vs SDD §12.6 event-shape deltas | SDD finalises: namespace `/game`, `room:leave`/`room:ready` take `{roomId}`, `state:request` gains `lastSeq`, new `invitation:received`, version gating `UPGRADE_REQUIRED` [Proposed]. |

## 11. Gaps — decisions the docs leave unspecified (report, don't silently invent)

- **G-1** Room limit change after creation; whether a match may start with fewer than the room limit (FR-47 implies yes for ≥ 2, never stated).
- **G-2** Matchmaking criteria: none specified (arrival order only, SDD §5.2.4). No skill/rank/region/wait-time criteria; no maximum wait; no partial-group start rule.
- **G-3** Invitation expiry duration: "expires" with no duration anywhere (UC-08 A1). Whether an invite carries the code, auto-joins, or may go to non-friends is unspecified.
- **G-4** Source of timer/grace/missed-turn values in Phase 5 (see C-11).
- **G-5** "Missed turn" definition: SDD defines it as a timer-expiry auto-play (including disconnected players' turns); the SRS never defines it.
- **G-6** Matchmaking queue timeout / failure behaviour: "keep waiting or cancel" with no timeout value.
- **G-7** "Return to active match" flow (UC-07 E2): no endpoint, screen, or state machine designed.
- **G-8** Orphan-room cleanup on failed creation (UC-06 E1): only the 10-min empty-room sweeper exists, which would leave an orphan visible for up to 10 minutes.
- **G-9** Turn-timer phase semantics: FR-52 does not distinguish expiry before vs after the roll; SDD §8.5 resolves it (timer spans the whole turn; expiry auto-rolls if needed and auto-moves, or skips).
- **G-10** Auto-play move choice: "first legal move in engine order" is SDD-proposed (DA-04), not an SRS rule.
- **G-11** Seat order: SDD proposes join order (DA-03); SRS is silent.
- **G-12** Room-code format: SDD proposes 6 uppercase alphanumerics excluding confusables (DA-02); SRS says only "unique room code".
- **G-13** Disconnect-detection interval: SDD proposes 10 s heartbeat timeout (Q-09); SRS says only "within a configured interval".
- **G-14** Reconnection identity: "same account, any socket" (SDD §8.7); session requirements, login-elsewhere behaviour, and grace survival across a restart are unspecified.
- **G-15** Voluntary mid-match leave: forfeit trigger (FR-56) but no specified UX copy, confirmation, or delay; whether already-played moves stay in the log is unstated (append-only implies yes).
- **G-16** Online ruleset visibility: SRS §7.4 requires all players to see the active rules in the lobby before readiness; no UI/data shape beyond `rulesetVersion` is designed.
- **G-17** Ranking inputs: OD-06 open; whether forfeits count as losses for ranking is ambiguous (BR-15 "recorded as a loss" vs BR-16 "completed matches").
- **G-18** Push/email providers: not specified (A-04/A-05/OD-09). Offline-friend invitations (FR-62) cannot work end-to-end until a provider is chosen.

**Decisions the brief must resolve before/with implementation:** OD-05
(matchmaking Stage 2 or 3), OD-11 (host rule options), OD-06 (ranking
algorithm, only if rankings are in scope), the Stage 2/3 boundary for FR-48/
FR-60–62 and FR-64–67, the timer-value source (G-4/C-11), and the flagged-match
state (C-12). Everything else in G-1–G-18 can be implemented on the SDD's
proposed defaults, recorded as such — but each must be recorded, not silently
assumed.

## 12. Risks and dependencies

1. **Scope creep across the Stage 2/3 boundary** (friends, invitations,
   rankings, history, admin config) is the largest risk — each item is a
   named Stage 3 requirement with its own open decision. Mitigation: the
   decisions in §11 are taken up front; Stage 3 items are explicitly excluded
   from the Phase 5 PR unless commissioned.
2. **TOCTOU races** (same class as H-02): concurrent `room:join` on the last
   seat, concurrent `dice:roll`/`token:move`, concurrent match creation.
   Mitigation: unique constraints + 23505 handling and/or the per-match Redis
   lock (exists, no caller yet); never rely on a pre-check alone.
3. **Timer/grace correctness** (exactly-once timeout per turn, timer recovery
   after restart, missed-turn counting) — the subtlest state machine in the
   phase; needs dedicated scenario tests, not just unit tests.
4. **Parity drift** between Dart and TS engines: the 23 vectors are all
   2-player and thin on edge cases (§8). Mitigation: add the gap vectors
   listed in §8 *before* the TS engine is judged conformant, and run both
   suites on the same file in CI.
5. **Redis-down behaviour with game traffic:** the H-01 adapter queue is
   unbounded while Redis is down; Phase 4 called it "bounded (no broadcast
   traffic yet)". Phase 5 must set a bound/drop policy and re-test `redis-down`
   with game traffic.
6. **Load bars are unproven:** NFR-05 (95% REST ≤ 500 ms @ 200 users),
   NFR-06 (95% actions ≤ 800 ms), NFR-24 (≥ 500 concurrent players) have no
   k6 script, no harness, and no baseline. Do not claim compliance without
   running them and reporting measured numbers.
7. **No CI exists** for any branch (Workflows permission 403). All verification
   is local until the permission is granted; the vectors CI job is staged
   locally and unpushed.
8. **M4.1 divergence (boundary — do not cross):** the M4.1 remediation batch
   is still unpushed staging-only work, and Anti's Windows tree has diverged.
   Phase 5's base `ba0d37c` does NOT contain it. Overlaps: `settings_screen.dart`,
   `lib/domain/engine/ludo_game.dart`, `docs/IMPLEMENTATION-PLAN.md`,
   `docs/TRACEABILITY.md`, `docs/ruleset.md` (and `ruleset_restore_test.dart`,
   which is absent from this base). If Phase 5 touches those files, note the
   overlap and leave the M4.1 changes alone.
9. **Secrets in the local tree:** `backend/.env` and `backend/.keys/` (dev
   RS256 keypair) exist in staging but are untracked (`.gitignore` excludes
   `.env*` and `.keys/`) — verified via `git ls-files`. The push manifest
   (built from `git ls-files --cached --others --exclude-standard`) must keep
   excluding them; never add them to a manifest.
10. **Offline regression:** the offline suite must stay green; the Dart engine
    must not be weakened to make the TS engine pass (NFR-39, D-05).

## 13. Stage plan (brief §19, Stages 2–9)

| Stage | Work | Entry criterion / exit evidence |
|---|---|---|
| 2 — Auth integration | Flutter auth screens, API client, secure storage, session restore, logout, error states | Backend auth verified (done); Flutter login/register against the real backend on a scratch DB, incl. failure cases |
| 3 — Rooms + matchmaking | Rooms module + tables + codes + readiness + host transfer + sweeper; matchmaking queue + endpoints; lobby UI | OD-05 + OD-11 decided; concurrent-join tests green |
| 4 — Authoritative TS engine | Engine module, validation, transitions, shared vectors extended (gap list in §8), Dart/TS parity run | All 23 existing vectors + new gap vectors pass in both languages on the same file |
| 5 — Real-time multiplayer | Socket event contracts (§6), server-authoritative broadcasts, `seq`/`requestId` discipline, simultaneous-request handling | Multi-client socket e2e green (join/leave/start/dice/move/capture/turn/invalid/duplicate/simultaneous) |
| 6 — Recovery + timers | Disconnect/grace/forfeit, `match:state`, restart recovery, turn timers + auto-play | Scenario tests: disconnect/reconnect, grace expiry, restart restore-or-cancel, timer expiry |
| 7 — Flutter integration | Online screens + navigation, rooms/matchmaking UI, online game screen, connection/reconnection UI | Offline suite still green; online widget tests green |
| 8 — Verification + hardening | All backend + Flutter + parity + scenario tests; load/concurrency (k6); format/lint/analyze; fix regressions | Measured counts reported passed/failed/not-run; no invented numbers |
| 9 — Documentation + PR preparation | Traceability + Phase 5 plan + API/socket docs; diff review; **staged** branch ready for the tap-gated push + draft PR (do NOT push/merge) | Staged HEAD + verification report to the parent; push + PR await Anti's tap |

## Appendix — M4.1 boundary (do not cross)

The M4.1 remediation batch (M4-D1 `fromState` fix, 47 remediation/sim tests,
K-01 cacheExtent fix) is staging-only and unpushed; Anti's Windows tree has
diverged (his own M4-D1 reimplementation, 25/25 tests, plus local modifications
to `settings_screen.dart`, `IMPLEMENTATION-PLAN.md`, `TRACEABILITY.md`,
`ruleset.md`). Phase 5's base does not contain it. Do NOT absorb, overwrite, or
"resolve" the M4.1 reconciliation inside Phase 5. If Phase 5 touches a file the
M4.1 batch also touches, note the overlap here and in the final report and
leave the M4.1 changes alone. The cacheExtent deprecation Anti reported is
K-01 / M4.1 scope, not Phase 5 scope.
