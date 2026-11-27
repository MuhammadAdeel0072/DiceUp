# Backend architecture — DiceUp online, Phase 4 foundation (Stages 2a–2c)

NestJS 11 + TypeScript modular monolith (SDD §4.5, decision D-04),
PostgreSQL 16 via TypeORM, Redis 7 via ioredis, Socket.IO 4.8 over the
same HTTP server as REST. This document describes what is actually
built at the end of Stage 2c — not what the plan promises for later
stages. Anything listed under "not here yet" does not exist in this
tree.

## Process and transport

- One Node process, plain HTTP, bound to `127.0.0.1` on `PORT`
  (default 3000). TLS is a deployment property (NFR-14): the app
  never terminates TLS itself; production runs behind TLS termination
  (see `02-setup.md`).
- REST under the global prefix `/v1`. Socket.IO shares the same HTTP
  server — no separate port, no plain-WebSocket listener.
- Swagger (OpenAPI) at `/v1/docs` in non-production only.
- Graceful shutdown: `app.enableShutdownHooks()`; the Socket.IO
  Redis clients disconnect in `onApplicationShutdown` (see
  `08-socket-io.md` — the ordering matters).

## Modules (`backend/src/`)

| Module | Responsibility |
|---|---|
| `config/` | Validated config (`@nestjs/config` + Joi), typed `AppConfig`, production fail-fast. See `03-environment.md`. |
| `common/` | Cross-cutting: §6.3 error envelope + error codes, `HttpExceptionFilter`, `ResponseEnvelopeInterceptor`, `LoggingInterceptor`, structured pino logging, pagination helpers, guard decorators (`@Public()`, `@Roles()`, `@CurrentUser()`), rate-limit decorator + guard. |
| `database/` | TypeORM + `pg`, the four Phase 4 entities, migrations, `SnakeNamingStrategy`. See `04-database.md`. |
| `redis/` | `RedisService` (the only Redis API the app uses) + the `REDIS_KEYS` registry. See `05-redis.md`. |
| `health/` | Liveness + readiness (`GET /v1/health`, `GET /v1/health/ready`). |
| `mailer/` | `Mailer` interface; `log` transport (dev/test) and `smtp` transport. |
| `auth/` | Registration, email verification, login, refresh/logout, password recovery, Argon2id hashing, RS256 JWT (`TokenService`, `JwtStrategy`), guards, rate limits, session purge job. See `07-authentication.md`. |
| `users/` | Own profile, public profile, password change, preferences, deletion request. |
| `socket/` | Socket.IO gateway on namespace `/game` with the Redis adapter (Stage 2c). See `08-socket-io.md`. |

`AppModule` imports them in that order (config first — everything
else reads it). Global `APP_GUARD`s, in order, are `JwtAuthGuard` →
`AccountStatusGuard` → `RolesGuard` → `RateLimitGuard` (registered in
`AuthModule`); they apply to REST only — the gateway wires its own
guards explicitly (guards do not run on `handleConnection`).

## Request pipeline (REST)

```
HTTP request
  → helmet (HSTS + nosniff)
  → CORS (allow-list only, never a wildcard; credentials: false)
  → JSON body parser, 100 KB limit (NFR-20; the platform-express
    default — no second parser is added)
  → global ValidationPipe (whitelist: strip unknown fields, transform)
  → APP_GUARDs (JwtAuthGuard → AccountStatusGuard → RolesGuard →
    RateLimitGuard); @Public() opts a route out
  → controller guards (e.g. EmailVerifiedGuard, @Roles('player'))
  → handler → service → TypeORM / Redis
  → ResponseEnvelopeInterceptor (success envelope)
  → HttpExceptionFilter (error envelope; body-parser errors mapped:
    oversized body → 413 PAYLOAD_TOO_LARGE, malformed JSON → 400
    VALIDATION_FAILED)
  → LoggingInterceptor (one structured line per request)
```

Every response uses the §6.3 envelope:

```json
// success
{ "success": true, "data": { "...": "..." } }
// error
{ "success": false, "error": { "code": "VALIDATION_FAILED", "message": "...", "details": { "field": ["..."] } } }
```

`X-Request-Id` is returned on every response. Error `code` values are
the machine-readable contract — clients switch on `code`, never on
message text. The same envelope is used on the socket transport
(`08-socket-io.md`).

## Data model

Exactly four tables (SDD §9.2), created by migration
`0001_init-auth` and extended by `0002_add-profile-preferences`:

- `users` — identity, status, `email_verified_at`,
  `deletion_requested_at` (`[P4 choice]` column).
- `profiles` — one row per user; display name, avatar key,
  `notification_preferences` JSONB (added by 0002).
- `auth_sessions` — one row per login; opaque refresh token
  (SHA-256 hashed at rest), `family_id` (`[P4 choice]`, for reuse
  revocation), expiry.
- `email_tokens` — single-use verification / password-reset codes
  (256-bit, hashed at rest), partial unique index
  `(user_id, purpose) WHERE used_at IS NULL`.

Entity properties are camelCase; migration columns are snake_case; a
`SnakeNamingStrategy` maps them. `synchronize` is never on (asserted
by a unit test) — schema changes only via migrations
(`04-database.md`).

## Redis usage

Redis holds **no business truth** (CI-05) — only counters and locks
that PostgreSQL can rebuild:

- rate-limit counters (REST + socket) and login-throttle counters;
- the Socket.IO Redis adapter's pub/sub channels (horizontal scaling);
- named-only keys for later phases: presence, matchmaking queue,
  match lock, match state, room codes (`05-redis.md`).

Redis down: auth writes fail closed; PostgreSQL-backed reads keep
working (fail-open for reads); readiness reports `redis: down`.

## Configuration

Validated with Joi at boot; production fails fast (named error, exit
non-zero) when a required variable is missing, and when
`DATABASE_URL` points at localhost. There is no default JWT key,
database URL, or password anywhere. See `03-environment.md` — and
note the precedence gotcha: `ConfigService` reads `backend/.env`
*before* `process.env`, so never ship a `.env` file alongside shell
env in a shared/test environment.

## Logging

Structured JSON via `nestjs-pino`, one line per request
(method/path/status/latency/requestId; bodies are never logged).
Redaction list: `password`, `*token*`, `authorization`, `mfa*`,
`JWT_PRIVATE_KEY`, `DATABASE_URL`, `REDIS_URL`. Socket logs carry
`userId` + `socketId` only — never a token.

## What is NOT here yet

Socket.IO gateway exists (Stage 2c) but has no rooms, no
matchmaking, no gameplay, no presence tracking, no match state.
Also not here: friends, leaderboards, notifications, admin, any
Next.js admin, any Flutter auth screen. Those are Phase 5+; the
hook points are documented in `08-socket-io.md`.
