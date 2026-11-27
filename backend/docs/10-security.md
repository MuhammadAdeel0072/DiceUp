# Security notes

Honest account of what is verified, what is assumed, and what is
still open. Nothing here claims production security that has not
been verified.

## Stage 4 review (2026-11-27)

The Stage 4 security + quality review covered the whole backend:
every REST DTO and socket payload, the auth lifecycle, guard
ordering, rate-limit fail modes, CORS/headers, secrets, raw-SQL
surface, dependency versions, logging, configuration, and socket
abuse. Review method: code reading plus live probes against the
production build on real PostgreSQL 16.15 + Redis 7.0.15 (dead-Redis
boot, nonexistent/unreachable database boot, trust-proxy flood,
CORS preflight, Swagger in dev). All fixes below landed as local
commits on `feature/online-phase-4-backend-foundation` (no push,
no PR). The full verification set was re-run on the finished tree:
typecheck, lint, format, build, 156 unit tests (22 suites) and 73
e2e tests (8 suites) — all green.

### Findings fixed in code

- **H-01 (High) — Dead Redis crashed the process at boot.**
  With Redis down the app died in <1 s with an uncaught
  `MaxRetriesPerRequestError`: the Socket.IO Redis adapter issues
  SUBSCRIBE on its pub/sub clients internally with no rejection
  handler, and the queued command was flushed as an unhandled
  rejection under `maxRetriesPerRequest: 3`. This contradicted the
  documented design ("the app must still boot so /health can
  answer") and turned a Redis outage into a total outage.
  Fixed: the adapter clients now use `maxRetriesPerRequest: null`
  (queue until Redis answers); the `RedisService` client keeps 3
  because its commands are all awaited/caught by callers. Shutdown
  awaits on the adapter clients are bounded by a 2 s timeout each,
  so a dead Redis cannot hang `app.close()` either. New
  `redis-down.e2e.spec.ts`: boots with dead Redis, liveness 200,
  readiness 503 (`database: up, redis: down`), register fails
  closed 503. Trade-off recorded in code: adapter publishes queue
  in memory while Redis is down — bounded in Phase 4 (no broadcast
  traffic exists yet).
- **H-02 (High) — Concurrent duplicate registration returned 500.**
  The register duplicate pre-checks are a TOCTOU race; the loser
  hit the CITEXT unique index as an unhandled 500 instead of the
  409 the API promises. Fixed: `AuthService.register()` catches
  PostgreSQL 23505 (new shared `isUniqueViolationError`) and
  re-checks which key lost, throwing the same 409
  `EMAIL_TAKEN` / `USERNAME_TAKEN`. `EmailTokenService.issue()`
  retries once on 23505 (same class: concurrent issue vs the
  partial unique live-token index). Proven by a concurrent-register
  e2e test (one 201 + one 409, exactly one user row) and a unit
  test for the error classifier.
- **H-03 (High in production topology) — `trust proxy` was missing.**
  Behind the TLS-terminating reverse proxy the plan requires
  (NFR-14), `req.ip` is the proxy's address for every client, so
  the per-IP login throttle (NFR-16) and the per-IP
  register/refresh limits collapse into one shared bucket — five
  failed logins from anyone would throttle everyone. Fixed: new
  `TRUST_PROXY` env (`unset/0/false` → off; `1/true` → 1; digits →
  count; loopback/link-local/unique-local passthrough; anything else
  → off, never trusts blindly), wired in `main.ts` and the e2e
  test factory, validated by Joi, documented in
  `03-environment.md` and `.env.example`. Proven live: with
  `TRUST_PROXY=1`, 11 registers with `X-Forwarded-For: 9.9.9.9`
  gave 10×201 then 429, and a fresh `X-Forwarded-For: 8.8.8.8`
  still got 201. (The probe's test users were deleted afterwards;
  `diceup_dev` is back to 0 rows.)
- **M-01 — REST validation errors collapsed to `_global`.**
  `exceptionFactory` now emits per-field `details` on REST 400s
  (shared `flattenValidationErrors` with the socket pipe) and the
  filter passes `details` through. The e2e assertion now requires
  per-field keys.
- **M-02 — Database boot had no bounded fail-fast.** A Stage 3
  probe against a nonexistent database took 26 s to exit (Nest
  TypeORM defaults: 10 retries × 3 s) and an unreachable host
  could hang far longer (pg's `connectionTimeoutMillis` defaults
  to 0). Fixed: `connectTimeoutMS` 5 s, Nest `retryAttempts` 3,
  `retryDelay` 1 s. Measured after the fix: nonexistent database →
  exit 1 in 4 s; unreachable host `10.255.255.1` → exit 1 in 3 s
  (bounded to ~17 s worst case). See "Fail-fast boot" below.
- **M-03 — Any user's successful login reset the shared IP
  throttle budget.** `LoginThrottleService.reset()` now clears only
  the account counter; the IP counter expires naturally after its
  15-min TTL. Previously an attacker on shared NAT got a fresh
  budget on every victim login.
- **M-04 — Client-supplied `X-Request-Id` was adopted as the
  correlation id.** Both the interceptor and the filter now always
  generate a fresh server-side UUID (log injection / forced
  collisions). Note: on error paths the header id and the body's
  `correlationId` can differ (guards reject before the interceptor
  runs); the body's id is authoritative and matches the server log.
- **M-05 — Token fields had no length cap.** `@MaxLength(256)`
  added to refresh-token, verify-email and reset-password token
  fields (real tokens are 43-char base64url).
- **M-06 — Production loopback check only caught literal
  `localhost` in `DATABASE_URL`.** Now `isLoopbackUrl()` covers
  `localhost` / `127.0.0.1` / `::1` / `*.localhost` for both
  `DATABASE_URL` and `REDIS_URL`.
- **M-07 — A half-configured JWT keypair silently fell back to
  an ephemeral dev keypair.** `buildJwtKeys` now throws when
  exactly one of private/public key is present.
- **M-08 — `.gitignore` missed `.env.test` / `.env.production`.**
  Now `.env*` + `!.env.example`, verified with `git check-ignore`.
- **Logger config precedence (Low).** `LoggerModule` read
  `process.env.LOG_LEVEL` at import time, silently ignoring
  `LOG_LEVEL` from `.env`. Now `forRootAsync` from the validated
  config.

### Stage 3 handoff items — decided

- **Config precedence (D-01):** re-audited. Grep result: **zero**
  remaining top-level `ConfigService` reads of `DATABASE_URL` /
  `REDIS_URL` (or any other secret key) in `src/`. Only the config
  factory (`src/config/configuration.ts`) reads `process.env`
  directly, plus `src/database/data-source.ts` (CLI `AppDataSource`,
  documented exceptions). Regression guard added:
  `test/unit/config-precedence.spec.ts` scans `src/` for
  top-level ConfigService reads and non-allow-listed
  `process.env` reads, and asserts the namespaced reads exist.
- **Token-claim staleness: already fixed, no code change.**
  `JwtStrategy.validate()` re-checks the DB user row on every
  request and derives `emailVerified` from
  `users.email_verified_at`, never trusting the JWT
  `email_verified` claim. `WsJwtGuard` reuses
  `JwtStrategy.validate()` per handshake **and per message**, so
  socket auth has the same property. A token minted
  pre-verification becomes usable immediately after verification —
  no re-login needed. `AuthService.refresh()` / `createSession()`
  also sign fresh tokens from the DB row. The claim is
  informational only.
- **Log redaction:** kept. The stdout-capture security test
  asserts no password/token/hash appears in logs. No new log path
  leaks: socket logs carry `userId` + `socketId` only; mailer and
  register-failure logs include recipient email addresses
  (operational PII, not secrets — see L-06). Pino redaction covers
  `password`, `*token*`, `authorization`, `mfa*`,
  `JWT_PRIVATE_KEY`, `DATABASE_URL`, `REDIS_URL`.
- **Envelope consistency:** re-checked. REST errors and socket
  `connect_error` / `exception` both carry
  `{success:false, error:{code, message, details?}}`; validation
  details are now per-field on both transports (M-01). 413/400
  paths verified by security e2e. One residual gap: see L-01 below
  (header vs body correlation id on error paths).
- **Fail-fast boot:** real risk, fixed (M-02 above). Pre-fix
  measurements: nonexistent DB 26 s to exit 1; unreachable host
  unbounded (pg timeout 0). Post-fix: 4 s and 3 s respectively,
  worst case bounded at ~17 s. One nuance: on module-init failure
  the process exits 1 via Nest's `ExceptionsZone` (its
  `ExceptionHandler` logs the named error with a stack); the
  `Fatal: backend failed to start` catch in `main.ts` is therefore
  unreachable for init failures — it only covers errors after
  `NestFactory.create` returns (e.g. `listen`). The behaviour is
  correct (named error, exit 1); the comment in `main.ts` slightly
  overstates the catch's reach.

