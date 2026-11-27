# Setup guide — DiceUp backend (Stages 2a–2c)

## Prerequisites

- Node 22 LTS, npm 10+ (`engines` in `package.json` pins
  `>=22 <23`; this VM runs Node v24.22.1 — no 24-vs-22 variance has
  been hit; `argon2` loads its native prebuild fine on 24).
- PostgreSQL 16, Redis 7.
- No Docker is used in this environment (the SDD §15.2 container
  suggestion does not apply here); local services are used instead.

## 1. Start PostgreSQL and Redis (this VM)

```bash
# PostgreSQL cluster 16/main (was DOWN on arrival; start it):
pg_ctlcluster 16 main start
pg_lsclusters          # expect: 16 main 5432 online

# Redis (localhost only, no persistence):
redis-server --daemonize yes --port 6379 --save '' --appendonly no \
  --protected-mode yes --bind 127.0.0.1
redis-cli ping         # expect: PONG
```

Create the local role and database (run once, as the `postgres` OS
user):

```bash
sudo -u postgres psql -c \
  "CREATE ROLE diceup LOGIN CREATEDB PASSWORD 'diceup_dev_local_only';"
sudo -u postgres psql -c "CREATE DATABASE diceup_dev OWNER diceup;"
```

The password above is a **local-dev-only** credential. It appears in
`.env` (git-ignored) and in test-code defaults for the local cluster
only. Never use it anywhere else; never commit a real `.env`.

## 2. Configure

```bash
cd backend
cp .env.example .env   # then fill in local values (see below)
```

> **The `.env.example` password is a placeholder, not the real one.**
> `.env.example` ships `DATABASE_URL` with a 9-character placeholder
> password. After copying it, replace that password with the
> local-dev-only password from §1 (`diceup_dev_local_only` — the one
> in the `CREATE ROLE` command). If you skip this step, `npm run
> migration:run` fails with `password authentication failed for user
> "diceup"` (Postgres `28P01`) — the server never starts. (Found by
> Stage 3 following this guide literally from a clean clone.)

Minimum local `.env` (after the password fix above):

```env
NODE_ENV=development
PORT=3000
DATABASE_URL=postgres://diceup:diceup_dev_local_only@127.0.0.1:5432/diceup_dev
REDIS_URL=redis://127.0.0.1:6379
RULESET_VERSION=1.0.0
```

The full variable reference — including what production additionally
requires — is `03-environment.md`.

### RS256 keys (dev)

Generate a dev-only keypair (RSA 2048) and point `.env` at it:

```bash
mkdir -p .keys
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
  -out .keys/dev-private.pem
openssl pkey -in .keys/dev-private.pem -pubout -out .keys/dev-public.pem
```

```env
JWT_PRIVATE_KEY_FILE=.keys/dev-private.pem
JWT_PUBLIC_KEY_FILE=.keys/dev-public.pem
```

`.keys/` is git-ignored. **Never commit a key; never use dev keys in
production.** Inline PEM in `JWT_PRIVATE_KEY` / `JWT_PUBLIC_KEY` wins
over the file form when both are set. With no keys configured, dev/test
boot generates an ephemeral in-memory keypair (warning logged; tokens
die on restart). Production boot fails fast without real keys.

## 3. Install, migrate, run

```bash
npm ci
npm run migration:run  # applies 0001 + 0002 to DATABASE_URL — dev DB only
npm run start:dev      # http://127.0.0.1:3000/v1/health
```

Check it is up:

```bash
curl http://127.0.0.1:3000/v1/health
# {"success":true,"data":{"status":"ok"}}
curl http://127.0.0.1:3000/v1/health/ready
# {"success":true,"data":{"status":"ok","database":"up","redis":"up",
#   "latencyMs":{"database":8,"redis":1}}} — 200 only if both
# PostgreSQL and Redis answer; otherwise 503 with error.data naming
# each dependency (up/down) plus per-check latency in ms.
# (Stage 3 correction: there is no `checks` object in the response;
# the per-dependency fields sit directly on `data`.)
```

Swagger (non-production only): `http://127.0.0.1:3000/v1/docs`.

## Tests

```bash
npm test          # unit tests
npm run test:e2e  # integration + security + vectors (real PostgreSQL + real Redis)
npm run typecheck && npm run lint && npm run format:check && npm run build
```

Integration tests create a scratch database
`diceup_test_<pid>_<random>` on the local cluster, run all
migrations, verify the schema, run, and drop it. They never touch
`diceup_dev` or any shared/production service. See `09-testing.md`.

## Production (what exists, what does not)

What exists: fail-fast config validation at boot (missing production
variables → named error, exit non-zero); production refuses a
`DATABASE_URL` pointing at localhost; the app binds plain HTTP and
expects TLS termination in front of it; the mailer fails fast in
production unless a real provider is selected.

What does **not** exist yet: no production deployment, no container
image, no reverse-proxy/TLS configuration, no production backup
(NFR-34 is an operations concern — the local `pg_dump` command for
the dev cluster is in `04-database.md`), no load testing, no CI
(no `.github/workflows/` file is part of this work and no CI pass is
claimed; evidence is local command output). Do not present this
backend as production-ready on the strength of these docs alone —
see `10-security.md` for the honest risk list.
