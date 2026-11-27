# Environment-variable reference

Validated with `@nestjs/config` + Joi (`src/config/`). No secret
value is ever included in a validation error message. There is no
default JWT key, database URL, or password anywhere.

## Required in every environment

| Variable | Example | Notes |
|---|---|---|
| `NODE_ENV` | `development` | `development` \| `test` \| `production` (default `development`). |
| `PORT` | `3000` | Port the app binds on `127.0.0.1` (default 3000). |
| `DATABASE_URL` | `postgres://diceup:…@127.0.0.1:5432/diceup_dev` | PostgreSQL 16 connection string (URI, required). |
| `REDIS_URL` | `redis://127.0.0.1:6379` | Redis 7 connection string (URI, required). |

## Optional in dev/test, required in production

Production boot fails fast (named error listing only the *names* of
missing variables, exit non-zero) when any of these is missing — see
`validateProductionConfig` in `src/config/config.validation.ts`.
Production also refuses a loopback `DATABASE_URL` or `REDIS_URL`
(`localhost`, `127.0.0.1`, `::1`) — Stage 4, M-06: the old check only
caught the literal string `localhost` in `DATABASE_URL`.

| Variable | Default | Notes |
|---|---|---|
| `JWT_PRIVATE_KEY` | — | Inline PEM (RS256 signing key). Wins over `_FILE` when both are set. |
| `JWT_PUBLIC_KEY` | — | Inline PEM (RS256 verification key). Wins over `_FILE` when both are set. |
| `JWT_PRIVATE_KEY_FILE` | — | Path to the private-key PEM, resolved relative to the process working directory (`backend/` when run from `backend/`). Recommended dev path: `.keys/dev-private.pem`. |
| `JWT_PUBLIC_KEY_FILE` | — | Path to the public-key PEM. Recommended dev path: `.keys/dev-public.pem`. |
| `JWT_ISSUER` | `diceup` | `iss` claim on access tokens. |
| `RULESET_VERSION` | `1.0.0` | BR-14: must match `diceup_app/test/vectors/rules.json` and the Dart `RulesetConfig` default. The vector loader in `test/vectors/` asserts this. |
| `CORS_ORIGINS` | (empty) | Comma-separated allow-list, no wildcard. Empty in dev means CORS is effectively off (`origin: false`); production requires at least one origin. |
| `MAILER_PROVIDER` | (unset = `log`) | Mail transport selector. `log` (default, dev/test) stores messages in memory and logs recipient + kind only — never sends real email, never logs a token. `smtp` sends via nodemailer. Production with anything but a real provider fails fast. Provider selection is still OPEN (OD-09). |

## Optional

| Variable | Default | Notes |
|---|---|---|
| `LOG_LEVEL` | `info` | `fatal` \| `error` \| `warn` \| `info` \| `debug` \| `trace` (pino). |
| `TRUST_PROXY` | `0` (trust nobody) | Express `trust proxy` hop count. Set to `1` in production behind a single TLS-terminating reverse proxy — otherwise `req.ip` is the proxy for every client and the per-IP rate limits / login throttle collapse into one shared bucket (Stage 4, H-03). Never set when clients connect directly. |
| `MAILER_FROM` | — | Sender address for the SMTP transport. |
| `MAILER_SMTP_HOST` | — | SMTP host. |
| `MAILER_SMTP_PORT` | — | SMTP port. |
| `MAILER_SMTP_USER` | — | SMTP username. |
| `MAILER_SMTP_PASS` | — | SMTP password. |
| `MAILER_API_KEY` | — | Reserved for a future API-based provider (not wired to any transport yet). |

## Precedence gotcha (read this before debugging config)

`ConfigService.get()` checks the Joi-**validated** env store before
`process.env`, and that store is frozen at `ConfigModule.forRoot()`
time (import time) from `backend/.env` — so a top-level key such as
`DATABASE_URL` / `REDIS_URL` read via `config.get('DATABASE_URL')`
silently ignores a shell-env override set later. This is worse than
it looks: Stage 3 proved it made **every e2e suite run against
`diceup_dev` instead of its scratch database** — the helpers set
`process.env.DATABASE_URL` to the scratch URL, but
`DatabaseModule` read the frozen validated value, so 523 test users
accumulated in `diceup_dev` while the scratch DBs stayed empty
(and were dropped). The fix (Stage 3): the app reads the
**namespaced** keys — `config.get('app.databaseUrl')` /
`config.get('app.redisUrl')` — whose `registerAs('app')` factory
reads live `process.env` when `ConfigService` is created, so it
honours assignments made before boot. Auth and Mailer already used
the `app` namespace; Database, Redis, and the socket Redis clients
were switched to it. Rules:

- Never read a top-level env key via `ConfigService.get()` in app
  code — use the `app.*` namespace (the factory in
  `src/config/configuration.ts`).
- Never ship a `.env` file alongside shell env in any shared or test
  environment.
- In tests, prefer provider overrides over env mutation (the
  dead-Redis readiness test overrides the `REDIS_CLIENT` provider).
- `appConfig` in `main.ts` reads `process.env` directly, so the two
  paths can disagree — if a value looks wrong, check for a stale
  `.env` first.
- Regression guard: `test/integration/full-journey.e2e.spec.ts`
  asserts the booted app's `DataSource` URL names the scratch
  database and that it starts empty.