### Route-vs-guard enumeration (verified from source)

Global guards, in order: `JwtAuthGuard` → `AccountStatusGuard` →
`RolesGuard` → `RateLimitGuard`. `@Public()` skips the JWT check
(and the later guards pass with no principal). `JwtStrategy`
enforces `role === 'player'`, `sid` session liveness
(not revoked/expired, `userId` match), and loads the DB user row.
`EmailVerifiedGuard` is controller-level on `UsersController`
only — auth endpoints are intentionally exempt (login/resend must
work while unverified), and logout is intentionally **not**
email-verified-guarded (an unverified user must be able to log
out).

| Route | Guard state |
|---|---|
| `POST /v1/auth/register` | `@Public` · 10/hr/IP |
| `POST /v1/auth/login` | `@Public` · NFR-16 throttle (account + IP) |
| `POST /v1/auth/refresh` | `@Public` · 60/hr/IP |
| `POST /v1/auth/logout` | JWT + `sid` · 100/min/user |
| `POST /v1/auth/verify-email` | `@Public` · 10/hr/IP |
| `POST /v1/auth/verify-email/resend` | `@Public` · 10/hr/IP |
| `POST /v1/auth/forgot-password` | `@Public` · 5/hr/email (hashed key) |
| `POST /v1/auth/reset-password` | `@Public` · 10/hr/IP |
| `GET /v1/users/me` | JWT + status + verified + `@Roles('player')` · 100/min |
| `PATCH /v1/users/me` | JWT + status + verified + `@Roles('player')` · 100/min |
| `PATCH /v1/users/me/password` | JWT + status + verified + `@Roles('player')` · 100/min |
| `PATCH /v1/users/me/preferences` | JWT + status + verified + `@Roles('player')` · 100/min |
| `GET /v1/users/:id/profile` | JWT + status + verified + `@Roles('player')` · 100/min · `ParseUUIDPipe` |
| `DELETE /v1/users/me` | JWT + status + verified + `@Roles('player')` · 100/min |
| `GET /v1/health` | `@Public` · no rate limit |
| `GET /v1/health/ready` | `@Public` · no rate limit |
| `GET /v1/docs` (Swagger) | Non-production only; no auth (dev aid) |

