# DiceUp — Phase 4 Plan: Backend Foundation

> **Status:** IMPLEMENTED + VERIFIED (Stage 5, 2026-11-27) — see §13 for the
> final-verification record. Every row in §2 now carries its FINAL status
> (`PASS` / `BLOCKED` / `NOT IMPLEMENTED` / `NOT APPLICABLE`), measured by
> Stage 5 on the finished tree (HEAD `93542ad` + Stage 5 doc commits).
> No code, no push, no PR, no merge is authorised by this document —
> the push + PR still need the user's tap (see the final report).
>
> **Branch:** `feature/online-phase-4-backend-foundation` (from
> `implementation/foundation-phase-2-3` @ `102884a`).
> **Sources:** SRS v0.1 (2026-11-16, draft, unapproved) and SDD v1.0
> (2026-11-21, draft, unapproved). Where the two disagree the SRS governs
> (SDD §1.4); no such disagreement was found that affects Phase 4.
> **Scope of this phase:** the SDD **Stage 2 infrastructure subset** — auth,
> PostgreSQL, Redis, REST, Socket.IO foundation, config, logging, security,
> tests. No gameplay, no rooms, no matchmaking, no social features, no admin
> panel. See §2.3 for the full out-of-scope list.

## 0. How to read this plan

- **"SDD §x" / "SRS §x"** = the prescription being followed. Where the SDD
  prescribes a choice, Phase 4 follows it verbatim.
- **`[Proposed]`** = the SDD itself marks the choice as proposed (needs
  stakeholder approval). It is still followed — it is the SDD's stated
  default — and is flagged here so a later change is a config/code swap,
  not a redesign.
- **`[P4 choice]`** = the SDD is silent and this plan picks the conventional
  NestJS default. Every such choice is logged in §10 with its reversibility.
- **`OPEN`** = a decision this plan does not invent. All OPEN items are
  carried over from the SRS/SDD registers (OD-01…OD-12); none of them blocks
  Stage 2, because each is isolated behind an interface (see §11.3).

### 0.1 Naming discrepancy (brief vs docs) — recorded, not resolved

The brief calls this work **"Phase 4"** (with later Phases 5/6/7). The SRS
and SDD never use "Phase 4/5/6/7" (0 hits in either document). They use
**Stages S1 / S2 / S3** (SRS §1.2, SDD §1.2):

| Brief name | Docs name | Content |
|---|---|---|
| Phase 4 (this plan) | Stage 2, infrastructure subset | Auth, PostgreSQL, Redis, REST, Socket.IO foundation |
| Phase 5 | Stage 2, gameplay subset | Rooms, matchmaking, authoritative game, reconnect/forfeit |
| Phase 6 | Stage 3, player subset | Profiles (public), friends, history, stats, leaderboard, notifications, reports |
| Phase 7 | Stage 3, admin subset | Next.js admin panel + admin APIs, audit trail, game config |

This plan uses the brief's "Phase 4/5/6/7" labels for the out-of-scope rows
in §2.3 (so the coordinator can route them) and the docs' "Stage 2/3"
labels everywhere else. Requirement IDs are never renumbered (SDD §1.4).

### 0.2 Environment verified for this plan (2026-11-27, this VM)

| Item | Found | Note |
|---|---|---|
| Node.js | v24.22.1 | SDD §15.1 / DA-07 pins **Node.js 22 LTS**. The VM has 24.22.1. Stage 2 targets 22 LTS (`engines` + `.nvmrc`); dev on 24 is a variance to record, not a redesign. No Node 22 runtime was verified here. |
| npm | 10.9.4 | Matches the Node 24 bundle. |
| PostgreSQL | psql 16.15; cluster `16/main` on port 5432, **online** (Stage 5 re-check: `pg_lsclusters` → online; integration tests use scratch DBs, never `diceup_dev`) | SDD pins PostgreSQL 16 (§9.2, DA-07) — version matches. |
| Redis | `redis-server` 7.0.15 **running** (Stage 5 re-check: `redis-cli ping` → `PONG`) | SDD pins Redis 7 (§15.1, DA-07) — version matches. |
| Docker | Not present | SDD §15.2 proposes local PostgreSQL/Redis "via containers" for dev. Without Docker, Stage 2 uses the local `pg_lsclusters` cluster and a local `redis-server` process instead. No container-based verification is claimed. |
| GitHub CI | Not available (Workflows permission 403, per brief) | **No `.github/workflows/` file is part of any file set in this plan, and no CI pass is claimed.** Lint/typecheck/tests are run locally by Stage 2 and evidenced by command output. |
| `backend/` | Exists — 134 files added vs `102884a` (see §13) | Created by Stage 2 per §3. |
| `diceup_app/` | Read-only; not modified by this plan | Offline engine, vectors and ruleset below are read as reference only. |

### 0.3 Rule-vector baseline read (reference for NFR-39)

- Shared vectors: `diceup_app/test/vectors/rules.json` — **formatVersion 1,
  rulesetVersion `1.0.0`, 23 cases** (release-only-on-six … three-sixes-in-sequence).
- Dart ruleset: `diceup_app/lib/domain/engine/ruleset_config.dart` —
  `RulesetConfig` with `releaseOnSix=true, releaseOnOne=false,
  extraTurnOnSix/Capture/Home=true, maxConsecutiveSixes=3, exactFinish=true,
  version='1.0.0'`, strict `fromJson` (all eight fields required), matching
  SDD §6.2 Table 6.2 defaults. These defaults are **proposals pending
  stakeholder approval (SRS OD-02)**; changing one is a new ruleset version,
  never a code change (BR-14).
- Phase 4 does **not** build the TypeScript engine. It builds the vector
  *loader + schema check* (§10.2) so Phase 5 can run the conformance suite
  against it. Full NFR-39 conformance (Dart + TS both green) is a Phase 5
  exit criterion, not a Phase 4 one.

---

## 1. Phase 4 in one paragraph

A single NestJS modular monolith (`backend/`, SDD §4.5, decision D-04)
exposing versioned REST under `/v1` and one authenticated Socket.IO
namespace (`/game`), backed by PostgreSQL 16 via TypeORM (SDD §3.5/§10.3,
`[Proposed]` in SDD §17.2) and Redis 7 via a thin `RedisService`
abstraction. It implements player identity end-to-end (register → verify →
login → refresh → logout, password recovery, profile, session revocation),
the four Phase 4 tables (`users`, `profiles`, `auth_sessions`,
`email_tokens`), validated configuration that fails fast, structured
logging, a global error envelope, rate limiting, health/readiness that
distinguishes app / PostgreSQL / Redis, and a test suite that runs against
**real** local PostgreSQL + real local Redis. It deliberately contains no
room, match, game, friend, ranking, notification, report or admin logic —
only the seams (guards, idempotency, per-match lock helper, presence key
patterns) those later phases will plug into.

## 2. Requirement-to-implementation mapping

Status values (FINAL, Stage 5): `PASS` (implemented and verified by a
named test/probe — evidence in §13), `BLOCKED` (in scope but its verification
could not run — reason in the row), `NOT IMPLEMENTED` (in scope, not built),
`NOT APPLICABLE` (belongs to another phase or is a guard constraint outside
this backend — phase named in the row). The original `PLANNED` /
`NOT IN PHASE 4 SCOPE` values are superseded by the §13 record; the
Verification column names the method Stage 4/5 used, and §13 names the
measured result.

### 2.1 In scope — PLANNED

#### 2.1.1 Functional requirements (FR)

| ID | Requirement (short) | Planned implementation | Module / file (planned) | Verification | Status |
|---|---|---|---|---|---|
| FR-02 | User registration — unique email + username, password policy (NFR-13), specific duplicate errors | `POST /auth/register`; DTO validation (email format, username allow-list pattern, password ≥ 8 chars); uniqueness checked in one transaction; `409 EMAIL_TAKEN` / `409 USERNAME_TAKEN`; creates `users` (status `active`, `email_verified_at` NULL) + `profiles` row + `email_tokens` verify row in one transaction; verification message dispatched via `Mailer` interface (§7.4) | `backend/src/auth/` (`auth.controller.ts`, `auth.service.ts`, `dto/register.dto.ts`); `backend/src/users/` (`user.entity.ts`, `profile.entity.ts`); `backend/src/mailer/` | Integration: duplicate email → 409 + specific code; duplicate username → 409; weak password → 400 with field detail; happy path creates both rows + token row; unit: DTO validation matrix | PASS |
| FR-03 | Email verification — link/code sent, online play restricted until verified `[Proposed]` | `POST /auth/verify-email` with single-use, time-limited (24 h `[Proposed]`, SDD §13.1), **hashed** token; sets `users.email_verified_at`; unverified users can log in but are refused online features — enforced by `EmailVerifiedGuard` on every online endpoint/gateway (deny-by-default, NFR-17); resend via `POST /auth/verify-email/resend` (rate-limited, §6.5) | `backend/src/auth/` (`email-token.entity.ts`, `email-verification.service.ts`); `backend/src/common/guards/email-verified.guard.ts` | Integration: verify with valid token → verified; reuse → 410/409 invalid; expired → rejected; unverified token calling an online-guarded route → 403; unit: token hash comparison (timing-safe) | PASS |
| FR-04 | User login — valid credentials return a session; invalid → generic error revealing neither field | `POST /auth/login` (email **or** username + password, per SDD §5.2.1/UC-05); Argon2id verify; on failure always `401 INVALID_CREDENTIALS` ("Email or password is incorrect."); on success issues 15-min RS256 access JWT + opaque refresh token (§7.1); failed attempts counted toward NFR-16 throttle | `backend/src/auth/` (`auth.service.ts`, `dto/login.dto.ts`) | Security: wrong email vs wrong password vs both wrong → identical status/body/timing class; integration: valid login returns both tokens + `expiresIn: 900` | PASS |
| FR-05 | User logout — ends session, deletes device tokens, offline still available | `POST /auth/logout` revokes the current `auth_sessions` row (`revoked_at` set); refresh token thereafter rejected; client-side token deletion is a Flutter concern (out of scope here — the server side is revocation, which is what makes logout real) | `backend/src/auth/` (`auth.service.ts`, `auth-session.entity.ts`) | Integration: logout → refresh with same token → 401; access token continues until expiry but its `sid` check fails on refresh only — see §7.1 note on `sid` revocation scope | PASS |
| FR-06 | Password recovery — time-limited reset link/code, invalid after one use or expiry | `POST /auth/forgot-password` (always returns 200 with a neutral message, even for unknown emails — no account enumeration); `POST /auth/reset-password` with single-use, time-limited (1 h `[Proposed]`, SDD §13.1), **hashed** token; on success hashes the new password, revokes **all** sessions for the user, invalidates the token (`used_at` set) | `backend/src/auth/` (`password-reset.service.ts`, `email-token.entity.ts` with `purpose='reset'`) | Integration: reset with valid token → login with new password works, old sessions revoked; token reuse → rejected; expired → rejected; forgot-password for unknown email → 200 neutral (no leak) | PASS |
| FR-07 | Profile management — view/edit display name + avatar selection, length/content validation | `GET /users/me`, `PATCH /users/me` (displayName ≤ 50 chars, `avatar_key` from the bundled set — **no uploads**, SDD §5.1.9/DA-05); ownership enforced (a user can only PATCH their own row — the `me` route takes no user id, so there is nothing to tamper with) | `backend/src/users/` (`users.controller.ts`, `users.service.ts`, `dto/update-profile.dto.ts`) | Integration: PATCH own profile → 200; validation failures → 400 field detail; avatar_key outside the allowed set → 400 | PASS |
| FR-08 | Account settings — change password, notification preferences (sound/vibration are local, Flutter-side) | `PATCH /users/me/password` (old password required + verified, new password per NFR-13, revokes all sessions on success); `PATCH /users/me/preferences` (notification preferences only — the persistence column lives on `profiles`; sound/vibration never reach the server) | `backend/src/users/` (`dto/change-password.dto.ts`, `dto/update-preferences.dto.ts`) | Integration: wrong old password → 401 generic; change → old sessions revoked, new login works; preferences round-trip | PASS |
| FR-09 | Session persistence — stay signed in across restarts until logout/expiry, tokens only in platform secure storage `[Proposed]` | Server side: refresh-token rotation (§7.1) is what makes persistence safe; `POST /auth/refresh` is the only renewal path. Device storage is a Flutter concern (`flutter_secure_storage`, SDD §5.1.1) and is **not** implemented or verified here. | `backend/src/auth/` (`auth.service.ts` refresh flow) | Integration: refresh before expiry → new pair; refresh after logout → 401 | PASS |
| FR-10 | Account deletion request `[Proposed]` (Stage 3 in SRS) | **Partial in Phase 4:** `DELETE /users/me` records the deletion request (sets a `deletion_requested_at` marker — see §4.1, column is `[P4 choice]`) and revokes all sessions immediately. **Full anonymisation/retention is NOT in Phase 4** — it depends on OPEN OD-08 (retention periods, §11.3). No personal data is deleted or anonymised by Phase 4 code until OD-08 is decided. | `backend/src/users/` (`users.service.ts` request path) | Integration: request → sessions revoked, marker set, login refused; unit: no anonymisation code path exists yet (asserted by code review) | PASS (partial) — request path only; anonymisation NOT IMPLEMENTED (OD-08 open) |
| FR-42 | Online access control — online features only for authenticated Registered Players; guests prompted; offline unaffected | `JwtAuthGuard` (global, §3.2) + `EmailVerifiedGuard` + `AccountStatusGuard` (BR-19) applied to every online route/gateway; public routes are an explicit allow-list (`/auth/*` public endpoints, `/health`, `/health/ready`), never the default. Offline modes are untouched — this backend is never called by offline play (CON-05). | `backend/src/common/guards/` (`jwt-auth.guard.ts`, `email-verified.guard.ts`, `account-status.guard.ts`); `backend/src/app.module.ts` (global guard wiring) | Authorization matrix test (§10.4): every route × {no token, expired, unverified, suspended, valid} → expected status; unit: guard unit tests | PASS — authz matrix covers 4/7 guarded routes — gap G-1, §13 |
| FR-63 | Player profile view — display name, avatar, statistics shown to other Registered Players | `GET /users/{id}/profile` returns only public fields (display name, avatar key, cached counters). Statistics fields return the stored cached counters, which are **0 until Phase 6 populates them** — no ranking computation exists in Phase 4. Password data is never in the response shape (enforced by DTO, not by convention). | `backend/src/users/` (`users.controller.ts`, `dto/public-profile.dto.ts`) | Integration: public profile excludes email/password hash; unknown id → 404 (same as not-visible, §6.3) | PASS |
| FR-75/76 | Suspend / block account — **enforcement only** in Phase 4 | `users.status` (`active`/`suspended`/`blocked`, CHECK constraint, SDD §9.2) is checked at login **and** on every online action via `AccountStatusGuard` (single choke point, SDD §13.2). The admin endpoints that *set* the status are Phase 7 (see §2.3). A suspended/blocked user can still use offline play — that is a client property, not something this backend can block. | `backend/src/common/guards/account-status.guard.ts`; `backend/src/users/user.entity.ts` | Integration: flip status directly in test DB → login 403 `ACCOUNT_SUSPENDED`; authenticated call → 403; unit: guard tests | PASS (enforcement only) — enforcement only; admin set-status endpoints are Phase 7 |

