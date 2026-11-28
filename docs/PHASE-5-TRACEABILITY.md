# DiceUp Phase 5 — Traceability

**Phase:** 5 — Online Multiplayer Gameplay (Stage 9, documentation)
**Branch:** `feature/online-phase-5-gameplay`, HEAD `5d47cf7` (Stage 8)
**Base:** `implementation/foundation-phase-2-3` tip `ba0d37c`
**Sources:** SRS v0.1 (Draft), SDD v1.0 (Draft), `docs/PHASE-5-ASSESSMENT.md`,
`docs/PHASE-5-PLAN.md`, the staged tree itself.

Every link below was verified against the staged tree in Stage 9 by reading
the code — not copied blindly from the assessment. Where the assessment and
the tree disagree, the tree wins and the difference is called out. Test
counts are the Stage 8 coordinator-measured numbers unless stated otherwise;
per-requirement test links name suites, not invented per-case counts.

> This is the **Phase 5** traceability record. Do not confuse it with the
> M4.1 remediation batch's `docs/TRACEABILITY.md` (different file, different
> scope, still unpushed staging work — see the M4.1 boundary note at the end).

## 1. Stage 2 requirements (FR-42–FR-59)

Stage 2 = FR-42–FR-59 (online multiplayer). Stage 3 = FR-60–69 (social),
FR-70–82 (admin) — out of Phase 5 scope unless commissioned (see §2).