Socket `/game`: handshake middleware + per-message `WsJwtGuard`
(same sid/status/verified checks), `WsRateLimitGuard` 20 events/s
with disconnect after 5 violations. Only event is `ping`/`pong`
(`PingDto`, 10 KB payload cap). No game events exist yet. No
client-supplied user id or role is ever trusted.

Rate-limit fail modes (verified in code): auth `@RateLimit`
endpoints fail **closed** (503) on Redis down; the generic
100/min per-user limit fails **open** (PostgreSQL-backed reads
keep working); the login throttle fails **closed** (503); the
socket rate limit fails **closed** (503).

### Dependency vulnerabilities

`npm audit` is **unavailable in this environment**: it fails with
`403 Forbidden - POST https://registry.npmjs.org/-/npm/v1/security/audits/quick - policy_denied`
(registry policy `zz_managed_internal_spaces_package_registries`).
No audit counts can be reported. Instead, the pinned versions from
`package-lock.json` were checked against public advisories:

- **engine.io 6.6.13** (via socket.io 4.8.3) — CVE-2026-59725
  (engine.io polling DoS, CVSS 7.5) affects <6.6.7 → **not
  affected**.
- **socket.io-parser 4.2.7** — CVE-2026-33151 affects ≤4.2.5 →
  **not affected**.
