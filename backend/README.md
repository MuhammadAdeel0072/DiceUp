# DiceUp backend — Phase 4 foundation (Stages 2a + 2b + 2c)

NestJS + TypeScript modular monolith (SDD §4.5, decision D-04), PostgreSQL 16
via TypeORM, Redis 7 via ioredis, Socket.IO 4.8 with the Redis adapter.
**Stage 2a scope:** scaffolding, validated config, the four Phase 4 tables,
Redis service, health/readiness, structured logging, and the error
envelope. **Stage 2b scope:** auth (register → verify → login → refresh →
logout, password recovery, Argon2id, RS256 JWT, guards, rate limits),
users API, mailer (log + SMTP transports), session purge job.
**Stage 2c scope (this stage):** Socket.IO gateway on namespace `/game`
(Redis adapter, handshake + per-message JWT auth reusing the one auth
path, event validation, 20/s rate limit with abuse disconnect) + the
backend documentation set in `docs/`. No matchmaking, gameplay, friends,
leaderboards, notifications, or admin — those are later stages
(see `docs/PHASE-4-PLAN.md`).

## Documentation

| Doc | Contents |
|---|---|
| `docs/01-architecture.md` | Backend architecture (modules, request pipeline, data model). |
| `docs/02-setup.md` | Setup guide: dev/test/prod, starting PostgreSQL + Redis, RS256 keys, migrations. |
| `docs/03-environment.md` | Environment-variable reference (incl. the `.env` precedence gotcha). |
| `docs/04-database.md` | Database setup + migration instructions. |
| `docs/05-redis.md` | Redis setup guide + key registry + failure policy. |
| `docs/06-rest-api.md` | REST API documentation (all endpoints, rate limits, error codes). |
| `docs/07-authentication.md` | Authentication (token model, flows, guard chain, keys, mailer). |
| `docs/08-socket-io.md` | Socket.IO architecture (events, auth, conventions, foundation-only scope). |
| `docs/09-testing.md` | Testing instructions + current test counts. |
| `docs/10-security.md` | Security notes: verified items, assumptions, remaining risks. |

## Environment variance (recorded, plan §0.2 / X-02)

- SDD pins **Node 22 LTS** (DA-07). This VM has **Node v24.22.1**; `engines`
  in `package.json` and `.nvmrc` pin `>=22 <23`, and all work here was run
  and tested on Node 24.22.1. No 24-vs-22 variance was hit — `argon2`
  builds and runs on Node 24 (native prebuild loads fine).
- SDD §15.2 proposes local PostgreSQL/Redis "via containers"; this VM has
  **no Docker**, so local services are used instead (below). No container
  claim is made.
- **No CI exists** (Workflows permission 403). No `.github/workflows/` file
  is part of this work and no CI pass is claimed; evidence is local command
  output (see Verification).
- **Dependency version pins (Stages 2b + 2c):** plain `npm install` pulled
  `@nestjs/jwt` / `@nestjs/passport` / `@nestjs/schedule` v12, which are
  ESM-only (`"type": "module"`) and cannot be required under this
  project's CommonJS ts-jest setup (e2e failed to load `AuthModule`).
  Pinned to the Nest-11-era CJS releases: `@nestjs/jwt` 11.0.2,
  `@nestjs/passport` 11.0.5, `@nestjs/schedule` 6.1.3. The same trap
  applies to the socket stack: `@nestjs/websockets` /
  `@nestjs/platform-socket.io` are pinned to 11.2.12 (v12 is ESM-only),
  `socket.io` to 4.8.3 exact (matches platform-socket.io's dependency,
  so npm dedupes to one copy), and `@socket.io/redis-adapter` to
  **8.2.1** exact — both 8.2.1 and 8.3.0 are CJS (verified from the
  published tarballs: no `"type": "module"`, `main: ./dist/index.js`),
  but 8.3.0 peers on `socket.io-adapter ^2.5.4` while socket.io 4.8.x
  bundles `~2.5.2`; 8.2.1 peers on `^2.4.0`, satisfied by the bundled
  2.5.9. Re-check before any upgrade to v12 (needs an ESM migration of
  the backend).

## Prerequisites

- Node 22 LTS (dev here: 24.22.1), npm 10+
- PostgreSQL 16, Redis 7

## Start the local services (this VM, 2026-11-27)

```bash
# PostgreSQL cluster 16/main was DOWN on arrival; started with:
pg_ctlcluster 16 main start
pg_lsclusters          # expect: 16 main 5432 online

# Redis was NOT running; started with (localhost only, no persistence):
redis-server --daemonize yes --port 6379 --save '' --appendonly no \
  --protected-mode yes --bind 127.0.0.1
redis-cli ping         # expect: PONG
```