| Req | Requirement (short) | Implementation | Tests |
|---|---|---|---|
| FR-42 | Online only for authenticated players; guests prompted; offline unaffected | Global `JwtAuthGuard` on all game routes; Flutter guest prompt in `diceup_app/lib/presentation/screens/home_screen.dart` (`_showOnlinePrompt`, UI-01) and `mode_selection_screen.dart` (`goOnline`) | `diceup_app/test/online/mode_selection_online_test.dart`; backend authz coverage in `backend/test/integration/rooms.e2e.spec.ts` |
| FR-02/03/04/05/06 | Registration, verification, login, logout, recovery | Backend: Phase 4, unchanged (`backend/src/auth/`). Flutter (new): `diceup_app/lib/data/online/auth_api_client.dart`, `auth_service.dart`, `auth_models.dart`, `token_storage.dart`; screens `diceup_app/lib/presentation/screens/auth/` (login, register, forgot_password, verify_email, account) | `diceup_app/test/online/auth_api_client_test.dart`, `auth_service_test.dart`, `auth_notifier_test.dart`, `auth_screens_test.dart`, `live_auth_test.dart` (live backend) |
| FR-07/08 | Profile, password change, preferences | Backend: Phase 4, unchanged (`backend/src/users/`). Flutter: `account_screen.dart` | `auth_screens_test.dart`, `live_auth_test.dart` |
| FR-09 | Session persists; tokens only in secure storage | `diceup_app/lib/data/online/token_storage.dart` (`flutter_secure_storage`); session restore at launch in `home_screen.dart`; silent refresh in `auth_service.dart`. Tokens are never written to SQLite | `auth_service_test.dart`, `live_auth_test.dart` |
| FR-10 | Account deletion | **Not built beyond Phase 4** — request marker + session revoke only; anonymisation awaits OD-08 (Stage 3 scope). No Phase 5 change | — (Phase 4 coverage only) |
| FR-43 | Create room (limit 2–4, unique code, host) | `backend/src/rooms/rooms.service.ts` + `rooms.controller.ts` (`POST /v1/rooms`); `CreateRoomDto` carries **only** `maxPlayers` (2–4) — no rule options (OD-11, §2). Code: `backend/src/rooms/room-code.ts` (6-char uppercase alphanumerics, confusables excluded). Table `rooms` (migration 0003) | `backend/test/unit/rooms.service.spec.ts`, `room-code.spec.ts`, `rooms-dto-validation.spec.ts`; `backend/test/integration/rooms.e2e.spec.ts` |
| FR-44 | Join by code (open, not full, specific errors) | `POST /v1/rooms/join` + `room:join` socket event; errors `ROOM_NOT_FOUND` / `ROOM_FULL` / `ROOM_STARTED` (`backend/src/common/errors/error-codes.ts`) | `rooms.e2e.spec.ts`, `backend/test/integration/rooms-socket.e2e.spec.ts` |
| FR-45 | Matchmaking queue + auto-grouping | `backend/src/matchmaking/matchmaking.service.ts` + `matchmaking.controller.ts` (`POST /v1/matchmaking/join|leave`, `GET /v1/matchmaking/status`); Redis sorted set `matchmaking:queue`, score = enqueue time; group size 4 (`MATCHMAKING_GROUP_SIZE = 4` — SDD default; see C-13 note in §5). Match found → `matchmaking:matched { roomId, roomCode }` per player (`backend/src/rooms/room-broadcaster.ts`) | `backend/test/unit/matchmaking.service.spec.ts`; `backend/test/integration/matchmaking.e2e.spec.ts` |
| FR-46 | Readiness per member, shown to all | `room:ready { roomId, ready }` → `room:updated { room, members[], ready{} }` broadcast (`backend/src/socket/game.gateway.ts`, `room-broadcaster.ts`) | `rooms-socket.e2e.spec.ts` |
| FR-47 | Start: host + ≥ 2 present + all ready | `match:start { roomId }` (host only — `NOT_ROOM_HOST` otherwise); seat assignment in join order (SDD DA-03, proposed); match creation in `backend/src/match/match.service.ts` | `rooms-socket.e2e.spec.ts`, `backend/test/integration/gameplay.e2e.spec.ts` |
| FR-48 | Invite friend to room | **Room-code sharing only (Phase 5 minimum).** Lobby copy/share: `diceup_app/lib/presentation/screens/online/online_lobby_screen.dart` (clipboard copy + `share_plus` share of `service.inviteFriend(user.id)`, which carries the room code). Friend-graph invites (FR-60–62) are Stage 3 — **not built**; `invitation:received` is not emitted anywhere in the tree (verified by grep in Stage 9) | `diceup_app/test/online/rooms_widget_test.dart` |
| FR-49 | Server generates all dice | TS engine `backend/src/game/ludo-game.ts` + `dice-roller.ts` (cryptographically secure RNG, no modulo bias); `dice:roll { matchId, requestId }` carries **no value** — a client-supplied value is ignored | `backend/test/unit/engine.spec.ts`; `gameplay.e2e.spec.ts`; parity spec (§4) |
| FR-50 | Server verifies turn/roll/move legality; reject with code, state unchanged | Engine validation in `ludo-game.ts`; per-match Redis lock (`match:lock:{matchId}`) in `match.service.ts`; rejections as `action:rejected { matchId, requestId?, code, message }` | `engine.spec.ts`, `backend/test/unit/match.service.spec.ts`, `gameplay.e2e.spec.ts` |
| FR-51 | Broadcasts in order with increasing `seq` | Every server game event carries `seq` (except `action:rejected`, which echoes `requestId`); client `OrderedEventBuffer` (`diceup_app/lib/data/online/game_socket_client.dart`) applies in order, ignores stale, requests a snapshot on a gap | `diceup_app/test/online/ordered_event_buffer_test.dart`, `game_socket_client_test.dart`, `gameplay.e2e.spec.ts` |
| FR-52 | Turn timer 30 s; expiry auto-roll + legal move or skip | Server-side timers in `match.service.ts` (`turn_ends_at` + `turn_epoch`, migration 0004); auto-play = first legal move in engine order (SDD DA-04, proposed); each expiry counts as a missed turn | `backend/test/unit/match-timers.spec.ts`; `backend/test/integration/recovery-timers.e2e.spec.ts` |
| FR-53 | At-most-once; dedupe / stale rejection | `requestId` UUID on every mutating client intent; `UNIQUE (match_id, request_id) WHERE request_id IS NOT NULL` on `move_events` (migration 0003); duplicate returns the original result; stale requests rejected (`STALE_STATE`) | `match.service.spec.ts`, `gameplay.e2e.spec.ts` |
| FR-54/55/56 | Disconnect detection, grace 60 s, reconnect, forfeit | Presence `presence:user:{userId}` TTL 30 s, refreshed on heartbeat (`match.service.ts`); disconnect → `player:disconnected { graceEndsAt }`, 60 s grace; reconnect (same account, any socket) → full `match:state`; grace expiry / 3 missed turns / voluntary leave → forfeit per BR-15 (`player:forfeited`, tokens removed, recorded as loss) | `recovery-timers.e2e.spec.ts`; `backend/test/unit/match-timers.spec.ts` |
| FR-57 | Single authoritative state; resend on request | `state:request { matchId, lastSeq }` → `match:state { matchId, snapshot, seq }` (full snapshot, replaces the client mirror wholesale); state checkpointed to PostgreSQL after every accepted transition (the `move_events` row *is* the checkpoint; replay via `backend/src/match/match-replay.ts`) | `backend/test/unit/match-replay.spec.ts`; `gameplay.e2e.spec.ts`, `recovery-timers.e2e.spec.ts` |
| FR-58 | Atomic persist of result + participants + ruleset + move log | One transaction in `match.service.ts` (`dataSource.transaction`, match end persists result + participants + ruleset version + ordered move log); no edit path exists for a result (BR-17, NFR-31) | `match.service.spec.ts`, `gameplay.e2e.spec.ts` |
| FR-59 | Leave before start; host transfer / close if empty | `room:leave` + `POST /v1/rooms/:id/leave`; host transfer to longest-present member; room closes when empty; 10-min empty-room sweeper (`backend/src/rooms/rooms-cleanup.service.ts`) | `rooms.e2e.spec.ts`, `rooms-socket.e2e.spec.ts` |