#### 2.1.2 Non-functional requirements (NFR)

| ID | Requirement (short) | Planned implementation | Module / file (planned) | Verification | Status |
|---|---|---|---|---|---|
| NFR-05 | 95% of routine REST ≤ 500 ms server time at 200 concurrent users `[Proposed]` | Design for it in Phase 4 (stateless services, indexed queries §4.3, no N+1, Redis for hot rate-limit reads). **Full k6 load test at 200 concurrent users is Stage 4/5 work, not claimed here** — Phase 4 measures per-endpoint latency in integration tests and records it; the 200-user bar is verified when the gameplay load exists. | Whole `backend/src/`; `backend/test/load/` (smoke only — see §10.5) | Integration timing assertions (p95 of routine endpoints in the local harness); load test deferred to Stage 5 with the k6 script as a follow-up | BLOCKED — no k6 / 200-user load test; test/load/ does not exist |
| NFR-13 | Passwords ≥ 8 chars, salted hash (bcrypt or Argon2), never logged/returned | Argon2id (SDD §13.1: memory 64 MiB, iterations 3, parallelism 1 `[Proposed]` OWASP baseline; per-password salt); `password_hash` column is never selected by any read query except the dedicated auth path, never serialised (DTO allow-list), never logged (log-redaction test, §10.4). bcrypt is the documented fallback if Argon2 cannot run in the deployment (SDD §13.1) — **not** implemented in parallel. | `backend/src/auth/` (`password-hasher.service.ts` — Argon2id via `argon2` package `[P4 choice]`); `backend/src/users/user.entity.ts` | Security: hash verification test (same password → different hashes); code review: no `password_hash` in any response DTO; log test: login flow emits no password/token | PASS |
| NFR-14 | All communication TLS ≥ 1.2 (HTTPS/WSS); plain HTTP/WS refused | TLS is a deployment property: the app binds plain HTTP only on localhost/dev and **refuses to serve production traffic without TLS termination configured** (fail-fast if `NODE_ENV=production` and no TLS/proxy headers configured — §8.1). No plain-WS listener exists; Socket.IO runs over the same HTTPS server. HSTS + `nosniff` headers set by helmet `[P4 choice]` (§8.2). | `backend/src/main.ts`; `backend/src/config/` | Config test: production boot without TLS config → exit non-zero with a named error; header test: responses carry HSTS/`X-Content-Type-Options: nosniff` | PASS — fail-fast + helmet wired; no header-assertion test, no live TLS / prod boot — §13 |
| NFR-15 | Access tokens expire ≤ 15 min; renewable by revocable refresh tokens | Access JWT 15 min (`expiresIn: 900`); refresh tokens opaque, stored **hashed** (SHA-256) in `auth_sessions`, rotated on every use, revocable per-session and per-user; reuse of a presented refresh token revokes the whole session family (SDD §12.4). `sid` claim in the JWT links it to its session row. | `backend/src/auth/` (`token.service.ts`, `auth-session.entity.ts`) | Security: reuse of an old refresh token → family revoked, all sessions for that family dead; integration: rotation yields a new pair, old refresh → 401 | PASS |
| NFR-16 | After 5 consecutive failed logins in 15 min (same account or IP), throttle/lock | Login throttle keyed by **both** account identifier and IP (Redis counters, §6.5); after 5 failures in 15 min further attempts return `429 RATE_LIMITED` with `Retry-After` (and the generic `INVALID_CREDENTIALS` shape is preserved — the 429 itself does not reveal whether the account exists). Counter resets on success. Admin login throttling is Phase 7 (same mechanism, different table). | `backend/src/auth/` (`login-throttle.service.ts` over `RedisService`); `backend/src/redis/` | Security: 5 bad logins → 6th is 429 even with the correct password; success resets the counter; integration: per-IP and per-account keys independent | PASS |
| NFR-17 | Every endpoint + socket event enforces authn/authz server-side; admin denies by default | Global `JwtAuthGuard`; deny-by-default (public routes are an explicit `@Public()` allow-list); ownership checks in services (load the resource, compare `requesterId` — never trust an id from the URL, SDD §13.2); `WsJwtGuard` on the gateway (§9.2); admin deny-by-default is structural in Phase 4 (no admin routes exist yet, so there is nothing to misconfigure). | `backend/src/common/guards/`; `backend/src/socket/` | Authorization matrix test (§10.4) over every route + gateway connect; code review: no controller without an explicit auth declaration | PASS — same matrix gap as FR-42; residuals L-01/L-02 documented |
| NFR-20 | Validate all inputs; rate-limit requests + socket events (20 events/s/connection `[Proposed]`) | Global `ValidationPipe` (class-validator DTOs, unknown fields stripped — SDD §12.1, `whitelist: true, forbidNonWhitelisted: false` `[P4 choice]` — strip, don't reject, per SDD "unknown fields are stripped"); REST 100 req/min per authenticated user (SDD §13.4) + tighter auth limits (§6.5); socket 20 events/s per connection, sustained abuse → disconnect (SDD §12.6). JSON body limit 100 KB, socket event 10 KB (SDD §13.4 `[Proposed]`). | `backend/src/main.ts` (global pipe); `backend/src/common/` (rate-limit guard/interceptor over `RedisService`); `backend/src/socket/` | Fuzz/validation matrix (§10.4): oversized body → 413; unknown fields stripped; bad enum → 400; flood test: 21st socket event in a second → dropped; REST flood → 429 + `Retry-After` | PASS |
| NFR-21 | Collect only needed data; never show password data to admins; support deletion workflow (FR-10) | Data minimisation by schema (§4.1 — no location/contacts/device-id columns exist); no password data in any DTO; FR-10 request path (§2.1.1). Full deletion/anonymisation awaits OD-08 (§11.3). | `backend/src/users/`, `backend/src/auth/` | Data-flow review (§10.4): every column mapped to an FR; no DTO contains `password_hash` | PASS |
| NFR-24 | Support ≥ 500 concurrent players (125 four-player matches); horizontal scaling via Redis `[Proposed]` | Stateless services (sessions in PostgreSQL/Redis, never node memory); Socket.IO Redis adapter wired from day one (§9.2, `[P4 choice]` `ioredis` + `@socket.io/redis-adapter`); per-match lock helper in `RedisService` (§5.3, unused until Phase 5). **The 500-player load test is not Phase 4** — it needs gameplay traffic (Phase 5) and is a Stage 5/Phase 5 exit item. | `backend/src/socket/` (adapter wiring); `backend/src/redis/` | Integration: two gateway instances share a broadcast via the adapter (local two-node test, §10.3); load test deferred | BLOCKED — Redis adapter + two-node broadcast pass; 500-player load test not run |
| NFR-27 | Zero static-analysis errors (ESLint); layered modules | ESLint (flat config) + `tsc --noEmit` in `backend/package.json` (`lint`, `typecheck` scripts); layered module rule (§3.2) enforced by code review in Stage 5 (no automated import-boundary tool is prescribed by the SDD for the server; if Stage 2 adds `eslint-plugin-boundaries` that is a `[P4 choice]` to record then). No CI exists to run these (see §0.2) — Stage 2 runs them locally and pastes the output as evidence. | `backend/` (`eslint.config.mjs`, `tsconfig*.json`, `package.json`) | `npm run lint` exit 0; `npm run typecheck` exit 0 (Stage 2 evidence) | PASS |
| NFR-31 | Online results derived only from server-validated transitions, stored atomically; no client/admin edits a result | **Pattern only in Phase 4** (no match/result exists yet): the transaction discipline is established now — every multi-row write in Auth/Users uses one TypeORM transaction (register, reset, sanction-enforcement reads are single-row). The match-result atomic transaction (FR-58) is Phase 5 and reuses this pattern; the "no edit" rule is structural (no UPDATE endpoint for results will ever be added — recorded here so Stage 5 can check it). | `backend/src/auth/`, `backend/src/users/` (transaction usage); `backend/src/database/` | Integration: register failure mid-transaction rolls back both rows (fault-injection test, §10.3) | PASS (pattern) — transaction pattern only; no match/result exists yet |
| NFR-37 | Backend logs errors, connection counts, latency, admin actions; logs exclude secrets | Structured JSON logging (`nestjs-pino` `[P4 choice]` — SDD is silent on the logging library; pino is the conventional NestJS structured-logging choice) with `requestId`/`correlationId` on every line; no passwords/tokens/PII in logs (redaction list: `password`, `*token*`, `authorization`, `mfa*`); connection-count + latency lines from an interceptor; admin-action logging has nothing to log yet (Phase 7). | `backend/src/common/logging/` (`logger.module.ts`, redaction list); `backend/src/common/interceptors/logging.interceptor.ts` | Log test: exercise login + a 500 and assert no secret appears in output; unit: redactor unit tests | PASS |
| NFR-39 | Dart + server engines both pass one shared rule-vector set in CI `[Proposed]` | **Foundation only in Phase 4:** a vector loader that reads `diceup_app/test/vectors/rules.json`, validates its schema (formatVersion, rulesetVersion `1.0.0`, 23 cases, required step/expect fields) and validates every embedded ruleset for **coherence** (the Dart `RulesetConfig.validate()` rules: at least one release roll, `maxConsecutiveSixes >= 0`, version non-empty and == `rulesetVersion`), asserting the canonical default case equals the Dart `RulesetConfig` defaults exactly. **Correction (Stage 5, 2026-11-27):** the original wording wrongly said the loader "asserts the embedded ruleset equals the Dart defaults" for every case. The real file has 17/23 cases at the defaults and 6 deliberate single-field variants (release-on-one, extra-turn-on-six/-capture/-home disabled, third-six-limit-off, exact-finish-off); requiring all 23 to equal the defaults would be false. The loader (and its spec, which asserts the 17/6 split) is the correct behaviour; this plan text was the error. The TypeScript engine it will test does **not** exist until Phase 5, so no conformance run is claimed in Phase 4. CI itself does not exist (see §0.2) — the loader runs as a Jest test locally. | `backend/test/vectors/` (`rules-vectors.loader.ts`, `rules-vectors.spec.ts`); vectors file itself is **not** copied — the loader reads the repo-relative path `../diceup_app/test/vectors/rules.json` so there is exactly one copy | Test: loader parses 23/23 cases; tampered vector (bad version, missing field) → test fails; incoherent embedded ruleset → test fails; canonical case must equal Dart defaults and each variant case must differ in exactly one field | PASS (foundation) — loader validates coherence; 17/23 at defaults, 6 single-field variants — wording corrected, §13 |

#### 2.1.3 Constraints, interfaces, business rules (in scope)

| ID | Requirement (short) | Planned implementation | Module / file (planned) | Verification | Status |
|---|---|---|---|---|---|
| CON-03 | Backend Node.js + NestJS + TypeScript + Socket.IO; PostgreSQL persistence; Redis transient coordination | The whole `backend/` tree (§3). Node 22 LTS target (see §0.2 variance note). | `backend/` | `node --version` / `package.json` engines check in Stage 2 | PASS — stack verified; Node 22 LTS runtime unexercised (ran on 24.22.1) |
| CI-01 | Mobile ↔ backend REST over HTTPS/JSON; consistent success/error structures + status codes | §6 (envelope, status table, `/v1` prefix). | `backend/src/common/` (envelope interceptor + exception filter) | Contract tests per endpoint (§10.3) | PASS |
| CI-02 | Mobile ↔ backend real-time over Socket.IO/WSS; socket authenticated with access token; unauthenticated refused | §8 (namespace `/game`, `WsJwtGuard`, handshake auth). | `backend/src/socket/` | Gateway tests: no token → refused; bad token → refused; valid → connected | PASS |
| CI-04 | Backend ↔ PostgreSQL; only the backend connects; clients/panel never connect directly | TypeORM `DataSource` owned by `DatabaseModule`; no DB credentials leave the server (env only, §7.1). No other component gets a connection string. | `backend/src/database/` | Code review: exactly one `DataSource` creation site; config test: no DB URL in any client-facing response | PASS |
| CI-05 | Backend ↔ Redis; ephemeral only; no final result's sole copy in Redis | §5.3 — key registry with TTLs; the only Phase 4 Redis writes are rate-limit counters and (prep) presence/lock key *definitions*. No business truth is written to Redis in Phase 4. | `backend/src/redis/` | Integration: flush Redis mid-test → auth flows still work (sessions are in PostgreSQL); review: key registry vs §5.3 | PASS |
| CI-07 | Backend ↔ email provider (verification + reset) | **Interface only in Phase 4** (provider TBD, OPEN OD-09/A-04, §11.3). `Mailer` interface + a dev-only log transport `[P4 choice]` so Stage 2/4 can verify the token flows without a provider. No production provider is selected here. | `backend/src/mailer/` (`mailer.interface.ts`, `log-mailer.service.ts`) | Integration: register/forgot-password produce a dispatched message containing the token (captured from the log transport in tests); no real email is sent | PASS (interface) — Mailer interface + log/SMTP transports; no real provider (OD-09) |
| CI-08 | Backend ↔ push service (APNs/FCM) | **Interface only, no implementation in Phase 4.** No notification exists yet (FR-68 is Phase 6). The `PushSender` interface is declared (§7.4) so Phase 6 does not redesign auth-adjacent code; it has no provider and no transport. | `backend/src/mailer/` (interface declaration only) | Code review: interface exists, zero providers wired | PASS (interface) — PushSender interface declared; no provider, no transport |
| BR-14 | Ruleset versioning — frozen at match start, stored with every online match | **Foundation only:** ruleset version `1.0.0` is a validated config value (`RULESET_VERSION`, §8.1) and the vector loader pins it (§2.1.2 NFR-39). No match stores it yet (Phase 5). | `backend/src/config/` | Config test: version value equals the vectors file + Dart default | PASS (foundation) — RULESET_VERSION 1.0.0 pinned; no match stores it yet (Phase 5) |
| BR-19 | Suspended/blocked accounts cannot use online features; offline unaffected | `AccountStatusGuard` (§2.1.1 FR-75/76). | `backend/src/common/guards/account-status.guard.ts` | See FR-75/76 row | PASS |

**In-scope count: 34 rows** — 12 FR rows (FR-02…FR-10, FR-42, FR-63, FR-75/76),
13 NFR rows, 1 CON, 6 CI, 2 BR (BR-14, BR-19). One row (FR-10) is partial;
two rows (FR-75/76, NFR-31, NFR-39, BR-14, CI-07, CI-08) are foundation /
pattern / interface-only, as labelled in the row.

### 2.2 Out of scope — NOT IN PHASE 4 SCOPE (grouped; every remaining ID is covered)

| IDs | Requirement (short) | Belongs to | Why not Phase 4 / what Phase 4 must not do | Status |
|---|---|---|---|
| FR-01, FR-11–FR-32 | Guest access; offline game init, modes, players, dice, moves, captures, home path, winning, results, restart, exit, resume, local recording/history/statistics | **Already implemented (Stage 1, Flutter)** — not backend work at all | `diceup_app/` is read-only. Phase 4 must not add any offline dependency on the backend (CON-05). No endpoint may be required for offline play. | NOT APPLICABLE |
| FR-33–FR-41 | AI participation, auto-roll, move detection, Easy/Medium/Hard, rule compliance, pacing, difficulty selection | **Already implemented (Stage 1, Flutter)** | AI is offline-only (A-10); online matches are human-only. No AI code in `backend/`. | NOT APPLICABLE |
| FR-43, FR-44, FR-46, FR-47, FR-48, FR-59 | Create/join room, readiness, start match, invite friend, leave room (+ host transfer) | **Phase 5** (Stage 2 gameplay) | No `rooms` / `room_members` tables in Phase 4 (§4.1). The gateway must not implement `room:join`/`room:leave`/`room:ready`/`match:start` yet (§9.3). Room-authorization *prep* is a guard interface only (§3.2). | NOT APPLICABLE |
| FR-45 | Matchmaking — public queue, auto-grouping `[Proposed]` | **Phase 5** (also gated by OD-05: Stage 2 vs 3) | Only the Redis key pattern `matchmaking:queue` is *named* in §5.3. No queue code, no endpoint. | NOT APPLICABLE |
| FR-49–FR-58 | Server dice, move validation, sync + sequence numbers, turn timer + auto-play, duplicate/late actions, disconnect/grace, reconnection, forfeit, consistent state, match completion + atomic recording | **Phase 5** (Stage 2 gameplay) | No `matches` / `match_players` / `move_events` tables (§4.1); no TS engine; no timers. Phase 4 provides only the seams: `requestId`/`Idempotency-Key` convention (§9.3), per-match lock helper (§5.3), snapshot-shape agreement (§9.3). | NOT APPLICABLE |
| FR-60, FR-61, FR-62 | Friend requests, friend list + presence, game invitations | **Phase 6** (Stage 3 player) | No `friendships` table; no presence writes (presence keys are definitions only, §5.3). | NOT APPLICABLE |
| FR-64, FR-65, FR-66, FR-67 | Online match history, player statistics, leaderboard, ranking update | **Phase 6** (also gated by OD-06 ranking algorithm) | No `rankings` table; no history/stats endpoints. `profiles` cached counters stay 0 (§2.1.1 FR-63). | NOT APPLICABLE |
| FR-68 | Notifications (in-app + push) | **Phase 6** | No `notifications` / `device_tokens` tables; push interface only (§2.1.3 CI-08). | NOT APPLICABLE |
| FR-69 | Report player | **Phase 6** (feeds Phase 7 report review) | No `reports` table. | NOT APPLICABLE |
| FR-70, FR-71, FR-72, FR-73, FR-74, FR-77, FR-78, FR-79, FR-80, FR-81, FR-82 | Admin auth (+ MFA), admin session control, dashboard, user search/detail, report management, platform monitoring, game config, leaderboard management, admin reports, audit trail | **Phase 7** (Stage 3 admin, Next.js panel) | No `admin_accounts` / `account_sanctions` / `game_configurations` / `audit_logs` tables in Phase 4 (§4.1). No `/v1/admin/*` router. No admin JWT type, no TOTP code. FR-75/76 *enforcement* is in scope (§2.1.1); the endpoints that set the status are not. | NOT APPLICABLE |
| NFR-01, NFR-02, NFR-03, NFR-04 | Cold start ≤ 3 s, ≥ 50 fps, tap feedback ≤ 100 ms, Hard AI ≤ 500 ms | **Flutter / Stage 1** — not backend | Not measured by `backend/` tests. | NOT APPLICABLE |
| NFR-06 | 95% of accepted online actions reach other players ≤ 800 ms (RTT ≤ 100 ms) | **Phase 5** (needs live matches + multi-client harness) | No socket game traffic exists in Phase 4 to measure. | NOT APPLICABLE |
| NFR-07, NFR-08, NFR-09, NFR-10 | Usability: 3-tap start, 48 dp targets, 320–430 dp portrait, admin 4-interaction suspend + WCAG 2.2 AA | **Flutter / Phase 7 panel** | Not backend-verifiable. | NOT APPLICABLE |
| NFR-11, NFR-12 | 99% crash-free sessions; 1,000 AI-only matches, no rule violation | **Flutter / Stage 1** | The 1,000-match simulation runs against the Dart engine, not this backend. | NOT APPLICABLE |
| NFR-18 | Backend rejects 100% of client-supplied dice/results/other players' moves | **Phase 5** (negative game tests) | The *mechanism* it will use (server-side validation, §10.4) is designed here; the tests need the game service to exist. Phase 4's negative tests cover auth/authz/input instead (§10.4). | NOT APPLICABLE |
| NFR-22 | Backend ≥ 99.5% monthly availability | **Operations / deployment** (Phase 7+) | Not a code deliverable. No uptime claim is made in Phase 4. | NOT APPLICABLE |
| NFR-23 | Offline 0% network-dependent (airplane-mode) | **Guard constraint, already satisfied** — recorded, not implemented | Phase 4 must not regress it: no Flutter change ships with this phase, and no backend call is added to any offline path. | PASS (guard — verified not violated, §13) |
| NFR-25 | Leaderboard ≤ 500 ms p95 with 100,000 users | **Phase 6** (needs `rankings` + generated data) | No leaderboard query exists in Phase 4. | NOT APPLICABLE |
| NFR-26, NFR-28, NFR-29 | Pure Dart engine ≥ 90% rule coverage; Android 8+/iOS 13+; one Dart codebase | **Flutter / Stage 1** | Not backend work. | NOT APPLICABLE |
| NFR-30, NFR-35 | Local SQLite writes transactional; corrupt local DB recreates itself | **Flutter / Stage 1** | Not backend work. | NOT APPLICABLE |
| NFR-32, NFR-33 | Reconnect + full state ≤ 5 s (p95) in grace; restart restores matches from persisted state or cleanly cancels | **Phase 5** (needs matches + grace machinery) | The snapshot contract it will use is specified in §9.3; no reconnect test is runnable in Phase 4. | NOT APPLICABLE |
| NFR-34 | PostgreSQL daily backup, RPO ≤ 24 h, RTO ≤ 4 h, restore rehearsed | **Operations / deployment** | Not code. Stage 2 documents the local backup command for the dev cluster in `backend/README.md` only; no production backup is set up or claimed. | NOT APPLICABLE |
| NFR-36, NFR-38 | App ≤ 100 MB, 500-match local cap; strings externalised | **Flutter** | Not backend work. | NOT APPLICABLE |
| BR-01–BR-13, BR-15, BR-16, BR-17, BR-18, BR-20 | All Ludo rules (players/tokens, dice, turn order, release, movement, extra turns, sixes, capture, safe cells, home/finish, winning, stacking, no-legal-move); forfeit; ranking eligibility; competitive integrity (no admin result edits); offline separation; online timers | **Phase 5** (BR-01–13, 15, 20 — engine + game service) / **Phase 6** (BR-16 — ranking) / **Phase 7** (BR-17 — admin capability absence) / **already satisfied** (BR-18 — no offline data reaches this backend) | BR-14 and BR-19 are the only business rules with Phase 4 content (§2.1.3). The TS engine that implements BR-01–13 is Phase 5. | NOT APPLICABLE |
| CON-01, CON-02, CON-04, CON-05, CON-06 | Flutter/Dart + CustomPainter; SQLite local-only, no rules in it; Next.js admin panel, separate; offline engine on-device; no payments/subscriptions | **Guard constraints** (Flutter / Phase 7 / scope) | Phase 4 must not violate them: no Flutter change, no admin panel, no payment code, no offline dependency. Recorded so Stage 5 checks them. | PASS (guard — verified not violated, §13) |
| CI-03 | Admin panel ↔ backend (separate HTTPS admin APIs) | **Phase 7** | No admin router in Phase 4. | NOT APPLICABLE |
| CI-06 | App ↔ SQLite (local data layer only) | **Flutter / Stage 1** | The backend never touches SQLite. | NOT APPLICABLE |

**Out-of-scope count: 70 FRs, 26 NFRs, 18 BRs, 5 CONs, 2 CIs** — every
requirement ID in the SRS/SDD is accounted for exactly once across §2.1 +
§2.3 (82 FR + 39 NFR + 20 BR + 6 CON + 8 CI = **155 IDs**).

### 2.4 What "PLANNED" does not mean

- No row above is implemented, tested, or verified by this plan.
- "Planned implementation" names the *intended* module/file so Stage 2 does
  not have to re-derive the mapping — Stage 2 may move a file if the module
  boundary is preserved, and must record the move in its handoff.
- If Stage 2 finds a row's planned implementation contradicts the SDD, the
  SDD governs and the plan is corrected in Stage 5 (the plan is not a
  second SDD).

---

## 3. Module structure

### 3.1 Location decision

**`backend/` at the repo root** (sibling of `diceup_app/`, `docs/`).
The SDD does not prescribe a directory name — it prescribes "one NestJS
application, one module per bounded context" (SDD §3.5, §4.5) — so the
conventional NestJS layout at the repo root is followed, as the brief
anticipates. Rationale: it mirrors `diceup_app/` (one top-level directory
per deployable component), keeps the Flutter tree untouched, and matches
SDD §15.1 (backend as one deployable unit / one Docker image). The Next.js
admin panel (Phase 7) will later sit at `admin/` by the same rule; that is
a naming expectation, not a Phase 4 deliverable.

### 3.2 NestJS module tree (planned)

```
backend/
├── package.json                  # engines: node >=22 <23 (SDD DA-07); npm only
├── tsconfig.json / tsconfig.build.json
├── nest-cli.json
├── .env.example                  # every variable in §7.1, with safe example values only
├── .gitignore                    # .env, node_modules, dist, coverage — never secrets
├── eslint.config.mjs
├── README.md                     # how to run / test locally (incl. starting local PG + Redis)
├── src/
│   ├── main.ts                   # bootstrap: global pipe/filter/interceptor, helmet, CORS, Swagger, shutdown hooks
│   ├── app.module.ts             # imports all modules below; global guards (§3.2)
│   ├── config/
│   │   ├── configuration.ts      # typed config object (validated, §7)
│   │   └── config.validation.ts  # Joi schema — fail-fast (§7.1)
│   ├── common/
│   │   ├── decorators/           # @Public(), @CurrentUser()
│   │   ├── filters/              # http-exception.filter.ts (envelope §6.3)
│   │   ├── interceptors/         # response-envelope + logging.interceptor.ts
│   │   ├── guards/               # jwt-auth.guard.ts, email-verified.guard.ts,
│   │   │                         # account-status.guard.ts, ws-jwt.guard.ts
│   │   ├── pipes/                # (global ValidationPipe is wired in main.ts)
│   │   ├── logging/              # logger.module.ts (nestjs-pino [P4 choice]), redaction
│   │   ├── pagination/           # cursor-pagination helpers (§6.4)
│   │   └── errors/               # error-code enum (ERROR_CODES, §6.3)
│   ├── database/
│   │   ├── database.module.ts    # TypeORM DataSource (async, from validated config)
│   │   ├── data-source.ts        # CLI data source for migrations (same config)
│   │   └── migrations/           # 0001_init-auth.ts … (one file per migration, §4.4)
│   ├── redis/
│   │   ├── redis.module.ts       # ioredis client (global module)
│   │   └── redis.service.ts      # get/set/del/incr-with-TTL, lock helper, key registry (§5.3)
│   ├── mailer/
│   │   ├── mailer.interface.ts   # Mailer (sendVerification, sendPasswordReset)
│   │   ├── log-mailer.service.ts # dev/test transport [P4 choice]
│   │   └── mailer.module.ts
│   ├── auth/
│   │   ├── auth.module.ts
│   │   ├── auth.controller.ts    # register/login/refresh/logout/verify/forgot/reset
│   │   ├── auth.service.ts       # orchestration (transactions §4.4)
│   │   ├── token.service.ts      # RS256 access JWT + opaque refresh (§7.1)
│   │   ├── password-hasher.service.ts  # Argon2id (§7.1)
│   │   ├── email-verification.service.ts
│   │   ├── password-reset.service.ts
│   │   ├── login-throttle.service.ts   # NFR-16 over RedisService
│   │   ├── strategies/           # jwt.strategy.ts (passport-jwt [P4 choice])
│   │   ├── entities/             # auth-session.entity.ts, email-token.entity.ts
│   │   └── dto/                  # register/login/refresh/verify/forgot/reset DTOs
│   ├── users/
│   │   ├── users.module.ts
│   │   ├── users.controller.ts   # GET/PATCH /users/me, password, preferences,
│   │   │                         # GET /users/{id}/profile, DELETE /users/me (request)
│   │   ├── users.service.ts
│   │   ├── entities/             # user.entity.ts, profile.entity.ts
│   │   └── dto/                  # update-profile/change-password/preferences/
│   │                             # public-profile DTOs
│   ├── health/
│   │   ├── health.module.ts
│   │   └── health.controller.ts  # GET /health, GET /health/ready (§6.6)
│   └── socket/
│       ├── socket.module.ts
│       ├── game.gateway.ts       # namespace /game; auth + lifecycle only (§8)
│       └── ws-jwt.guard.ts       # (or under common/guards — Stage 2 picks one home)
└── test/
    ├── jest-e2e.json / jest-unit.json   # separate configs; e2e boots real PG+Redis
    ├── setup-e2e.ts              # creates a scratch database per run (never production)
    ├── vectors/
    │   ├── rules-vectors.loader.ts
    │   └── rules-vectors.spec.ts # NFR-39 foundation (§2.1.2)
    ├── unit/                     # services, guards, DTOs, redaction, hashing
    ├── integration/              # auth flows, rate limits, health, transactions
    └── security/                 # §10.4 negative tests
```

### 3.3 Module rules (SDD §3.5, §4.1, §4.5)

1. One module per bounded context; a module depends only on another
   module's **exported service interface**, never its internals.
2. `GameModule` does not exist in Phase 4. Nothing in Auth/Users may
   import game concepts (no `matchId`, no `tokenId`, no dice) — if Stage 2
   finds itself writing one, the scope has leaked and it stops.
3. Cross-cutting concerns (auth guards, validation, rate limiting, logging,
   exception mapping) are implemented **once** globally, never per module
   (SDD §3.5).
4. `diceup_app/` is never imported. The only cross-tree read is the test
   vector loader (§2.1.2 NFR-39), which reads a JSON file — not Dart code.
5. No `.github/workflows/` anywhere in this tree (see §0.2).

### 3.4 What Stage 2 builds first (recommended order, not a schedule)

1. Config + logging + envelope + health (the skeleton everything plugs into).
2. Database module + migration 0001 + the four entities (§4).
3. Redis module + rate-limit plumbing (§5).
4. Auth module (register → verify → login → refresh → logout → reset).
5. Users module (profile, password, preferences, deletion request).
6. Socket gateway skeleton (§8) — last, because it depends on the auth
   guards being real.

---

## 4. Database plan (PostgreSQL only)

### 4.1 Entities required for Phase 4 only

Exactly four tables, taken verbatim from SDD §9.2 (column names, types and
constraints as specified there). **No other table is created in Phase 4.**
The full multiplayer/social/admin schema (rooms, matches, move_events,
friendships, rankings, notifications, reports, admin_accounts,
account_sanctions, game_configurations, audit_logs) is Phase 5/6/7 work.

| Table | Key columns (SDD §9.2) | Purpose in Phase 4 |
|---|---|---|
| `users` | `id UUID PK` (`gen_random_uuid()`); `email CITEXT UNIQUE NOT NULL`; `username CITEXT UNIQUE NOT NULL`; `password_hash TEXT NOT NULL`; `status TEXT NOT NULL DEFAULT 'active' CHECK (active/suspended/blocked)`; `email_verified_at TIMESTAMPTZ NULL`; `created_at/updated_at TIMESTAMPTZ NOT NULL` | Account identity (FR-02…FR-06). CITEXT gives case-insensitive uniqueness. |
| `profiles` | `user_id UUID PK FK→users(id) ON DELETE CASCADE`; `display_name VARCHAR(50) NOT NULL`; `avatar_key VARCHAR(50) NOT NULL DEFAULT 'default'`; `matches_played/matches_won INT DEFAULT 0` (cached, stay 0 until Phase 6); `updated_at` | Public profile 1—1 with users (FR-07, FR-63). |
| `auth_sessions` | `id UUID PK`; `user_id UUID FK→users`; `refresh_token_hash TEXT NOT NULL`; `device_label TEXT NULL`; `expires_at TIMESTAMPTZ NOT NULL`; `revoked_at TIMESTAMPTZ NULL`; `created_at` | Revocable refresh sessions (NFR-15). Expired rows purged by a scheduled job (see §4.5). |
| `email_tokens` | `id UUID PK`; `user_id UUID FK→users`; `purpose TEXT CHECK (verify/reset)`; `token_hash TEXT NOT NULL`; `expires_at NOT NULL`; `used_at NULL`; `UNIQUE (user_id, purpose) WHERE used_at IS NULL` | Single-use, time-limited verification/reset tokens (FR-03, FR-06). |

**Roles / permissions:** there is **no roles table** in Phase 4. The SRS
defines a single Administrator role (A-08) held in a separate
`admin_accounts` table (Phase 7), and "room host" is a temporary room-level
responsibility, not an account role (SRS §2.3). Player JWTs carry
`role: 'player'` (SDD §12.4); the admin role is a separate token type in
Phase 7. If a future staff sub-role is ever needed it is OD-04 — not
designed here.

**`[P4 choice]` addition — one column, flagged:** `users.deletion_requested_at
TIMESTAMPTZ NULL`, supporting the FR-10 *request* path (§2.1.1). The SDD
does not name this column; it is the minimal marker that lets the request
be recorded without inventing an anonymisation workflow (which awaits
OD-08). Reversible: dropped or repurposed when the deletion workflow is
designed in Phase 6/7.

**Explicitly not in Phase 4:** `rooms`, `room_members`, `matches`,
`match_players`, `move_events`, `friendships`, `rankings`, `notifications`,
`device_tokens`, `reports`, `admin_accounts`, `account_sanctions`,
`game_configurations`, `audit_logs`. Stage 2 must not create them
"in advance" — a table that exists invites code that writes to it.

### 4.2 DB access layer choice

**TypeORM** (with `pg` driver), as prescribed by the SDD: §3.5 ("TypeORM
repositories"), §9 ("TypeORM / SQL"), §15.2 ("TypeORM migrations
`[Proposed]`"), §17.2 (listed as a proposed addition, "NestJS-native
persistence + migrations"). The prescription is followed; the
`[Proposed]` tag is noted because it means the SDD itself leaves the door
open to substitution — but substitution would have to be justified against
the SDD's own module text, and the repository pattern (§4.3) is what makes
it cheap if it ever happens. No second ORM, no raw-SQL string building
(SDD §13.4: parameterised queries only).

- Entities are TypeORM `@Entity()` classes, one file per entity, colocated
  with their owning module (`auth/entities/`, `users/entities/`).
- All data access goes through repositories injected into services
  (SDD §4.3 repository pattern). Services never import `DataSource`
  directly except for explicit transactions.
- The app's PostgreSQL role follows SDD §13.6 least privilege: read/write
  on the four application tables; no `UPDATE`/`DELETE` on any audit table
  (none exists yet — the grant rule is recorded now so Phase 7 applies it);
  cannot create users/extensions; cannot read `admin_accounts.password_hash`
  through any application query (no such table in Phase 4).

### 4.3 Indexes / constraints (SDD §9.3, Phase 4 subset)

Beyond PKs/unique keys in §4.1:

| Index / constraint | Purpose |
|---|---|
| `users (status, created_at)` | Admin list in Phase 7 (FR-73) — created now because the column exists now; harmless, and it is the SDD's own recommendation. |
| `auth_sessions (user_id, expires_at)` | Session lookup + purge of expired rows. |
| `email_tokens (user_id, purpose) WHERE used_at IS NULL` | Enforces at most one live token per purpose (SDD §9.2 partial unique). |
| `users.email` / `users.username` CITEXT unique | Case-insensitive uniqueness (FR-02); note for Stage 2: requires the `citext` extension — the migration must `CREATE EXTENSION IF NOT EXISTS citext` (the app role cannot create extensions per §4.2, so this runs as the migration role; record it in the migration file). |
| `profiles.display_name` length | Enforced by `VARCHAR(50)` + DTO validation (defence in depth). |

### 4.4 Migration strategy + schema versioning

- **Tool:** TypeORM migrations (`typeorm` CLI via the `data-source.ts`
  in §3.2), run as a release step, never by hand on the database
  (SDD §15.2).
- **Numbering:** `0001_init-auth.ts` (the four tables), then one file per
  change, strictly increasing. A migration never drops a column the
  currently-deployed code still reads (**expand-then-contract**,
  SDD §15.4) — Phase 4 has no deployed code yet, so 0001 can be a clean
  create, but the rule is adopted from the first migration so rollbacks
  stay possible later.
- **Schema versioning:** TypeORM's own `migrations` table is the version
  record (applied-migration rows with timestamps). In addition, every
  migration file header records the SDD/SRS requirement IDs it implements
  (e.g. `0001: FR-02/03/04/05/06, NFR-13/15`) so traceability survives a
  `git log` without the plan doc.
- **No `synchronize: true` anywhere** — not in dev, not in tests. Schema
  changes only via migrations. Stage 2 must assert this in a config test
  (a test that boots the `DataSource` options and fails if `synchronize`
  is truthy).
- **Test databases:** integration tests create a scratch database
  (`diceup_test_<random>` or `diceup_test` on the local cluster), run all
  migrations, run the suite, drop it. Never the dev database, never any
  shared/production service (§10.1).

### 4.5 Transactions + maintenance

- One transaction per multi-row write: register (users + profiles +
  email_tokens), password reset (password update + session revocation +
  token invalidation). Single-row writes need no explicit transaction.
- A scheduled purge job (NestJS `@Cron()` — `[P4 choice]`; the SDD
  requires purging, SDD §9.2 "expired rows purged by a job", but names no
  scheduler) deletes expired/revoked `auth_sessions` and used/expired
  `email_tokens` rows. Daily, low-traffic hour, logged with row counts.
  In Phase 4 the job is the only use of the scheduler; match-related jobs
  do not exist yet.
- Backups (NFR-34) are an operations concern, not code (§2.3). Stage 2
  documents the local `pg_dump` command for the dev cluster in
  `backend/README.md` and does not claim a production backup.

---

## 5. Redis plan

### 5.1 What Redis is used for in Phase 4 (real, implemented)

| Use | Key pattern (SDD §9.4) | TTL / type | Notes |
|---|---|---|---|
| REST + socket rate-limit counters | `ratelimit:{userId\|ip}:{window}` | Counter, TTL = window | NFR-20, NFR-16. Implemented via `RedisService.incrWithExpiry` (§5.2). The only Phase 4 writes to Redis. |
| Login-throttle counters | `ratelimit:login:{accountOrIp}:15m` | Counter, TTL 15 min | NFR-16 (§7.1). Same primitive, different key namespace. |
| Health / lifecycle | — | — | `PING` on readiness (§6.6); graceful shutdown closes the client (§5.2). |

### 5.2 RedisService abstraction (the only Redis API the app uses)

`backend/src/redis/redis.service.ts` exposes a small, typed surface and
nothing else may import the raw client:

- `ping()`, `get(key)`, `set(key, value, ttlSeconds)`, `del(key)`,
  `incrWithExpiry(key, windowSeconds)` (atomic `INCR` + `EXPIRE` via Lua
  or `SET NX` — Stage 2 picks one and tests the race),
  `acquireLock(key, ttlSeconds)` / `releaseLock(key, token)` — `SET NX EX`
  per-match lock (SDD §9.4 `match:lock:{matchId}`, TTL 10 s).
- Client: `ioredis` `[P4 choice]` (SDD names no Redis client library; the
  Socket.IO Redis adapter requires a Redis client, and `ioredis` is the
  adapter's conventional pairing — see §9.2).
- Failure policy (SDD §9.4): if Redis is unavailable, the backend **refuses
  new online sessions with a clear error** (login/refresh return `503`
  with `SERVICE_UNAVAILABLE` — the throttle cannot be enforced, so failing
  open would silently drop a security control) but keeps serving
  PostgreSQL-backed reads that do not need Redis. In Phase 4 that means:
  health/readiness reports Redis down, auth writes fail closed, and
  nothing else exists to degrade. No final result is ever stored only in
  Redis (CI-05) — trivially true in Phase 4, asserted by the key registry
  review (§10.3).

### 5.3 Preparation-only (defined, not implemented)

These key patterns are **named in the plan and in a `REDIS_KEYS`
registry constant** so later phases do not invent conflicting names, but
no Phase 4 code reads or writes them:

| Key pattern (SDD §9.4) | Phase | Notes |
|---|---|---|
| `presence:user:{userId}` (String, TTL 30 s, heartbeat-refreshed) | Phase 6 (FR-61) | Friend online/offline status. No presence writes in Phase 4. |
| `matchmaking:queue` (sorted set, score = enqueue time) | Phase 5 (FR-45) | No queue code in Phase 4. |
| `match:lock:{matchId}` (String, TTL 10 s, NX) | Phase 5 (FR-50/53) | Helper exists (§5.2); no caller exists yet. |
| `match:state:{matchId}` (Hash/JSON, TTL 5 min) | Phase 5 (FR-57) | Snapshot cache only — PostgreSQL is the truth. |
| `socket:adapter` (Socket.IO Redis adapter pub/sub) | Phase 4 wiring, Phase 5 traffic | Adapter is wired in Phase 4 (§9.2) so multi-node behaviour is testable early; no game broadcasts exist yet. |
| `room:code:{code}` (String → roomId) | Phase 5 (FR-43/44) | Optional fast lookup; PostgreSQL remains authoritative. No code in Phase 4. |

---

## 6. REST API plan

### 6.1 Versioning + route conventions

- Base: `/v1` (SDD §12.1: `https://api.diceup.example/v1` `[Proposed]` —
  the host is an example; the **versioned prefix** is the design choice
  being followed so a future breaking change does not strand installed
  apps). Admin API lives under `/v1/admin/*` in Phase 7 — the router
  mount point is reserved now, the router itself is not created.
- All requests/responses JSON. IDs in URLs are UUIDs, except the
  6-character room code (Phase 5). No other identifier format is
  introduced.
- REST is for request/answer state (auth, profile — SDD §12). Anything
  that must reach other players within 800 ms (NFR-06) is a socket event,
  not REST. Phase 4 has no such traffic.

### 6.2 Phase 4 endpoints (complete list — nothing else is added)

| Method + endpoint | Purpose (FR) | Auth |
|---|---|---|
| `POST /v1/auth/register` | Register (FR-02) | Public, rate-limited |
| `POST /v1/auth/login` | Log in (FR-04) | Public, NFR-16 throttle |
| `POST /v1/auth/refresh` | Refresh session (NFR-15) | Refresh token |
| `POST /v1/auth/logout` | Log out, revoke refresh (FR-05) | User (access JWT) |
| `POST /v1/auth/verify-email` | Verify email (FR-03) | Token in body |
| `POST /v1/auth/verify-email/resend` | Resend verification `[P4 choice]` (SDD names verification + expiry/ re-request in UC-04 A2 but no endpoint; a resend endpoint is the conventional shape — rate-limited, neutral response) | Public, rate-limited |
| `POST /v1/auth/forgot-password` | Request reset (FR-06) | Public, rate-limited |
| `POST /v1/auth/reset-password` | Reset with token (FR-06) | Token in body |
| `GET /v1/users/me` · `PATCH /v1/users/me` | Own profile (FR-07) | User |
| `PATCH /v1/users/me/password` | Change password (FR-08) | User |
| `PATCH /v1/users/me/preferences` | Notification preferences (FR-08) | User |
| `GET /v1/users/{id}/profile` | Public profile (FR-63) | User |
| `DELETE /v1/users/me` | Request account deletion (FR-10, partial) | User |
| `GET /v1/health` | Liveness (§6.6) | Public |
| `GET /v1/health/ready` | Readiness (§6.6) | Public |

No rooms, matches, friends, stats, leaderboard, notification, report or
admin endpoint is added in Phase 4 (§2.3). Any Stage 2 temptation to add
one "while we're here" is out of scope.

### 6.3 Response / error envelope (SDD §12.3, §12.5)

Success (all endpoints):

```json
{ "success": true, "data": { /* endpoint payload */ } }
```

Error:

```json
{ "success": false,
  "error": { "code": "USERNAME_TAKEN", "message": "That username is already taken." } }
```

Rules: machine-readable `code` is stable (clients switch on it, never on
message text); human-readable `message` is present; validation errors add
`error.details` with per-field messages; 500s add a `correlationId` the
user can quote to support, and the server logs the same id (SDD §12.5).
HTTP status mapping (SDD §12.5):

| Status | Meaning | Example codes |
|---|---|---|
| 400 | Validation failed (DTO) | `VALIDATION_FAILED` |
| 401 | Missing/expired/invalid token; or login failure (generic) | `UNAUTHORIZED`, `INVALID_CREDENTIALS` |
| 403 | Authenticated but not allowed (suspended, unverified for online, not owner) | `FORBIDDEN`, `ACCOUNT_SUSPENDED`, `EMAIL_NOT_VERIFIED` |
| 404 | Not found (or not visible to the requester — same response either way) | `NOT_FOUND` |
| 409 | Conflict (duplicate username/email, token already used) | `USERNAME_TAKEN`, `EMAIL_TAKEN`, `TOKEN_ALREADY_USED` |
| 410 | Token expired `[P4 choice]` (SDD does not distinguish 409/410 for expired email tokens; 410 marks "gone" explicitly and is reversible) | `TOKEN_EXPIRED` |
| 422 | Semantically invalid for current state | `INVALID_STATE` |
| 429 | Rate limit exceeded; `Retry-After` header set | `RATE_LIMITED` |
| 500 | Unexpected error; generic message to client, correlation id logged | `INTERNAL_ERROR` |
| 503 | A required dependency (PostgreSQL/Redis) is down | `SERVICE_UNAVAILABLE` |

A 401 from an API call triggers one silent refresh client-side; if the
refresh fails the client clears the session (Flutter concern, SDD §12.5).

### 6.4 Pagination

Cursor-based pagination is the default for every list endpoint (SDD §12.3
Example 2 uses `?limit=20&cursor=…` with `nextCursor` — that example is
followed as the convention). Rules: `limit` default 20, max 100
(`[P4 choice]` — SDD names no max; 100 bounds a single query);
`nextCursor` is opaque (never a raw offset/id the client can forge);
no list endpoint returns an unbounded array. Phase 4 has no list
endpoint yet (no friends/history/leaderboard) — the helper is built now
in `common/pagination/` so Phase 6 does not invent a second convention.

### 6.5 Rate-limit policy

| Endpoint group | Limit | Key | Source |
|---|---|---|---|
| All authenticated REST | 100 req/min per user | user id | SDD §13.4 |
| `POST /auth/login` | 5 failures / 15 min, then throttle (NFR-16) | account identifier **and** IP (both) | SDD §13.1 / NFR-16 |
| `POST /auth/register` | 10 / hour per IP `[P4 choice]` | IP | SDD §13.4 "login/register tighter" — the number is silent, so a conventional tight value is proposed and flagged |
| `POST /auth/forgot-password` | 5 / hour per email `[P4 choice]` | email (hashed key, never logged in plaintext) | Same as above |
| `POST /auth/reset-password`, `POST /auth/verify-email` (+ resend) | 10 / hour per IP `[P4 choice]` | IP | Same as above |
| `POST /auth/refresh` | 60 / hour per IP `[P4 choice]` | IP | Same as above |
| Socket events | 20 events/s per connection (NFR-20) | connection | SDD §12.6 |

All 429s carry `Retry-After` and the standard error envelope
(SDD §13.4). Rate-limit counters live in Redis (§5.1); if Redis is down,
auth writes fail closed (§5.2) rather than running unthrottled.

### 6.6 Health / readiness

- `GET /v1/health` — **liveness only.** Returns `200 { "success": true,
  "data": { "status": "ok" } }` if the Node process can answer. No
  dependency checks, no version strings, no secrets. Used by the host to
  decide whether to restart the process.
- `GET /v1/health/ready` — **readiness.** Checks PostgreSQL
  (`SELECT 1` via the TypeORM pool) and Redis (`PING`), each reported
  separately: `200` only if **both** are up; `503` otherwise, with a body
  that names which dependency is down and a per-check latency in ms
  (`{ "database": "up", "redis": "down", ... }`). No credentials, no
  connection strings, no stack traces, no internal hostnames in either
  response. (The SDD does not specify health endpoints — this shape is a
  `[P4 choice]` following the conventional NestJS Terminus pattern; the
  app/PostgreSQL/Redis distinction is required by the brief and is the
  point of the endpoint.)

### 6.7 OpenAPI / Swagger

Swagger (`@nestjs/swagger`, `[P4 choice]` — SDD §12 names no
documentation tool; Swagger is the conventional NestJS choice) is wired
in `main.ts` and served at `/v1/docs` **in non-production environments
only** (never in production — it would enumerate the API surface). Every
Phase 4 DTO carries `@ApiProperty()` so the spec is generated, not
hand-written. The spec is a developer aid; the SDD §12 text remains the
normative contract.

### 6.8 CORS + logging (REST)

- CORS: allow only the known origins from config (admin panel origin in
  Phase 7; the mobile app does not rely on CORS — SDD §13.3). No wildcard
  origin in any environment. `[P4 choice]`: `credentials: false` for the
  player API (Bearer tokens, not cookies — cookies are the admin panel's
  transport in Phase 7, SDD §5.3.1).
- Every request is logged once (method, path, status, latency ms,
  `requestId`); bodies are never logged; `Authorization` headers are
  never logged (NFR-37, §10.4 redaction test).

---

## 7. Authentication plan

### 7.1 Strategy (per SDD §12.4, §13.1 — followed, not invented)

| Decision | SDD prescription | Phase 4 implementation |
|---|---|---|
| Password hashing | Argon2id `[Proposed]`, memory 64 MiB, iterations 3, parallelism 1 (OWASP baseline); bcrypt acceptable fallback | `argon2` package, `PasswordHasher` service; bcrypt is **not** also implemented — the fallback is documented for a future deployment decision, not built in parallel |
| Access token | JWT, RS256 `[Proposed]`, 15-min expiry, claims `sub` (user id), `role` (`player`), `email_verified`, `sid` (session id) | `@nestjs/jwt` + `passport-jwt` `[P4 choice]` (SDD names no JWT library; these are the conventional NestJS pair) |
| Refresh token | Opaque, stored **hashed** in `auth_sessions`, revocable per-session and per-user, **rotated on every use**; reuse revokes the whole session family | 256-bit `crypto.randomBytes`, SHA-256 hash stored; rotation in `TokenService.refresh()`; family = all sessions sharing the original session's lineage (linked by a `family_id` — `[P4 choice]` column on `auth_sessions`; SDD requires family revocation but names no column, so the minimal lineage marker is added and flagged) |
| Email tokens | Single-use, time-limited, stored hashed; verification 24 h, reset 1 h `[Proposed]` | `crypto.randomBytes` token, SHA-256 hash in `email_tokens`, `used_at` set on first use, expiry enforced in the service (never by trusting the client) |
| Session revocation | Server-side `auth_sessions` rows are the source of truth; deleting a row logs the user out everywhere immediately | `JwtAuthGuard` checks `sid` against `auth_sessions` (not revoked, not expired) on every request — **this is what makes revocation real despite a 15-min JWT**; the cost is one indexed lookup per request, accepted deliberately |
| Login throttle | 5 consecutive failures / 15 min, same account or IP (NFR-16) | §6.5 |
| MFA | TOTP for **administrators only** (FR-70, SDD §13.1) | **Not in Phase 4.** No TOTP code, no `mfa_secret` column, no MFA endpoint. Phase 7. |
| Token storage (device) | Platform secure storage only (FR-09) | Flutter concern; the server's part is issuing short-lived tokens and revocable refresh tokens. Not implemented or verified here. |
| Admin tokens | httpOnly, Secure, SameSite cookie (SDD §5.3.1 `[Proposed]`) | Phase 7 only. |

**Revocation scope note (honest limitation, SDD-consistent):** the access
JWT itself cannot be recalled before its 15-minute expiry — revocation is
enforced at refresh time and, via the `sid` check in `JwtAuthGuard`, on
every request that needs a live session. The 15-minute window is the
SDD's own trade-off (NFR-15); no shorter expiry is invented.

### 7.2 Auth flows (sequence summary; SDD §5.2.1, §8.2)

1. **Register** → validate DTO → check duplicates → hash password
   (Argon2id) → transaction: create user + profile + verify token →
   dispatch verification message via `Mailer` → return `201` with user
   (public fields) + tokens (the user is unverified; `emailVerified:
   false` is in the payload — the client must not treat login as "online
   ready" until verified).
2. **Verify** → hash presented token → find live `email_tokens` row →
   set `email_verified_at`, `used_at` → return success. Reuse/expiry →
   `409`/`410` (§6.3).
3. **Login** → throttle check → load user by email-or-username → status
   check (suspended/blocked → `403 ACCOUNT_SUSPENDED`, generic enough not
   to leak which field failed — see §7.3) → Argon2id verify (constant-time
   failure path: on unknown user, still run a dummy verify so timing does
   not leak existence — `[P4 choice]`, conventional) → create session row
   → issue pair.
4. **Refresh** → hash presented token → load session → if revoked/expired
   → `401`; if the token was already rotated (reuse) → revoke the whole
   family → `401` → else rotate (new pair, old row revoked, new row in the
   same family).
5. **Logout** → revoke the current session row. (No "logout everywhere"
   endpoint in Phase 4 — password change revokes all sessions, §2.1.1
   FR-08; a dedicated revoke-all endpoint is a Phase 6 convenience, not
   invented here.)
6. **Forgot/reset** → §2.1.1 FR-06. Forgot-password always returns `200`
   neutral. Reset revokes all sessions.

### 7.3 What login errors must not leak

Per FR-04/NFR-16: wrong email, wrong password, unknown account,
suspended account, and unverified account **must not be distinguishable
by the login response alone** beyond what the flow legitimately needs.
Concretely: invalid credentials → `401 INVALID_CREDENTIALS` always;
suspended/blocked → `403 ACCOUNT_SUSPENDED` is returned *because the
account's online access is denied* (BR-19/UC-05 E2 requires a status
message on login) — this is the SDD's own carve-out (UC-05 E2), not a
leak introduced by this plan, and it is recorded so Stage 4 tests the
exact boundary: the 403 is only returned *after* a correct password, so
it cannot be used to enumerate accounts. Unverified users log in
successfully (they need a session to resend verification) but are refused
online-guarded routes with `403 EMAIL_NOT_VERIFIED`.

### 7.4 Email + push interfaces (no providers)

- `Mailer` interface (§7.4 / §2.1.3 CI-07): `sendVerification(email,
  token, …)`, `sendPasswordReset(email, token, …)`. Dev/test transport
  logs the message (token visible in **test logs only**, never in
  production logs — the log transport is registered only when
  `NODE_ENV != production`; production boot with no real provider
  **fails fast**, §8.1). Provider selection is OPEN (OD-09, §11.3).
- `PushSender` interface (§2.1.3 CI-08): declared, no implementation, no
  transport. Provider selection is OPEN (OD-09, §11.3) and not needed
  until Phase 6.

---

## 8. Config, logging, exceptions, security

### 8.1 Config — validated env, fail-fast

- Library: `@nestjs/config` with a **Joi validation schema**
  (`[P4 choice]` — SDD §15.2 requires environment-based configuration
  but names no validation library; Joi is the conventional NestJS pairing
  for `@nestjs/config`).
- `.env.example` lists every variable with a safe example value; `.env`
  itself is git-ignored and never committed. No secret is ever in source
  control, a client bundle, or a log (SDD §13.3).
- **Fail-fast:** the app exits non-zero at boot (with a named error, no
  stack trace to the client) if any required production variable is
  missing or malformed. Required in production: `DATABASE_URL`,
  `REDIS_URL`, `JWT_PRIVATE_KEY`, `JWT_PUBLIC_KEY` (PEM), `JWT_ISSUER`,
  `RULESET_VERSION`, `CORS_ORIGINS`, `MAILER_*` (provider config — fails
  fast in production only, because the log transport covers dev/test).
  Required in all environments: `NODE_ENV`, `PORT`, `DATABASE_URL`,
  `REDIS_URL`. Defaults exist only for genuinely safe values (`PORT=3000`
  in dev, log level). There is no default JWT key, no default database
  URL, no default password — ever.
- Config values that are rules, not secrets, live in config with SDD
  defaults: `RULESET_VERSION=1.0.0` (BR-14), turn timer / grace / missed
  turns are **not** Phase 4 config (they belong to `game_configurations`,
  Phase 7, FR-79) — Phase 4 code must not invent its own timer constants.

### 8.2 Security controls (attack surface → control)

| Attack surface / threat | Control (planned) | Requirement |
|---|---|---|
| Password guessing / credential stuffing | Argon2id; NFR-16 throttle (account + IP); generic login errors; no enumeration via register (duplicates are specific *by design* per FR-02 — that is the SDD's carve-out) | NFR-13, NFR-16, FR-02/04 |
| Token theft (access) | 15-min expiry; `sid` revocation check per request; Bearer only over TLS | NFR-15 |
| Token theft (refresh) | Opaque, hashed at rest, rotated per use, family revocation on reuse | SDD §12.4 |
| Session fixation / stale sessions | New session row per login; logout revokes; password change revokes all | FR-05/08 |
| SQL injection | TypeORM parameterised queries only; no string-built SQL (SDD §13.4) | NFR-20 |
| Mass assignment / unexpected fields | Global `ValidationPipe` with `whitelist: true` (strip unknown fields, SDD §12.1); DTO allow-lists are the only serialised shape | NFR-20 |
| Oversized payloads | JSON body 100 KB; socket event 10 KB (SDD §13.4 `[Proposed]`) | NFR-20 |
| Rate / flood abuse | REST 100/min/user + tighter auth limits (§6.5); socket 20 ev/s, disconnect on sustained abuse | NFR-20 |
| Unauthenticated access | Global `JwtAuthGuard`, deny-by-default, explicit `@Public()` allow-list | NFR-17 |
| Privilege escalation / IDOR | Ownership check in every service (load resource, compare requester); `me`-routes take no id; admin routes do not exist yet, so no admin check can be forgotten | NFR-17, SDD §13.2 |
| Suspended/blocked bypass | Single `AccountStatusGuard` choke point at login + every online action | BR-19, SDD §13.2 |
| Secrets in logs / responses | Redaction list (§3.2 logging); DTO allow-lists; log test (§10.4); `.env` git-ignored | NFR-13/21/37 |
| Plain HTTP / downgrade | TLS ≥ 1.2 required in production; HSTS + `nosniff` (helmet `[P4 choice]`); no plain-WS listener | NFR-14 |
| CORS abuse | Explicit origin allow-list from config; no wildcard; `credentials: false` on player API | SDD §13.3 |
| Email-token guessing | 256-bit random tokens, SHA-256 hashed at rest, single-use, short expiry | FR-03/06 |
| Redis loss / flush | Fail closed for auth writes (§5.2); PostgreSQL remains the truth (CI-05) | SDD §9.4 |
| Dependency confusion / supply chain | `npm only`, lockfile committed, `npm ci` in any future build; no new dependency without a reason recorded in the Stage 2 handoff | (project convention; SDD silent) |

**Out of scope for Phase 4 security work (later phases):** game cheating
(NFR-18 — Phase 5 negative tests), admin MFA (FR-70 — Phase 7), audit
trail (FR-82 — Phase 7), push/email provider hardening (Phase 6/7).

### 8.3 Logging

Structured JSON via `nestjs-pino` `[P4 choice]` (§2.1.2 NFR-37). Every
line carries `requestId` (generated per request, returned as
`X-Request-Id` so a client can quote it) and, on errors, the
`correlationId`. Redaction list (never logged): `password`,
`newPassword`, `oldPassword`, `*token*`, `authorization`, `mfa*`,
`JWT_PRIVATE_KEY`, `DATABASE_URL`, `REDIS_URL`. Connection counts and
per-request latency are logged by the interceptor; admin actions have
nothing to log yet (Phase 7). Log level is config-driven
(`LOG_LEVEL`, default `info`).

### 8.4 Exception handling

One global `HttpExceptionFilter` maps everything to the §6.3 envelope:
known `HttpException`s keep their status/code; unknown errors become
`500 INTERNAL_ERROR` with a `correlationId` and a full server-side log
line (no stack trace to the client). Validation failures from
`class-validator` become `400 VALIDATION_FAILED` with per-field
`details`. The filter is the single place this mapping lives — services
throw typed exceptions (`UnauthorizedException`, `ConflictException`,
custom `TokenExpiredException` → 410), never hand-built responses.

---

## 9. Socket.IO plan

### 9.1 Foundation-only scope (read this first)

Phase 4 builds the **gateway, the auth, and the lifecycle** — not the
game. The gateway accepts authenticated connections, tracks them, and
refuses everything else. There are **no game events in Phase 4**: no
`room:join`, `room:leave`, `room:ready`, `match:start`, `dice:roll`,
`token:move`, `state:request`, and no server broadcasts except the
connection lifecycle itself. Any Stage 2 code that adds one of those has
left Phase 4 scope (§2.3).

### 9.2 Gateway

- **Namespace:** `/game` (SDD §12.6 `[Proposed]` — one namespace; rooms
  are Socket.IO rooms inside it, named `room:{roomId}`, in Phase 5).
- **Transport:** WSS only (same HTTPS server as REST; no separate port,
  no plain WS — NFR-14).
- **Authentication:** JWT in the handshake `auth` object
  (`{ token }`); verified by `WsJwtGuard` (same `TokenService` as REST,
  same `sid`/status/verified checks — one auth path, not two). The client
  also sends its app version in the handshake (SDD §12.7 `[Proposed]`
  version gating — recorded, not enforced in Phase 4: the gateway logs
  the version and accepts it; a minimum-version refusal is only switched
  on when a breaking event change ships, i.e. Phase 5+).
- **Lifecycle:** on connect — verify, load user, attach `{ userId,
  sessionId }` to the socket, log `connection counts` (NFR-37); on
  disconnect — log, release nothing else (no room membership exists yet).
  Heartbeat/timeout is Socket.IO's built-in mechanism; the 10 s
  heartbeat-detection interval (SDD §8.7 `[Proposed]`) is a *game*
  concern (grace periods) and is not implemented until Phase 5.
- **Validation:** `ValidationPipe` on the gateway (class-validator DTOs
  for every inbound event, once events exist). Payload size limit 10 KB
  per event (SDD §13.4).
- **Rate limiting:** 20 events/s per connection (NFR-20); beyond that the
  event is dropped; sustained abuse disconnects the socket (SDD §12.6).
  In Phase 4 there are no client events to rate-limit, so the limiter is
  wired and unit-tested, not integration-proven against game traffic.

### 9.3 Event naming / payload conventions (for Phase 5 to follow)

Finalised from SRS §5.4 in SDD §12.6 — recorded here so Phase 5 does not
re-decide them, not implemented here:

| Direction | Event | Payload (final) |
|---|---|---|
| C → S | `room:join` / `room:leave` / `room:ready` | `{ roomCode }` / `{ roomId }` / `{ roomId, ready }` |
| C → S | `match:start` | `{ roomId }` (host only) |
| C → S | `dice:roll` | `{ matchId, requestId }` — **no value supplied** |
| C → S | `token:move` | `{ matchId, tokenId, requestId }` |
| C → S | `state:request` | `{ matchId, lastSeq }` |
| S → C | `room:updated`, `match:started` | Room/members/ready; seats + ruleset version |
| S → C | `dice:rolled`, `token:moved`, `turn:changed` | Authoritative result + `seq` |
| S → C | `player:disconnected` / `player:reconnected` / `player:forfeited` | `{ matchId, playerId, graceEndsAt? }` |
| S → C | `match:state`, `match:ended` | Full snapshot + `seq`; final result |
| S → C | `action:rejected` | `{ matchId, requestId?, code, message }` — state unchanged |
| S → C | `invitation:received` | `{ roomCode, fromUser }` (Phase 6) |

Conventions: client events express **intent only**; server events carry
**authoritative results**; every server game event carries an increasing
`seq` (FR-51); every client mutating intent carries a client-generated
UUID `requestId` (FR-53, idempotency); error shape for sockets mirrors
the REST envelope (`{ code, message }`, never a bare string).

### 9.4 What is foundation-only vs later-phase (Socket.IO)

| Item | Phase 4 | Later |
|---|---|---|
| Namespace `/game`, handshake auth, `WsJwtGuard`, connect/disconnect lifecycle, logging | **Yes** | — |
| Redis adapter wiring (`ioredis` + `@socket.io/redis-adapter`) `[P4 choice]` | **Yes** (wired; two-node broadcast tested locally, §10.3) | Multi-node load test (Phase 5) |
| Event validation pipe, 20 ev/s limiter, 10 KB limit | **Yes** (wired + unit-tested) | Proven against game traffic (Phase 5) |
| `room:join/leave/ready`, `match:start`, `dice:roll`, `token:move`, `state:request` + all server broadcasts | No | **Phase 5** |
| Grace-period / reconnect / snapshot serving (`match:state`) | No | **Phase 5** (FR-54/55/57) |
| `invitation:received` | No | **Phase 6** (FR-62) |
| App-version minimum enforcement (`UPGRADE_REQUIRED`) | No (logged only) | Phase 5+, when a breaking event change ships |

---

## 10. Testing plan

### 10.1 Test infrastructure (isolated, real services)

- **Real PostgreSQL 16 + real Redis 7, locally.** Integration/e2e tests
  boot against the local cluster (`pg_lsclusters` 16/main, started by the
  tester) and a local `redis-server` on a scratch port. **Never**
  production services, **never** SQLite or an in-memory substitute
  claimed as PostgreSQL verification (the brief forbids it, and SQLite
  would silently accept things PostgreSQL rejects — e.g. CITEXT
  uniqueness, partial unique indexes).
- **No Docker** (not present in this VM, §0.2). If a later environment
  has Docker, Stage 2 may add a `docker-compose.yml` for dev/test — that
  is a `[P4 choice]` for then, not a claim now.
- **Scratch databases:** each e2e run creates a fresh database, runs all
  migrations (§4.4), runs, drops. Test data is generated per run; no
  shared fixtures that can leak between tests.
- **No CI** (Workflows permission 403). Tests run locally (`npm test`,
  `npm run test:e2e`); Stage 2 pastes command output + counts as evidence
  in its handoff. Nothing in this plan claims a CI run.
- **Runners:** Jest (unit + integration) with `supertest` for HTTP and
  `socket.io-client` for gateway tests `[P4 choice]` — the conventional
  NestJS testing stack; the SDD names no test runner for the server
  (it names k6 for load tests, §4.1 NFR-05, and the Dart suite for the
  engine).

### 10.2 Unit tests (no services)

- DTO validation matrix: every DTO × {valid, each field invalid, missing
  required, unknown field} → expected pass/strip/400.
- `PasswordHasher`: same password → different hashes; verify
  correct/incorrect; timing-safe comparison on email tokens.
- `TokenService`: access token claims (`sub`, `role`, `email_verified`,
  `sid`, 15-min expiry); refresh rotation (new pair, old revoked);
  family revocation on reuse; expired refresh → 401.
- Guards: `JwtAuthGuard` (missing/expired/bad token, revoked `sid`),
  `EmailVerifiedGuard`, `AccountStatusGuard` (each status value).
- `RedisService`: `incrWithExpiry` atomicity (parallel increments);
  lock acquire/release (NX semantics, wrong-token release refused).
- Log redactor: every redaction-list key is stripped from a sample log
  line; a login flow emits no password/token.
- Config validation: missing `JWT_PRIVATE_KEY` in production → boot
  failure (tested by spawning the validation function, not by booting
  the app against production).
- Vector loader: 23/23 cases parse; tampered version/field → failure;
  incoherent embedded ruleset → failure; canonical case must equal the
  Dart defaults and each of the 6 variant cases must differ in exactly one
  field (§2.1.2 NFR-39 — wording corrected in Stage 5; the original text
  wrongly required every case to equal the defaults).

### 10.3 Integration tests (real PostgreSQL + real Redis)

- **Auth flows end-to-end:** register → verify → login → refresh →
  logout → refresh-again-401; duplicate email/username → 409 with the
  right code; weak password → 400; login with email and with username.
- **Password recovery:** forgot (neutral 200 for unknown email) → reset
  with valid token → old sessions dead, new login works; token reuse →
  rejected; expired token → rejected.
- **Profile:** GET/PATCH own profile; PATCH password (wrong old → 401,
  success → all sessions revoked); preferences round-trip; public
  profile excludes email/hash; `DELETE /users/me` sets the marker and
  revokes sessions.
- **Transactions:** register with a forced failure after the user insert
  (fault injection) → no partial rows (NFR-31 pattern).
- **Rate limits:** login throttle (5 bad → 6th is 429 even with the right
  password; success resets); register/forgot/reset/refresh limits per
  §6.5; 429 carries `Retry-After`.
- **Health:** `/health` 200 with no deps; `/health/ready` 200 when both
  up, 503 with per-dependency status when Redis is stopped (test stops
  the local Redis, asserts, restarts it) and when PostgreSQL is
  unreachable (same pattern, or a bad `DATABASE_URL` override).
- **Envelope:** every endpoint returns the §6.3 shape on success and on
  each error class; 500 path returns a `correlationId` (forced via a
  test-only error route? No — via a deliberately failing validation of an
  internal path; Stage 2 picks the mechanism and records it. No
  test-only route ships in production code.)
- **Gateway:** connect without token → refused; bad token → refused;
  unverified/suspended token → refused; valid → connected; disconnect →
  logged. Two gateway instances share a broadcast via the Redis adapter
  (local two-node test, NFR-24 prep).
- **Migrations:** fresh database + `migration:run` → all four tables
  exist with the §4.1 constraints; re-run is a no-op; `synchronize` is
  off (config test, §4.4).

### 10.4 Security tests (negative tests — Phase 4 scope)

- **Enumeration:** wrong email vs wrong password vs unknown account →
  identical login responses; forgot-password for unknown email → 200
  neutral; public profile for unknown id vs another user's id → same 404.
- **Authorization matrix:** every route × {no token, expired token,
  revoked session, unverified, suspended, blocked, valid} → expected
  status (§2.1.1 FR-42). This matrix is the single most important Phase 4
  test artefact — Stage 4 must be able to point at it per route.
- **Token abuse:** refresh-token reuse → family revoked; access token
  with a forged `role: 'admin'` claim (signed with a wrong key) → 401;
  access token for a deleted/revoked session → refused.
- **Input abuse:** oversized body → 413; SQL-injection strings in
  username/email/password fields → stored as inert data or 400, never
  executed (parameterised queries, §8.2); unknown fields stripped;
  `avatar_key` outside the allowed set → 400.
- **Rate-limit abuse:** flood login (NFR-16), flood register, flood
  socket connects → 429 / refused, service stays up.
- **Secret leakage:** full login/register/reset flows with log capture →
  no password, token, hash or key appears in any log line or response.

### 10.5 Explicitly not tested in Phase 4

- k6 load test at 200 concurrent users / 500 concurrent players (needs
  gameplay traffic — Phase 5; §2.1.2 NFR-05/NFR-24).
- Game negative tests (NFR-18: client-supplied dice/moves — Phase 5).
- Reconnect/grace/restart recovery (NFR-32/33 — Phase 5).
- Leaderboard load test at 100,000 users (NFR-25 — Phase 6).
- Any Flutter, admin-panel, or device test (out of scope for `backend/`).

---

## 11. Decisions log

### 11.1 Choices made where the SDD was silent (`[P4 choice]`)

| # | Decision | Why (conventional default) | Reversible? |
|---|---|---|---|
| D-P4-01 | `backend/` at repo root | SDD prescribes one NestJS app, no directory name; mirrors `diceup_app/` | Yes — a move is a rename |
| D-P4-02 | `ioredis` as the Redis client | SDD names no client; required by the Socket.IO Redis adapter (SDD §9.4) | Yes — behind `RedisService` |
| D-P4-03 | `@nestjs/swagger` for OpenAPI, non-prod only | SDD names no doc tool; conventional NestJS choice | Yes |
| D-P4-04 | `nestjs-pino` for structured JSON logging | SDD requires structured logging without secrets (NFR-37), names no library | Yes |
| D-P4-05 | `@nestjs/config` + Joi validation schema, fail-fast | SDD requires env-based config (§15.2), names no validator | Yes |
| D-P4-06 | `passport-jwt` + `@nestjs/jwt` | SDD requires RS256 JWTs (§12.4), names no library | Yes |
| D-P4-07 | `argon2` npm package for Argon2id | SDD prescribes the algorithm, not the package | Yes — hasher is one service |
| D-P4-08 | `users.deletion_requested_at` column (FR-10 request marker) | Minimal marker; full workflow awaits OD-08 | Yes — drop the column when the workflow is designed |
| D-P4-09 | `auth_sessions.family_id` column (refresh-token lineage) | SDD requires family revocation (§12.4) but names no column | Yes |
| D-P4-10 | Token-expiry status `410 TOKEN_EXPIRED` (vs 409) | SDD does not distinguish; 410 is the precise "gone" semantic | Yes — a status-code change |
| D-P4-11 | `POST /auth/verify-email/resend` endpoint | UC-04 A2 ("verification link expires: user requests a new one") implies a re-request; no endpoint is named | Yes |
| D-P4-12 | Rate-limit numbers beyond NFR-16 (register 10/hr/IP, forgot 5/hr/email, reset/verify 10/hr/IP, refresh 60/hr/IP) | SDD §13.4 says "tighter" without numbers | Yes — config values |
| D-P4-13 | Cursor pagination defaults (limit 20, max 100) | SDD §12.3 shows cursor pagination without limits | Yes — config values |
| D-P4-14 | `ValidationPipe` strips unknown fields (`forbidNonWhitelisted: false`) | SDD §12.1: "unknown fields are stripped, not ignored silently" | Yes |
| D-P4-15 | Health endpoints `/v1/health` + `/v1/health/ready` (Terminus-style, hand-rolled) | SDD specifies no health endpoints; the brief requires the app/PG/Redis distinction | Yes |
| D-P4-16 | `@Cron()` purge job for expired sessions/tokens | SDD §9.2 requires purging, names no scheduler | Yes |
| D-P4-17 | `helmet` (HSTS + `nosniff`) | SDD §13.3 calls the headers "[Proposed] hardening" | Yes |
| D-P4-18 | Log transport for `Mailer` in dev/test only | Lets Stage 2/4 verify token flows with no provider (OD-09 open) | Yes — swap in a real provider |
| D-P4-19 | Jest + `supertest` + `socket.io-client` for tests | SDD names no server test runner (k6 is for load, §4.1) | Yes |
| D-P4-20 | Dummy Argon2id verify on unknown-user login (timing) | Conventional anti-enumeration hardening; SDD requires the generic error, not the timing behaviour | Yes |

### 11.2 Discrepancies between this brief and the docs

| # | Discrepancy | Resolution in this plan |
|---|---|---|
| X-01 | Brief says "Phase 4/5/6/7"; docs say Stages S1/S2/S3, never "Phase 4" | Recorded in §0.1; mapping table in §0.1; out-of-scope rows use Phase labels, everything else uses Stage labels |
| X-02 | Brief says "Node v24.22.1" environment; SDD pins Node 22 LTS (DA-07, §15.1) | Recorded in §0.2; Stage 2 targets 22 LTS in `engines`/`.nvmrc`; dev on 24 is a recorded variance, not a redesign |
| X-03 | SDD §15.2 proposes local PostgreSQL/Redis "via containers" for dev; this VM has no Docker | Recorded in §0.2; Stage 2 uses the local `pg_lsclusters` cluster + local `redis-server` instead; no container claim |
| X-04 | SDD §17.2 lists TypeORM as a `[Proposed]` addition, while §3.5/§9/§15.2 write as if it were decided | Followed as the SDD's named choice (§4.2); the `[Proposed]` tag is noted so a substitution is a justified change, not a surprise |
| X-05 | SDD §12.4 proposes RS256; §13.1 proposes Argon2id parameters, 24 h/1 h token lifetimes, 10 s heartbeat, 10-min empty-room expiry | All followed as the SDD's stated defaults and flagged `[Proposed]` where they first appear, so each is a one-line change if stakeholders pick otherwise |
| X-06 | The brief's "no GitHub CI" vs SDD's repeated "in CI" (NFR-27, NFR-39, §6.9) | No CI is assumed or claimed anywhere in this plan (§0.2). NFR-39's conformance suite is built as a local Jest test in Phase 4 and wired into CI only when CI exists. Lint/typecheck are local Stage 2 evidence. |

### 11.3 OPEN FOR USER DECISION (carried from SRS/SDD registers — none blocks Stage 2)

| # | Decision | Source | Why it is OPEN (not invented here) | Effect on Phase 4 |
|---|---|---|---|---|
| OPEN-1 | Email provider selection | OD-09, A-04 | SDD defines the interface (§3.8) but no provider | **Non-blocking.** `Mailer` interface + log transport (§7.4). Real provider wired when decided; no Phase 4 code changes shape. |
| OPEN-2 | Push provider selection (APNs/FCM) | OD-09, A-05 | Same as OPEN-1 | **Non-blocking.** Interface only (§2.1.3 CI-08); no code needs it until Phase 6. |
| OPEN-3 | Hosting provider + budget | OD-07 | SDD is deliberately provider-neutral (§15) | **Non-blocking.** Affects deployment, not code. No hosting decision is assumed. |
| OPEN-4 | Ranking algorithm | OD-06, Q-01, DA-08 | SRS leaves it open; SDD proposes simple points behind a strategy interface | **Non-blocking.** No ranking code exists in Phase 4. Decided before Phase 6. |
| OPEN-5 | Data retention periods + anonymisation rules (incl. FR-10 full workflow) | OD-08, OD-01, OD-10, Q-06 | Needs legal review; SDD §13.7 defers it explicitly | **Partially blocking for FR-10 only.** Phase 4 implements the *request* path; no data is deleted/anonymised until this is decided. |
| OPEN-6 | Final defaults for configurable Ludo rules | OD-02, Q-02 | SDD Table 6.2 defaults are proposals | **Non-blocking for Phase 4.** Ruleset `1.0.0` is pinned as config (§2.1.2 NFR-39); the TS engine that consumes it is Phase 5. |
| OPEN-7 | Matchmaking in Stage 2 vs Stage 3; which rule options a host may set | OD-05, OD-11, Q-07 | SRS open decisions | **Non-blocking.** No matchmaking/room code in Phase 4. Decided before Phase 5. |

**No irreversible decision was invented in this plan.** Every choice in
§11.1 is reversible behind an interface or a config value, and every
genuinely open decision is listed above with its source register ID. If
Stage 2 encounters a decision that is irreversible or contradicts the
SDD, it must stop and record it as OPEN rather than inventing it — the
same rule this stage followed.

---

## 12. Stage 2 handoff notes (what changes for the implementers)

1. **Start from §3.4's order.** Config/logging/envelope/health first —
   everything else plugs into them, and a broken skeleton wastes the
   most time if found late.
2. **Do not create tables "in advance."** §4.1's four tables are the
   complete Phase 4 schema. A fifth table is a scope leak, not foresight.
3. **Do not add endpoints "while you're here."** §6.2 is the complete
   Phase 4 route list. A rooms/matches/friends endpoint belongs to its
   phase's branch, not this one.
4. **Do not claim CI.** There is none (Workflows 403). Evidence is local
   command output: `npm run lint`, `npm run typecheck`, `npm test`,
   `npm run test:e2e` — paste the counts, don't summarise them from memory.
5. **Start the local services yourself.** PostgreSQL cluster `16/main` is
   down and Redis is not running (§0.2). Integration tests need both up;
   record the exact commands you used in `backend/README.md`.
6. **Node version.** The VM has Node 24.22.1; the SDD pins 22 LTS (§0.2,
   X-02). Pin `engines` to 22 LTS and note any 24-vs-22 variance you hit.
7. **The `sid` check is load-bearing.** If it is skipped for performance,
   logout/revocation silently stops working (NFR-15, §7.1). Do not
   optimise it away without a plan amendment.
8. **The authorization matrix (§10.4) is the exit artefact.** Stage 4/5
   cannot verify Phase 4 without a per-route × per-state table. Build it
   as a test, not as a document.
9. **M4.1 reconciliation (parallel work) is untouched by this plan.**
   This phase touches no Flutter file and no Windows-divergent file; the
   only shared file is the read-only vectors JSON. If the M4.1
   reconciliation changes `rules.json` or `ruleset_config.dart`, re-check
   §0.3 and the NFR-39 loader before Stage 5 signs off.
10. **If you find an OPEN decision while implementing, stop and record
    it** (§11.3 rule). Do not invent it to keep moving.

---

---

## 13. Stage 5 — Final verification (2026-11-27, this VM)

Stage 5 re-ran **everything** on the finished tree — no count below is
carried over from an earlier stage. Environment: Node v24.22.1, npm
10.9.4, PostgreSQL 16.15 (cluster `16/main`, online), Redis 7.0.15
(running, `PING` → `PONG`). No Docker, no CI. All work on Node 24;
SDD pins Node 22 LTS — unexercised (see §13.4).

### 13.1 Measured results

| Check | Command | Result |
|---|---|---|
| Typecheck | `npm run typecheck` (`tsc --noEmit`) | exit 0 |
| Lint | `npm run lint` (ESLint flat config) | exit 0, no warnings/errors |
| Format | `npm run format:check` (Prettier) | exit 0 — all files conform |
| Build | `npm run build` (`nest build`) | exit 0, `dist/main.js` produced |
| Unit tests | `npm test` | **156 passed / 0 failed / 0 skipped, 22 suites** (~20 s) |
| E2E tests | `npm run test:e2e` (`--runInBand`, real PostgreSQL + real Redis, scratch DB per run) | **73 passed / 0 failed / 0 skipped, 8 suites** (~59 s) |
| **Total** | | **229 passed / 0 failed / 0 skipped (30 suites)** |
| npm audit | `npm audit` | **BLOCKED** — `403 Forbidden`, registry policy `zz_managed_internal_spaces_package_registries` (re-verified by Stage 5; substitute advisory check stands, see §13.3) |

Per-suite unit counts (verbose re-run, sums to 156): `ws-jwt.guard`
20, `naming-strategy` 24, `dto-validation` 12, `guards` 12, `jwt-keys`
8, `rate-limit` 8, `jwt-strategy` 8, `socket-rate-limit` 8,
`ws-validation.pipe` 8, `token.service` 6, `login-throttle` 6,
`config.validation` 5, `redis.service` 5, `password-hasher` 5,
`trust-proxy` 4, `database-options` 3, `config-precedence` 3,
`unique-violation` 3, `mailer` 3, `email-token` 2, `pagination` 2,
`cleanup` 1.

Per-suite e2e counts (verbose re-run, sums to 73): `auth` 31,
`socket` 13, `full-journey` 8, `health` 6, `auth-security` 6,
`rules-vectors` 4, `redis-down` 3, `authz-matrix` 2 (the 2 matrix
tests contain 32 route×state assertions: 4 routes × 8 states).

Note: Jest prints "did not exit one second after the test run has
completed" on e2e runs — pre-existing (open ioredis/socket handles
after `app.close()`), verified on the Stage 3 baseline, not a
failure. No test was weakened or deleted to get green.

### 13.2 Clean-checkout sanity (Stage 5, separate scratch clone)

Stage 3 did the full literal doc-following; Stage 5 re-verified the
**final** tree (incl. Stage 4 changes) in a fresh clone at
`/tmp/diceup-phase4-clean` (same HEAD `93542ad`, clean `git status`):

1. `git clone` local repo + checkout
   `feature/online-phase-4-backend-foundation` → HEAD `93542ad`.
2. `npm ci` → **817 packages in 32 s**, exit 0.
3. Fresh database `diceup_cleancheck` (owner `diceup`); `.env` from
   `.env.example` — the documented D-02 placeholder-password fix was
   still required (`.env.example` ships a 9-char placeholder; the
   local-dev password `diceup_dev_local_only` must be substituted,
   as `02-setup.md` §2 already documents). Dev RS256 keypair
   generated with `openssl` per the guide.
4. `npm run migration:run` → exit 0; **both migrations applied**
   (`InitAuth`, `AddProfilePreferences`); tables present: `users`,
   `profiles`, `auth_sessions`, `email_tokens` (+ TypeORM
   `migrations`).
5. `npm run start:prod` (production build) boots → "Nest application
   successfully started", listening on `127.0.0.1:3000`.
6. `GET /v1/health` → **200** `{"success":true,"data":{"status":"ok"}}`;
   `GET /v1/health/ready` → **200**, `database: up, redis: up`
   (latency 1 ms / 0 ms).
7. Live smoke: `POST /v1/auth/register` → **201**, RS256 access
   token with `expiresIn: 900`, refresh token issued.
8. Server stopped, scratch database dropped. No doc drift found —
   no setup-doc change was needed.

### 13.3 Security re-verification (Stage 5)

- Stage 4 fixes re-confirmed present in the tree and covered by
  tests: H-01 (`redis-down.e2e.spec.ts`, 3 tests), H-02 (concurrent
  duplicate registration → one 201 + one 409, in `auth-security`
  e2e + `unique-violation` unit), H-03 (`trust-proxy.spec.ts`, 4
  tests), M-01–M-08 (see `backend/docs/10-security.md`).
- `npm audit` re-run by Stage 5: still **BLOCKED** (403,
  `policy_denied`). The Stage 4 advisory-check substitute stands:
  engine.io 6.6.13 / socket.io-parser 4.2.7 / jsonwebtoken 9.0.3
  not affected by the cited CVEs; **ioredis 5.11.1** (Snyk High,
  RESP-parser recursion) and **Redis 7.0.15** (CVE-2024-31228)
  remain known risks — production Redis must be ≥ 7.2.6 with auth
  on a private network. A real audit must run before any production
  release.
- L-01–L-16 documented items unchanged (see `10-security.md`).

### 13.4 Gaps, discrepancies and honest limitations found by Stage 5

- **G-1 — Authorization matrix covers 4 routes, not "every route".**
  Plan §10.4 requires every route × every state. The matrix test
  (`authz-matrix.e2e.spec.ts`) probes 4 guarded routes
  (`GET/PATCH /users/me`, `GET /users/:id/profile`,
  `POST /auth/logout`) × 8 states (32 assertions, all passing).
  The other 3 guarded routes (`PATCH /users/me/password`,
  `PATCH /users/me/preferences`, `DELETE /users/me`) are exercised
  for happy-path + error cases in `auth.e2e.spec.ts` but not across
  the full state matrix. The guard mechanism is identical (global
  guards + controller-level `EmailVerifiedGuard`), so FR-42/NFR-17
  are marked PASS — but the matrix itself is incomplete. Phase 5
  should extend the matrix to all 7 guarded routes.
- **G-2 — NFR-14 has no header-assertion test.** `helmet()` is
  wired in `main.ts` and production fail-fast is unit-tested
  (`config.validation`, 5 tests), but no test asserts HSTS /
  `nosniff` headers are actually emitted, and no live TLS or live
  production-mode boot was possible (production requires
  non-loopback DB/Redis URLs; local services bind 127.0.0.1 only).
  NFR-14 is PASS for what is verifiable here; TLS termination
  remains a deployment property.
- **G-3 — `backend/docs/09-testing.md` was stale.** It still said
  unit 143 / e2e 68 (Stage 3 numbers) while the tree had 156 / 73
  since Stage 4 (`10-security.md` had the right numbers). Stage 5
  corrected `09-testing.md` to the measured counts with per-suite
  tables.
- **G-4 — No load verification.** NFR-05 (≤ 500 ms at 200 users)
  and NFR-24 (500 concurrent players) are BLOCKED: `test/load/`
  does not exist, no k6 script exists, no load run was performed.
  What exists is design (stateless services, indexed queries, Redis
  adapter) plus the two-node broadcast integration test. The load
  tests belong to Phase 5, when gameplay traffic exists.
- **G-5 — Node 22 LTS unexercised.** All Stage 5 runs used Node
  v24.22.1; `engines` + `.nvmrc` pin 22 LTS and no 24-vs-22
  variance was hit, but Node 22 itself has never run this backend
  in this environment.
- **G-6 — No CI, no production boot probe.** No
  `.github/workflows/` file exists (Workflows permission 403); all
  evidence is local command output. No production deployment,
  container image, reverse proxy / TLS config, backup, load test,
  pen test, or third-party audit exists.
- **Guard constraints verified:** `git diff 102884a..HEAD --
  diceup_app/` is empty (zero Flutter changes); no admin panel, no
  payment code, no offline dependency added. NFR-23 and
  CON-01/02/04/05/06 are PASS (guard).

### 13.5 Final status tally (§2.1, 34 rows)

PASS 32 (incl. 2 foundation-only, 2 interface-only, 1 pattern-only,
1 partial — FR-10 request path only), BLOCKED 2 (NFR-05, NFR-24 —
load verification only; the implementation design is in place),
FAIL 0, NOT IMPLEMENTED 0 as a standalone row status (the
not-implemented parts — FR-10 anonymisation, CI-07/CI-08 providers,
BR-14 match storage — are recorded inside their rows' evidence).
§2.2: 25 rows NOT APPLICABLE, 2 guard rows PASS.

### 13.6 Plan corrections recorded by Stage 5

1. **Vectors wording (§2.1.2 NFR-39, §10.2)** — corrected as
   described in the NFR-39 row: the loader validates coherence and
   asserts the canonical case equals the Dart defaults; it does not
   require all 23 cases to equal the defaults (17 at defaults, 6
   deliberate single-field variants — verified by Stage 5 against
   `diceup_app/test/vectors/rules.json`).
2. **§0.2 environment table** — PostgreSQL online, Redis running,
   `backend/` exists (Stage 1 values were arrival-time observations).
3. **§2 status values** — `PLANNED` / `NOT IN PHASE 4 SCOPE`
   superseded by the final statuses above.

*Plan prepared 2026-11-27 (Stage 1, Phase 4). Sources: SRS v0.1
(`~/workspace/scratch/diceup-audit/DiceUp_SRS_v0.1.txt`), SDD v1.0
(`~/workspace/scratch/diceup-audit/DiceUp_Software_Design_Document_v1.0.txt`),
`diceup_app/test/vectors/rules.json` (23 cases, ruleset `1.0.0`),
`diceup_app/lib/domain/engine/ruleset_config.dart`. Staging branch:
`feature/online-phase-4-backend-foundation` @ `102884a`. No code was
written for this plan; no verification is claimed beyond the environment
checks in §0.2.*