Create the local role/database (run once, as the `postgres` OS user):

```bash
sudo -u postgres psql -c \
  "CREATE ROLE diceup LOGIN CREATEDB PASSWORD 'diceup_dev_local_only';"
sudo -u postgres psql -c "CREATE DATABASE diceup_dev OWNER diceup;"
```

The password above is a **local-dev-only** credential. It appears in
`.env` (git-ignored) and in test code defaults for the local cluster only;
never use it anywhere else, never commit a real `.env`.

## Run

```bash
cd backend
cp .env.example .env   # then fill in local values (DATABASE_URL etc.)
npm ci
npm run migration:run  # applies 0001_init-auth + 0002_add-profile-preferences to DATABASE_URL — dev DB only
npm run start:dev      # http://127.0.0.1:3000/v1/health
```

## Auth & users (Stage 2b)

Endpoints (all under `/v1`, envelope §6.3):

| Method + endpoint | Purpose |
|---|---|
| `POST /auth/register` | Register (FR-02); 201 + user + tokens; 409 `EMAIL_TAKEN` / `USERNAME_TAKEN` |
| `POST /auth/login` | Email-or-username + password (FR-04); generic 401 `INVALID_CREDENTIALS`; NFR-16 throttle |
| `POST /auth/refresh` | Rotate refresh token (NFR-15); reuse revokes the whole family |
| `POST /auth/logout` | Revoke the current session (FR-05) |
| `POST /auth/verify-email` | Verify with a single-use code (FR-03); reuse 409, expired 410 |
| `POST /auth/verify-email/resend` | Resend verification (neutral 200, no leak) |
| `POST /auth/forgot-password` | Request reset (FR-06, neutral 200 even for unknown emails) |
| `POST /auth/reset-password` | Reset with a single-use code (FR-06); revokes all sessions |
| `GET /users/me` · `PATCH /users/me` | Own profile (FR-07); avatar from the bundled set, no uploads |
| `PATCH /users/me/password` | Change password (FR-08); revokes all sessions |
| `PATCH /users/me/preferences` | Notification preferences (FR-08, JSONB on `profiles`) |
| `GET /users/{id}/profile` | Public profile (FR-63); public fields only |
| `DELETE /users/me` | Request account deletion (FR-10, partial: marker + revoke; **no** anonymisation — awaits OD-08) |

Auth design (SDD §12.4/§13.1, plan §7.1): Argon2id (64 MiB / 3 / 1);
RS256 access JWT, 15 min, claims `sub` / `role: 'player'` /
`email_verified` / `sid`; opaque 256-bit refresh tokens, SHA-256 hashed
at rest, rotated on every use, family revocation on reuse
(`auth_sessions.family_id`); the `sid` session check runs on **every**
authenticated request (`JwtStrategy.validate`) — it is load-bearing and
must not be optimised away. Global guards (APP_GUARD, in order):
`JwtAuthGuard` → `AccountStatusGuard` → `RolesGuard` →
`RateLimitGuard`; public routes opt out with `@Public()`. Unverified
users can log in/resend but get 403 `EMAIL_NOT_VERIFIED` on users
routes; suspended/blocked get 403 `ACCOUNT_SUSPENDED` (only after a
correct password on login, so it cannot enumerate accounts).
Email tokens are 256-bit, hashed, single-use (verify 24 h, reset 1 h).
A daily 03:00 purge job deletes expired sessions and used/expired
email tokens (revoked-but-unexpired sessions are kept — reuse
detection needs them until they expire).

### RS256 keys

- Dev: a keypair lives in `backend/.keys/` (git-ignored, RSA 2048,
  generated with openssl — see `.env.example`). `.env` points at it
  via `JWT_PRIVATE_KEY_FILE` / `JWT_PUBLIC_KEY_FILE` (inline PEM in
  `JWT_PRIVATE_KEY` / `JWT_PUBLIC_KEY` wins when both are set).
- Dev/test with no keys configured: the app generates an ephemeral
  in-memory keypair at boot (warning logged; tokens die on restart).
- Production: boot fails fast without real keys (config validation +
  `JwtKeys` factory). **Never commit a key; never use dev keys in
  production.**

### Mailer

`Mailer` interface (`src/mailer/`), transport selected by
`MAILER_PROVIDER`: unset/`log` (default, dev/test) stores messages in
memory and logs recipient + kind only — never sends real email, never
logs a token; `smtp` sends via nodemailer from `MAILER_SMTP_HOST` /
`MAILER_SMTP_PORT` / `MAILER_SMTP_USER` / `MAILER_SMTP_PASS` (+
`MAILER_FROM`). Production with anything but `smtp` fails fast.
Verification/reset arrive as a code (no player web frontend exists in
Phase 4 for a link form). Provider selection is still OPEN (OD-09).