### FR-60–FR-69, FR-70–FR-82 — explicitly not built (Stage 3)

| Req | Status |
|---|---|
| FR-60/61/62 friends, friend list, invitations | **Not built.** No friends module, no friends routes, no `invitation:received` emission. Room-code sharing (FR-48) is the Phase 5 minimum. |
| FR-64/65/66/67 online history, statistics, leaderboard, ranking | **Not built.** FR-58 records results; no ranking runs (OD-06 open, DA-08 proposed, D-08 forbids hard-coding it). The results screen shows an online result label (`modeOnline`, no Play Again for online matches) but there is no segmented Local/Online history or statistics view. |
| FR-68 notifications / FR-79 game config | **Not built.** No push/email provider; no admin config UI. Timer values are seeded (see §2, timers decision). |
| FR-70–FR-82 admin | **Not built.** No admin routes in Phase 5. |

## 2. Scoping decisions (assessment §11 / §10)

| Decision | Resolution (as built) | Where it is implemented / recorded |
|---|---|---|
| **OD-05 — matchmaking in** | Matchmaking is **in** Stage 2 scope. | `backend/src/matchmaking/` (service, controller, module); `POST /v1/matchmaking/join|leave`, `GET /v1/matchmaking/status`; `diceup_app/lib/presentation/screens/online/matchmaking_screen.dart`; `matchmaking.e2e.spec.ts` |
| **Room-code invites in, friend-graph out** | Room-code sharing is the minimum; friend-graph invites are Stage 3 and out. | Lobby copy/share in `online_lobby_screen.dart`; `GameRoomService.inviteFriend` (`diceup_app/lib/data/online/game_room_service.dart`) carries the room code only. No friends module exists; `invitation:received` is not emitted (verified Stage 9). |
| **History / stats / ranking out** | FR-64–67 out of scope; FR-58 records results only. | No leaderboard/rankings tables or routes; `matches.status` has no ranking side-effects; results screen online label only (`results_screen.dart`). |
| **OD-11 — frozen ruleset** | Host selects **only** the player limit (2–4). The ruleset is the frozen `RULESET_VERSION=1.0.0`, stored per room and per match. | `CreateRoomDto` has only `maxPlayers` (`backend/src/rooms/dto/rooms.dto.ts`); `RULESET_VERSION` pinned in `backend/src/config/config.validation.ts` + `configuration.ts`; `rooms.ruleset_version`, `matches.ruleset_version` (migration 0003). |
| **Timers seeded 30/60/3** | Turn timer 30 s, grace 60 s, missed-turn limit 3 — seeded from the `game_configurations` row; no admin writer exists (FR-79 is Stage 3). | `backend/src/rooms/entities/game-configuration.entity.ts` (`turnTimerSeconds` default 30, `gracePeriodSeconds` default 60, `missedTurnLimit` default 3, `maxRoomPlayers` default 4); consumed in `rooms.service.ts` / `match.service.ts`. |
| **C-12 — flagged match unimplementable** | Recorded as unimplementable as written: `matches.status` is only `in_progress/completed/cancelled` — there is no flagged/error state. UC-09 E2 has no designed state. | Migration 0003 `CHK_matches_status`; no flagged status anywhere in `backend/src/match/` or the match entity. |

## 3. Migrations 0001–0004

