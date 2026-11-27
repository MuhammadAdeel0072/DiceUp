# Testing instructions

## Commands

```bash
npm test          # unit tests (jest --config test/jest-unit.json)
npm run test:e2e  # integration + security + vectors
                  # (jest --config test/jest-e2e.json --runInBand)
npm run test:cov  # unit tests with coverage
npm run typecheck && npm run lint && npm run format:check && npm run build
```

Unit tests must be green before any commit; the e2e suite must be
green before a stage is reported done. Never weaken assertions or
delete tests to get green — fix the defect, or report it as BLOCKED
with evidence.

## Unit tests (`test/unit/`)

Pure, fast, no external services (Redis is faked where a service
needs it; config/DB-options tests assert static properties). They
cover: config validation + production fail-fast, database options
(`synchronize` never on), naming strategy, pagination, password
hasher, token service, JWT keys, JWT strategy, login throttle,
rate-limit guard/service, guards, DTO validation, mailers (log +
SMTP), the session/token purge job, and the socket pieces
(`WsJwtGuard`, `WsValidationPipe`, socket rate-limit service/guard).

Current count (Stage 5, re-measured 2026-11-27 — the Stage 3 figure
of 143 / 19 suites below was stale; Stage 4 had already reached 156):
**156 unit tests, all passing (22 suites)**.

## Integration tests (`test/integration/`, real PostgreSQL + real Redis)

Never SQLite / in-memory substitutes. Each run:

1. Creates a scratch database `diceup_test_<pid>_<random>` on the
   local PostgreSQL 16 cluster.
2. Runs **all** migrations against it and verifies the schema.
3. Runs the specs, then drops the scratch database.

They never touch `diceup_dev` or any shared/production service.
(Stage 3 correction: before the Stage 3 config fix this claim was
FALSE — every e2e suite was silently running against `diceup_dev`
because `ConfigService.get('DATABASE_URL')` reads the Joi-validated
env store frozen from `backend/.env` at import time; 523 test users
had accumulated there. Database/Redis/socket clients now read the
`app.*` namespace, which follows live `process.env`, and
`full-journey.e2e.spec.ts` regresses it. See `03-environment.md`.)
Prerequisites: the local cluster and Redis running (see
`02-setup.md`). A stale `backend/.env` will silently override
shell env for `DATABASE_URL`/`REDIS_URL` — do not ship one
alongside shell env in tests (see `03-environment.md`).

Suites:

| File | Covers |
|---|---|
| `auth.e2e.spec.ts` | Auth flows end-to-end: register → verify → login → refresh → logout, refresh-token reuse revocation, forgot/reset. |
| `authz-matrix.e2e.spec.ts` | Authorization matrix (4 routes × 8 account states). |
| `health.e2e.spec.ts` | Liveness, readiness (both deps up / Redis down / PostgreSQL down). |
| `socket.e2e.spec.ts` | Socket gateway: boots on the Redis adapter; auth refusals (no/bad/revoked/unverified/suspended token); `ping`/`pong`; malformed + oversized payloads rejected with the standardized error; clean disconnect + reconnect; 21-event burst (20 pongs + `RATE_LIMITED`); sequential 30-event flood (20 pongs, ≥4 `RATE_LIMITED`, disconnect); two-node broadcast via the Redis adapter. |
| `full-journey.e2e.spec.ts` | (Stage 3) The whole backend as one system on a live server: register → verify → login → `GET /users/me` → Socket.IO `/game` connect with the same token → `ping`/`pong` → refresh → logout → old token fails REST (401) + socket (`connect_error`) → refresh reuse revokes the family; plus readiness (deps up / Redis down → 503), login rate limit firing, expired token on both transports, no secrets in logs, and a regression test that the app uses the scratch DB (see below). |
| `redis-down.e2e.spec.ts` | (Stage 4, H-01) Boots the app with Redis down: liveness 200, readiness 503 with `redis: down` / `database: up`, register fails closed 503. Proves a dead Redis no longer kills the process at boot. |
| `auth-security.e2e.spec.ts` | (security) Enumeration resistance, SQL-injection strings, oversized/malformed bodies, no secrets in logs; (Stage 4, H-02) concurrent duplicate registration → one 201 + one 409, never a 500. |

Rate-limit counters are cleared before each test (all supertest
traffic comes from one IP by design); rate-limit tests build their
flood inside a single test. Socket tests use `socket.io-client`
with `reconnection: false` and register the `connected` listener
immediately after `io()` creation — the server emits `connected`
from `handleConnection`, so a listener attached only after
`connect` resolves can miss it.

## Security tests (`test/security/`)

Enumeration resistance (register/login/forgot-password leak
nothing), SQL injection attempts, oversized/malformed bodies, and
a log-output test asserting no password/token ever appears in logs.

## Ruleset vectors (`test/vectors/`)

`rules-vectors.loader.ts` validates every embedded ruleset in
`diceup_app/test/vectors/rules.json` for coherence and asserts the
canonical default case matches `RULESET_VERSION` (BR-14 / NFR-39).
17/23 vector cases embed the defaults; 6 are deliberate
single-field variants — the loader does not require all 23 to
equal the defaults.

## Current counts (Stage 5, own runs, 2026-11-27)

| Suite | Total | Passed | Failed | Skipped |
|---|---|---|---|---|
| Unit (`npm test`) | 156 | 156 | 0 | 0 |
| E2E (`npm run test:e2e`) | 73 | 73 | 0 | 0 |
| **Total** | **229** | **229** | **0** | **0** |

Per-suite unit counts (verbose re-run): `ws-jwt.guard` 20,
`naming-strategy` 24, `dto-validation` 12, `guards` 12, `jwt-keys` 8,
`rate-limit` 8, `jwt-strategy` 8, `socket-rate-limit` 8,
`ws-validation.pipe` 8, `token.service` 6, `login-throttle` 6,
`config.validation` 5, `redis.service` 5, `password-hasher` 5,
`trust-proxy` 4, `database-options` 3, `config-precedence` 3,
`unique-violation` 3, `mailer` 3, `email-token` 2, `pagination` 2,
`cleanup` 1 (22 suites).

Per-suite e2e counts (verbose re-run): `auth` 31, `socket` 13,
`full-journey` 8, `health` 6, `auth-security` 6, `rules-vectors` 4,
`redis-down` 3, `authz-matrix` 2 (the 2 matrix tests contain 32
route×state assertions: 4 routes × 8 states) (8 suites).

(Stage 3 added `test/integration/full-journey.e2e.spec.ts`: 8 tests.
Stage 4 added `test/integration/redis-down.e2e.spec.ts` (H-01) and
`test/unit/trust-proxy.spec.ts` (H-03); the e2e total moved 68 → 73
and the unit total 143 → 156. The previous version of this file
still showed the Stage 3 numbers — corrected by Stage 5.)

`npm run typecheck`, `npm run lint`, `npm run format:check`, and
`npm run build` all exit 0. No CI exists (no `.github/workflows/`
file is part of this work); these numbers are local command output.