### Rate limits (plan §6.5)

Login: 5 failures / 15 min per account **and** per IP (NFR-16),
failure-based, the account counter resets on success while the IP
counter expires naturally after its 15-min TTL (Stage 4, M-03 —
resetting the shared IP counter on any success handed attackers on
shared NAT a fresh budget), Redis down fails closed
(503). Register 10/hr/IP; forgot-password 5/hr/email (hashed key);
reset/verify/resend 10/hr/IP; refresh 60/hr/IP; all authenticated
REST 100/min/user (fail-open for reads when Redis is down, so
PostgreSQL-backed reads keep working). All 429s carry `Retry-After`.
`@nestjs/throttler` was deliberately **not** installed — the plan's
Redis-counter choice is implemented instead.

## Database

- **TypeORM + `pg`** (SDD §3.5/§9.2/§15.2). `synchronize` is **never** on
  (asserted by a unit test); schema changes only via migrations.
- Migration `0001_init-auth` creates exactly four tables, verbatim from
  SDD §9.2 — `users`, `profiles`, `auth_sessions`, `email_tokens` — plus
  the two documented `[P4 choice]` columns (`users.deletion_requested_at`,
  `auth_sessions.family_id`). It also creates the `citext` extension and
  the SDD §9.3 indexes (`users(status, created_at)`,
  `auth_sessions(user_id, expires_at)`, partial unique
  `email_tokens(user_id, purpose) WHERE used_at IS NULL`).
- Migration `0002_add-profile-preferences` (Stage 2b) adds
  `profiles.notification_preferences` JSONB — the plan (§2.1.1 FR-08)
  says the persistence column lives on `profiles`, but 0001 did not
  create it; 0001 is never edited, schema changes only via new
  migrations.
- **Naming:** entity properties are camelCase, migration columns are
  snake_case. A `SnakeNamingStrategy` (`src/database/naming.strategy.ts`)
  maps them — without it every repository query failed
  (`column User.emailVerifiedAt does not exist`), a latent Stage 2a
  defect found by Stage 2b's first repository query (no Stage 2a repo
  query ever ran).
- Migration commands: `npm run migration:run | revert | show`
  (TypeORM CLI via `src/database/data-source.ts`). Run against a
  scratch/dev database, never production. Expand-then-contract (SDD §15.4).
- Local backup of the dev cluster: `pg_dump -U diceup -d diceup_dev > diceup_dev.sql`
  (NFR-34 is an operations concern; no production backup is set up here).

## Redis

- `ioredis` behind `RedisService` (`src/redis/`) — the only Redis API the
  app uses. `ping/get/set/del`, atomic `incrWithExpiry` (Lua INCR+EXPIRE),
  `acquireLock/releaseLock` (SET NX EX, token-checked release).
- Failure policy (SDD §9.4): Redis down → auth writes fail closed
  (register → 503, proven by the dead-Redis boot e2e test); a dead
  Redis no longer crashes the process at boot (Stage 4, H-01 — the
  Socket.IO adapter clients queue until Redis answers);
  health/readiness reports `redis: down`; PostgreSQL-backed reads
  keep working. No business truth is ever stored only in Redis (CI-05).
- Key registry: `src/redis/redis-keys.ts` (only rate-limit keys are written
  in Phase 4; presence/matchmaking/match-state keys are named only).

## Health

- `GET /v1/health` — liveness only, `200 { success: true, data: { status: "ok" } }`.
- `GET /v1/health/ready` — readiness. `200` only if **both** PostgreSQL
  (`SELECT 1`) and Redis (`PING`) are up; otherwise `503` with the error
  envelope and `error.data` naming each dependency (`up`/`down`) plus
  per-check latency in ms. No credentials, connection strings, hostnames,
  or stack traces in either response.
- Swagger (non-production only): `/v1/docs`.

## Config