| Migration | Contents |
|---|---|
| `0001_init-auth` | Phase 4: `users`, `profiles`, `auth_sessions`, `email_tokens`. Unchanged by Phase 5. |
| `0002_add-profile-preferences` | Phase 4: profile preferences. Unchanged by Phase 5. |
| `0003_rooms-matchmaking` | Phase 5, Stage 3: `rooms` (incl. `CHK_rooms_max_players` 2–4, `CHK_rooms_status` open/playing/closed, `CHK_rooms_source` manual/matchmaking, partial unique index `UQ_rooms_code_open` on `code WHERE status='open'`, `IDX_rooms_host_status`), `room_members` (PK `(room_id, user_id)`), `matches` (incl. `CHK_matches_status` in_progress/completed/cancelled, `UQ_matches_room` — 1 room → 0..1 match, `IDX_matches_winner_ended`), `match_players` (PK `(match_id, user_id)`, seat 0–3, result win/loss/forfeit, `IDX_match_players_user_match`), `move_events` (type check incl. `dice_rolled/token_moved/turn_changed/player_forfeited/match_started/match_ended`, `UQ_move_events_match_seq`, partial unique `UQ_move_events_match_request` on `(match_id, request_id)`), `game_configurations` (version unique). |
| `0004_stage6_timers_presence` | Phase 5, Stage 6: `matches.turn_ends_at` (timestamptz) + `matches.turn_epoch` (int, default 0); `match_players.disconnected_at` + `match_players.grace_ends_at` (timestamptz). Down migration drops all four columns. |

Live DB at Stage 8: `diceup_test_stage5_live_f8dcc36b443c`, 4 migrations applied.

## 4. REST endpoints (new in Phase 5)

Base `/v1`, envelope `{ success, data | error{code, message, details, correlationId} }`,
`X-Request-Id` on every response. All Phase 5 routes require an authenticated,
email-verified player (global `JwtAuthGuard` + `AccountStatusGuard` +
`EmailVerifiedGuard` + `@Roles('player')`) unless noted; all authenticated
REST is additionally rate-limited at 100/min per user.

| Method + endpoint | Purpose | Implementation |
|---|---|---|
| `POST /v1/rooms` | Create room (FR-43). Body `{ maxPlayers: 2–4 }`. 201 + room + 6-char code | `rooms.controller.ts`, `rooms.service.ts` |
| `POST /v1/rooms/join` | Join by code (FR-44). Body `{ code }` (case-insensitive). Errors `ROOM_NOT_FOUND` / `ROOM_FULL` / `ROOM_STARTED` / `ALREADY_IN_ROOM` | `rooms.controller.ts` |
| `GET /v1/rooms/:id` | Room detail (members + readiness) | `rooms.controller.ts` |
| `POST /v1/rooms/:id/leave` | Leave before start (FR-59); host transfer / close-if-empty | `rooms.controller.ts` |
| `POST /v1/matchmaking/join` | Enter the queue (FR-45). Errors `ALREADY_IN_MATCHMAKING` / `ALREADY_IN_ROOM` / `ALREADY_IN_MATCH` | `matchmaking.controller.ts` |
| `POST /v1/matchmaking/leave` | Leave the queue. Error `NOT_IN_MATCHMAKING` | `matchmaking.controller.ts` |
| `GET /v1/matchmaking/status` | Queue status `{ status, queueSize, groupSize: 4 }` | `matchmaking.controller.ts` |
| `GET /v1/matches/active` | The caller's active (in-progress) match, if any — "return to active match" (UC-07 E2 read path) | `matches.controller.ts` |
| `GET /v1/matches/:id` | Match detail | `matches.controller.ts` |
| `GET /v1/matches/:id/state` | Current authoritative snapshot (REST form of `match:state`) | `matches.controller.ts` |
| `GET /v1/matches/:id/events` | Ordered move log (`move_events`, by `seq_no`) | `matches.controller.ts` |

Phase 4 endpoints (health ×2, auth ×8, users ×6) are unchanged; see
`backend/docs/06-rest-api.md`.

## 5. Socket.IO events (namespace `/game`)

Full contract — payload shapes, error codes, and the reconnect/recovery
contract — is documented in `backend/docs/11-phase5-online-api.md`.
Summary (verified against `backend/src/socket/socket.constants.ts` and
`game.gateway.ts`):