- **jsonwebtoken 9.0.3** — CVE-2026-25537 is the **Rust** crate,
  not npm jsonwebtoken → **not applicable**; no known npm
  jsonwebtoken CVE at 9.0.3 found.
- **Pinned CJS lines** (`@nestjs/jwt` 11.0.2, `@nestjs/passport`
  11.0.5, `@nestjs/schedule` 6.1.3, `@nestjs/websockets` /
  `@nestjs/platform-socket.io` 11.2.12, `socket.io` 4.8.3,
  `@socket.io/redis-adapter` 8.2.1) — no known CVE found for these
  exact versions in the advisory search. The pins are a constraint
  (v12 is ESM-only under this CommonJS setup), not a vulnerability
  finding.
- **ioredis 5.11.1 — Snyk HIGH, Uncontrolled Recursion in the RESP
  parser** (crafted nested-array byte streams → stack exhaustion →
  process crash); remediation is ioredis ≥ 6.0.0-beta.1. Exploitable
  only from a malicious/compromised Redis endpoint — in this
  deployment Redis is trusted localhost, so residual risk is **Low
  in practice**. Not upgraded blindly (major version, CJS
  constraint); recorded as a known risk.
- **Redis server 7.0.15 — CVE-2024-31228** (authenticated-user DoS
  via long match patterns; fixed in 6.2.16 / 7.2.6 / 7.4.1). Local
  dev exposure only (localhost, no auth); **production Redis must
  be ≥7.2.6 with auth and a private network**.

This is an advisory search, not a full audit. Run `npm audit`
(or an equivalent scanner) in an environment where the registry
allows it before any production release.

## Verified (by tests in this tree)

- **Passwords:** Argon2id 64 MiB / 3 / 1, per-password salt;
  `password_hash` never selected except on the auth path, never
  serialised, never logged (log test asserts it).
- **Sessions:** `sid` revocation check on every REST request and
  every socket message; logout takes effect immediately (REST +
  socket e2e tests). Refresh-token reuse revokes the whole family.
- **Tokens at rest:** refresh tokens and email tokens are SHA-256
  hashed; email tokens are single-use with a partial unique index
  guaranteeing one live token per purpose.
- **Enumeration resistance:** register, login, forgot-password, and
  verify-email/resend return neutral responses; account-status
  checks on login run only after a correct password (security
  suite asserts this).
- **Injection / malformed input:** SQL-injection attempts,
  oversized bodies (413), malformed JSON (400), malformed socket
  payloads (`VALIDATION_FAILED`, connection survives) — all covered
  by security + socket e2e tests. Unknown fields are stripped
  (whitelist) on both transports.
- **Secrets in logs:** a test asserts no password/token appears in
  log output; the pino redaction list covers `password`,
  `*token*`, `authorization`, `mfa*`, `JWT_PRIVATE_KEY`,
  `DATABASE_URL`, `REDIS_URL`. Socket logs carry `userId` +
  `socketId` only.
- **Rate limiting:** login throttle (5 failures / 15 min per
  account and per IP), per-endpoint limits, 100/min per
  authenticated user, 20/s per socket with disconnect on sustained
  abuse — all covered by unit + e2e tests. All 429s carry
  `Retry-After`.
- **Fail-closed where it matters:** Redis down fails closed for
  auth writes, the login throttle, and the socket rate-limit guard;
  production boot fails fast without real JWT keys, a real mailer
  provider, or a non-localhost database URL.