Validated with `@nestjs/config` + Joi (`src/config/`). Required in every
environment: `NODE_ENV`, `PORT`, `DATABASE_URL`, `REDIS_URL`. Production
additionally fails fast at boot (named error, exit non-zero) when
`JWT_PRIVATE_KEY`, `JWT_PUBLIC_KEY`, `JWT_ISSUER`, `RULESET_VERSION`,
`CORS_ORIGINS`, or `MAILER_PROVIDER` is missing, or when `DATABASE_URL`
points at localhost. There is no default JWT key, database URL, or
password. `RULESET_VERSION=1.0.0` (BR-14) must match
`diceup_app/test/vectors/rules.json` and the Dart `RulesetConfig` default;
the vector loader in `test/vectors/` asserts this (NFR-39 foundation).
Note: 17/23 vector cases embed the defaults; 6 are deliberate
single-field variants — the loader validates every embedded ruleset
for coherence and asserts the canonical default case, rather than
requiring all 23 to equal the defaults (see the loader's doc comment).

**Config precedence gotcha (found in Stage 2a testing, root-caused in Stage 3):**
`@nestjs/config`'s `ConfigService.get()` reads the Joi-validated env
store *before* `process.env`, and that store is frozen at
`ConfigModule.forRoot()` time (import time) from `backend/.env`, so a
shell-env override of `DATABASE_URL`/`REDIS_URL` is silently ignored
while a `.env` file sets the same key. Stage 3 proved the consequence:
every e2e suite had been running against `diceup_dev` instead of its
scratch database (523 test users accumulated there) because
`DatabaseModule` read top-level `DATABASE_URL`. Fixed in Stage 3:
Database, Redis, and the socket Redis clients now read the namespaced
`app.databaseUrl` / `app.redisUrl` keys, whose factory reads live
`process.env` when `ConfigService` is created; `full-journey.e2e.spec.ts`
regresses it. `appConfig` in `main.ts` reads `process.env`
directly, so the two paths can disagree. Rule for later stages: never
read a top-level env key via `ConfigService.get()` — use the `app.*`
namespace — never ship a `.env` file alongside shell env in any
shared/test environment, and prefer provider overrides over env
mutation in tests.

## Logging / errors

- Structured JSON logging via `nestjs-pino` (`src/common/logging/`), one
  line per request (method/path/status/latency/requestId, bodies never
  logged), with a redaction list (`password`, `*token*`, `authorization`,
  `mfa*`, `JWT_PRIVATE_KEY`, `DATABASE_URL`, `REDIS_URL`).
- Every response uses the §6.3 envelope: success
  `{ success: true, data }`, error
  `{ success: false, error: { code, message, details?, correlationId? } }`
  via `ResponseEnvelopeInterceptor` + `HttpExceptionFilter`. `X-Request-Id`
  is returned on every response.
- The exception filter also maps Express body-parser errors (Stage 2b
  fix — an oversized body came back as a misleading 500): oversized
  body → 413 `PAYLOAD_TOO_LARGE`, malformed JSON → 400
  `VALIDATION_FAILED`.

## Socket.IO (Stage 2c)

Namespace `/game`, Redis adapter (`@socket.io/redis-adapter` 8.2.1),
authenticated connections only — the handshake middleware reuses the
one auth path (`TokenService` + `JwtStrategy`, including the `sid`
revocation check) and the guard re-validates the token on every
message. Events: client → server `ping` (foundation-only probe,
`{ requestId }`); server → client `connected`, `pong`, `exception`
(§6.3 envelope). 20 events/s per socket, 5 violations → disconnect;
10 KB per-event payload limit enforced by `WsValidationPipe`. No
rooms, matchmaking, gameplay, presence, or match state yet (Phase 5).
Full detail: `docs/08-socket-io.md`.

## Tests

```bash
npm test          # unit tests (config, DB options, naming strategy, RedisService fake, pagination, hasher, tokens, throttle, rate limit, guards, JWT strategy, DTOs, mailers, purge job, socket guards/pipe/rate limit) — 143 tests, all passing
npm run test:e2e  # integration + security + vectors: real PostgreSQL + real Redis
                  # (fresh scratch DB per run, migrations, schema check, drop) — 68 tests, all passing
                  # (Stage 3 added test/integration/full-journey.e2e.spec.ts, 8 tests)
npm run build && npm run lint && npm run typecheck && npm run format:check
npm run build && npm run lint && npm run typecheck && npm run format:check
```

Integration tests create a scratch database `diceup_test_<pid>_<random>`
on the local cluster, run all migrations, verify the schema, run, and
drop it. They never touch the dev database or any shared/production service.
Rate-limit counters are cleared before each test (all supertest traffic
comes from one IP by design); rate-limit tests build their flood inside
a single test. The e2e suite covers: auth flows end-to-end (register →
verify → login → refresh → logout, reuse-revocation, forgot/reset),
the authorization matrix (4 routes × 8 states), the socket gateway
(auth refusals, `ping`/`pong`, malformed + oversized payloads,
disconnect/reconnect, rate-limit burst + abuse disconnect, two-node
broadcast via the Redis adapter), and security (enumeration
resistance, SQL injection, oversized/malformed bodies, no secrets in
log output).

## What is NOT here yet (Stage 3+)

Matchmaking, gameplay, friends, leaderboards, notifications, admin.
The Socket.IO gateway **is** installed (Stage 2c); what it does not
have yet is rooms, matchmaking, gameplay events, presence tracking,
or match state — those are Phase 5.