**Client → server:** `ping`, `room:join { roomCode }`, `room:leave { roomId }`,
`room:ready { roomId, ready }`, `match:start { roomId }`,
`dice:roll { matchId, requestId }` (no value), `token:move { matchId, tokenId, requestId }`,
`state:request { matchId, lastSeq }`.

**Server → client:** `connected`, `pong`, `exception`, `room:updated`,
`match:started`, `matchmaking:matched`, `dice:rolled`, `token:moved`,
`turn:changed`, `match:state`, `match:ended`, `action:rejected`,
`player:disconnected`, `player:reconnected`, `player:forfeited`.

**Discipline:** every server game event carries an increasing `seq` (FR-51)
except `action:rejected`, which echoes the intent's `requestId`; every
client mutating intent carries a client-generated UUID `requestId` (FR-53).
Clients apply broadcasts in `seq` order and request a snapshot on a gap.
**Not built:** `invitation:received` (Stage 3, FR-62) — no emission exists.

## 6. Rate limits

| Limit | Value | Where |
|---|---|---|
| Authenticated REST | 100/min per user | Phase 4 global guard (unchanged) |
| L-01 — global per-IP limit for unauthenticated requests to protected routes (health exempt) | Per-IP flood limit, fail-open on Redis error with a logged warning (see note in §7) | `backend/src/common/rate-limit/unauthenticated-rate-limit.middleware.ts`; `backend/test/unit/unauthenticated-rate-limit.middleware.spec.ts` |
| L-02 — socket **connection** rate limit | 120/min per IP, 20/min per user, 60 s window; in-process fallback when Redis is down | `backend/src/socket/socket-connection-rate-limit.service.ts`, `socket.constants.ts` (`SOCKET_CONNECTIONS_PER_MINUTE_PER_IP/USER`); `socket-connection-rate-limit.spec.ts` |
| Socket events | 20 events/s per socket; 5 violations → disconnect | `socket-rate-limit.service.ts`, `ws-rate-limit.guard.ts`; `socket-rate-limit.spec.ts` |
| Socket payload | 10 KB per event (raw payload, before whitelist strip) | `ws-validation.pipe.ts` |
| Login throttle | 5 failures / 15 min per account **and** per IP (Phase 4, unchanged) | `backend/src/auth/` |

## 7. Known limitations (as built — not defects to fix in Phase 5)

1. **Login-burst Argon2id cost under concurrency.** Under a burst of
   concurrent logins the Argon2id verification cost (64 MiB/3/1) dominates
   latency. This is a VM-capacity observation from the Stage 8 load harness,
   **not a defect and not in scope to fix** in Phase 5. The load harness
   seeds pre-hashed users and stays under the connection limits
   (`CONNECT_WAVE = 100`, under the 120/min/IP product limit) for this reason.
2. **Presence caveat.** Presence is a 30 s TTL key refreshed on heartbeat;
   a connected-but-idle client is therefore marked DISCONNECTED after ~30 s
   without a heartbeat. Grace (60 s) protects the player: reconnecting inside
   grace restores the match with full state. (See `match.service.ts`:
   "within its 30 s TTL … marked DISCONNECTED … socket is caught at most
   ~30 s after its last heartbeat".)
3. **Load-harness run-id prefix wart.** The seed lookup uses
   `LIKE 'load_<run-id>_%'`, so a run-id that is a prefix of an earlier
   run-id collides with the earlier run's users. Workaround (documented in
   `backend/test/load/README.md`): use a fresh `--run-id` (or none) for
   repeat ramp runs. Recorded in commit `5d47cf7`.
4. **`onlineMatchStarted` unused l10n key.** The string exists in
   `diceup_app/lib/l10n/app_en.arb` (+ generated localizations) but is
   referenced by no screen. Dead string; removal is a follow-up, not a
   Stage 9 code change.
5. **NFR-12 blocked on M4.1.** The 1,000-match AI sim is blocked on OD-M4-01
   (M4.1 scope: AI-only sim vs BR-01 "≥ 1 human" per match). Only affects TS
   conformance sim construction; no sim was built in Phase 5.
6. **L-01 fail-open on Redis error.** The unauthenticated per-IP middleware
   *allows* the request (and logs) when Redis is unavailable, so the limit
   degrades rather than failing closed. This is a deliberate, logged
   trade-off in the middleware (availability over strictness when the
   limiter itself is down); the auth endpoints' own fail-closed limits
   still apply downstream. Recorded here so the choice is visible.