- **Boot resilience:** a dead Redis no longer kills the process
  (H-01); a dead database now fails fast (M-02). No bootstrap path
  in this tree depends on the adapter's pub/sub being live.
- **Trust proxy:** `TRUST_PROXY` is validated and wired; per-IP
  limits behave correctly behind a proxy (H-03, live probe).
- **Concurrent writes:** duplicate registration is a 409, not a
  500 (H-02); email-token issue retries once on a unique-index
  race.
- **CORS preflight:** live probe — `OPTIONS` with an `Origin`
  header returns 204 from the cors middleware before any guard,
  so preflight is never 401'd. Swagger serves in development
  (`/v1/docs` → 200); the production gate is a single
  `if (nodeEnv !== 'production')` around `SwaggerModule.setup`.
  A live production-mode boot probe was not possible in this VM
  (production requires non-loopback DB/Redis URLs; local
  PostgreSQL/Redis bind 127.0.0.1 only), so the prod gate is
  proven by code, not by a live prod boot.
- **SQL injection:** no string-concatenated SQL anywhere. The only
  raw SQL is static DDL in migrations 0001/0002, `SELECT 1` in
  health, and parameter-less query-builder deletes in the purge
  job. All app queries go through TypeORM repositories /
  parameterised `findOne` / `update`.

## Assumptions (true by construction here, not by external proof)

- The deployment terminates TLS in front of the app (the app binds
  plain HTTP on `127.0.0.1`); NFR-14 is a deployment property.
- PostgreSQL and Redis are reachable only from the app host in
  production (local setup binds both to `127.0.0.1` with no
  password — that is a dev posture, not a production one).
- `RULESET_VERSION` matches the Flutter ruleset (BR-14) — asserted
  by the vector loader, not by a deployed-client check.
- The `log` mailer is dev/test only; production requires `smtp`
  (fail-fast enforces it).

## Remaining risks / open items (not verified, not claimed)

- **No production deployment exists yet** — no container image,
  no reverse proxy / TLS configuration, no production backup
  (NFR-34: daily backup, RPO ≤ 24 h, RTO ≤ 4 h, restore rehearsed),
  no load testing, no penetration test, no third-party security
  audit. Green local tests are not a production-security claim.
- **No CI** — no `.github/workflows/` file is part of this work
  (Workflows permission 403); verification is local command output
  only.
- **Mailer provider selection is still open (OD-09)** — the `smtp`
  transport is wired, but no provider has been chosen or verified
  end-to-end with real delivery.
- **Account-deletion anonymisation is not implemented (OD-08)** —
  `DELETE /users/me` is marker + session revoke only; personal
  data is not anonymised.
- **Socket abuse limits are foundation values** — 20 events/s and
  the 5-violation disconnect threshold are `[P4 choice]` values
  (the plan is silent on the count); they have not been tuned
  against real client behaviour or a load test.
- **Node version variance** — the SDD pins Node 22 LTS; this work
  was run on Node v24.22.1 with no variance hit, but Node 22
  itself has not been exercised in this environment.
- **Dependency pins** — several Nest packages are pinned to
  CJS-compatible lines because v12 is ESM-only under this CommonJS
  setup (`@nestjs/jwt` 11.0.2, `@nestjs/passport` 11.0.5,
  `@nestjs/schedule` 6.1.3, `@nestjs/websockets` /
  `@nestjs/platform-socket.io` 11.2.12, `socket.io` 4.8.3,
  `@socket.io/redis-adapter` 8.2.1). Upgrading to v12 needs an ESM
  migration of the backend; until then, security patches on those
  lines must be tracked manually.
- **No MFA, no admin role, no audit log** — none exists in Phase 4
  scope.