7. **Deep links not built.** `go_router` was not adopted; the app uses
   built-in named routes. An invitation link does not deep-link into the
   lobby — the lobby accepts an optional room id and the code can be
   pasted/shared (`app_routes.dart` comment: "go_router stays out of this
   stage"). Invitation deep-linking needs a follow-up decision.
8. **No CI.** No `.github/workflows/` exists (Workflows permission 403), so
   no CI runs exist for any branch, including this one. All verification in
   Phase 5 is local. The vectors CI job is staged locally, unpushed.
9. **Test-only credentials in the tree.** The committed test files contain
   passwords for throwaway local accounts only: `LivePass!1` (live-test
   accounts `live3-*@example.com` on the local scratch DB,
   `diceup_app/test/online/live_game_test.dart`), `LoadPass!1` (load-harness
   seed users, `backend/test/load/load-test.js`), and the fake
   `CorrectHorse!9` (mocked API-client tests). None is a production
   credential; no real secret is committed. `backend/.env` and
   `backend/.keys/` remain untracked and git-ignored (verified Stage 9).
10. **Matchmaking has no criteria.** Grouping is arrival order only
    (SDD §5.2.4); no skill/rank/region/wait-time criteria, no maximum wait,
    no partial-group start rule (assessment G-2/G-6). Group size is 4
    (SDD default; a brief assuming 2-player groups contradicts it — C-13).
11. **No flagged-match state (C-12).** See §2. A match that needs human
    review has no designed status; it can only be in_progress, completed,
    or cancelled.

## 8. UI requirements (online halves)

| Req | Online half | Status |
|---|---|---|
| UI-01 | Home "Play Online" entry; guests get the login prompt | Built — `home_screen.dart` (`_showOnlinePrompt`), session restore at launch |
| UI-03 | Online game screen (one screen, server snapshots, connection + timer + grace UI, `action:rejected` surfaced without changing local state) | Built — `diceup_app/lib/presentation/screens/online/online_game_screen.dart`, `OnlineGameController` in `app_providers.dart`, `online_connection_banner.dart` |
| UI-05 | Auth screens (login / register / forgot / verify / account) | Built — `diceup_app/lib/presentation/screens/auth/` |
| UI-07 | Rooms / lobby / matchmaking (create + code copy/share, join by code, member list + ready toggles, host Start gated on FR-47, Leave) | Built — `online_lobby_screen.dart`, `matchmaking_screen.dart`, `game_room_service.dart` |
| UI-09 | History / statistics, segmented Local/Online | **Online half not built (Stage 3, FR-64–66).** Only the results screen's online label (no Play Again for online matches) exists. Local screens stay SQLite-only. |

## 9. Engine parity (NFR-39, D-20)

- The Dart engine wins on any conflict (D-20): 51+4+1 home path, release to
  step 1, BR-11 (not BR-25) for winning, three-phase turn machine
  (`awaitingRoll` / `awaitingMove` / `finished`). The TypeScript engine
  (`backend/src/game/`) mirrors the Dart engine, not the SDD pseudocode.
- Shared vectors: `diceup_app/test/vectors/rules.json`, **39 cases**
  (extended from 23 in Stage 4 with the assessment §8 gap cases).
- Stage 8 measured: TS parity spec 42 (39 cases + 3 meta); Dart vector
  suite 41 (39 + 2). The Dart offline engine was not modified to make the
  TS engine pass.

## 10. M4.1 boundary (do not cross)

Phase 5's base `ba0d37c` does **not** contain the M4.1 remediation batch.
Stage 9 verified (diff `367f573..HEAD`, the local base commit standing in
for `ba0d37c` — see `docs/PHASE-5-PLAN.md` §5): **none** of the files the
M4.1 batch also touches — `diceup_app/lib/domain/engine/ludo_game.dart`,
`settings_screen.dart`, `docs/IMPLEMENTATION-PLAN.md`, `docs/TRACEABILITY.md`,
`docs/ruleset.md` — appears in the Phase 5 diff. The only `ruleset` match in
the diff is the new Phase 5 TypeScript file `backend/src/game/ruleset-config.ts`,
which is not an M4.1 file. No M4.1 overlap was introduced by Stage 9 either
(this doc is `docs/PHASE-5-TRACEABILITY.md`, a different file from
`docs/TRACEABILITY.md`).