- **L-01 — No global/IP rate limit for unauthenticated requests
  to protected routes.** `JwtAuthGuard` 401s before
  `RateLimitGuard`, so floods against protected routes hit RS256
  verification unbounded. Recommend Phase 5 add a global per-IP
  limit exempting health. (Medium in effect; Low urgency in
  Phase 4, no game traffic yet.)
- **L-02 — No per-IP/per-user socket connection rate limit.**
  A handshake flood costs an RS256 verify + 2 DB lookups per
  connection; reconnecting resets the per-socket event budget.
  Recommend Phase 5 add a connection rate limit keyed on IP.
- **L-03 — Concurrent double-present of a refresh token revokes
  the whole family by design** (SDD-prescribed): a client retry
  after a lost response looks like token theft. Documented, not a
  defect.
- **L-04 — Email-token 410-vs-401 distinguishes token
  existence** (negligible: 256-bit tokens) plus timing side
  channels on neutral endpoints. Accepted.
- **L-05 — Change password allows new == old; no dedicated
  throttle** beyond 100/min. Recommend Phase 5 add a
  new≠old check and a tighter throttle.
- **L-06 — User email addresses appear in log lines** (AuthService
  register warn, mailer services) — operational PII, not secrets.
  Accepted for Phase 4; revisit if logs leave the host.
- **L-07 — ioredis 5.11.1 RESP-parser recursion (Snyk High).**
  See "Dependency vulnerabilities" above.
- **L-08 — Redis server 7.0.15 CVE-2024-31228.** See above;
  production Redis must be ≥7.2.6.
- **L-09 — `npm audit` unavailable** (registry policy 403). See
  above; run a real audit before any production release.
- **L-10 — Dev DB password committed as a default** in
  `test/integration/test-helpers.ts`
  (`postgres://diceup:diceup_dev_local_only@localhost:5432/postgres`).
  Localhost-only dev credential, overridable via
  `TEST_ADMIN_DATABASE_URL`. Accepted for test tooling.
- **L-11 — `MAILER_API_KEY` is validated in the Joi schema but no
  code reads it** (reserved for a future mailer provider, unwired).
  Harmless; remove or wire it when the provider is chosen (OD-09).
- **L-12 — `X-Request-Id` vs `correlationId` can differ on error
  paths** (M-04 note above). The body's `correlationId` is
  authoritative.
- **L-13 — Socket 10 KB cap is measured in UTF-16 code units**
  (`JSON.stringify` length), not bytes; the engine.io
  `maxHttpBufferSize` default of 1 MB is the byte-level backstop
  (verified in `node_modules/engine.io/build/server.js:478`).
- **L-14 — Refresh-token TTL is 30 days** (a `[P4 choice]`).
  Accepted for Phase 4; revisit for production.
- **L-15 — Minor duplication:** the email-hash key derivation is
  implemented twice (`LoginThrottleService.accountKey` and
  `hashRateLimitEmail`); both are SHA-256 of the lowercased email.
  Cosmetic.
- **L-16 — Declared-but-unwired surface:** `PushSender`
  interface has no implementation; cursor-pagination helpers and
  `acquireLock`/`releaseLock` are unused; `deviceLabel` is always
  null. Planned for later stages, not dead code in the harmful
  sense — but Stage 5 should either wire them or remove them
  before they become stale.

## Quality review (Stage 4)

- **No circular dependencies** — Nest would fail at boot if any
  existed; the full e2e suite boots the whole module graph.
- **No business logic in controllers** — controllers are thin
  (validation → service → response mapping).
- **No giant services** — the largest, `AuthService`, is ~300
  lines and cohesive.
- **Dead code:** nothing harmful found. The declared-but-unwired
  items are listed as L-16 above rather than deleted, because
  they are planned Phase 5 surface.
- **Test counts (Stage 4 final run):** unit 156 passed / 0 failed
  (22 suites); e2e 73 passed / 0 failed (8 suites). Jest prints
  "did not exit one second after the test run has completed" on
  e2e runs — verified pre-existing on the Stage 3 baseline
  (open ioredis/socket handles after `app.close()`), not caused
  by Stage 4.
