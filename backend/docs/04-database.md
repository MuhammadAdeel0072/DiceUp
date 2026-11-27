# Database setup + migrations

PostgreSQL 16 via TypeORM + `pg`. `synchronize` is **never** on
(asserted by a unit test); schema changes only via migrations.

## Local setup

```bash
pg_ctlcluster 16 main start
pg_lsclusters          # expect: 16 main 5432 online

sudo -u postgres psql -c \
  "CREATE ROLE diceup LOGIN CREATEDB PASSWORD 'diceup_dev_local_only';"
sudo -u postgres psql -c "CREATE DATABASE diceup_dev OWNER diceup;"
```

`DATABASE_URL` for dev:
`postgres://diceup:diceup_dev_local_only@127.0.0.1:5432/diceup_dev`
(the password is local-dev-only; never use it elsewhere).

## Schema — exactly four tables (SDD §9.2)

| Table | Purpose |
|---|---|
| `users` | Identity, `status`, `email_verified_at`, `deletion_requested_at` (`[P4 choice]`). |
| `profiles` | One row per user: display name, avatar key, `notification_preferences` JSONB (added by migration 0002). |
| `auth_sessions` | One row per login: opaque refresh token (SHA-256 hashed at rest), `family_id` (`[P4 choice]`, reuse revocation), expiry. |
| `email_tokens` | Single-use verification / password-reset codes (256-bit, hashed at rest). Partial unique index `(user_id, purpose) WHERE used_at IS NULL`. |

Indexes include the SDD §9.3 set (`users(status, created_at)`,
`auth_sessions(user_id, expires_at)`) and the `citext` extension
(migration 0001 creates it).

Entity properties are camelCase; migration columns are snake_case.
`SnakeNamingStrategy` (`src/database/naming.strategy.ts`) maps them
— without it every repository query fails
(`column User.emailVerifiedAt does not exist`), a latent Stage 2a
defect found by Stage 2b's first repository query.

## Migrations

Files live in `src/database/migrations/`:

- `0001_init-auth` — creates the four tables verbatim from SDD §9.2
  (plus the two documented `[P4 choice]` columns), the `citext`
  extension, and the §9.3 indexes.
- `0002_add-profile-preferences` — adds
  `profiles.notification_preferences` JSONB. The plan (§2.1.1 FR-08)
  says the persistence column lives on `profiles`, but 0001 did not
  create it; 0001 is never edited — schema changes only via new
  migrations (expand-then-contract, SDD §15.4).

Commands (TypeORM CLI via `src/database/data-source.ts`):

```bash
npm run migration:run     # apply pending migrations to DATABASE_URL
npm run migration:show    # list applied / pending migrations
npm run migration:revert  # revert the last applied migration
npm run migration:generate # generate a migration from entity diffs
```

Run migrations against a scratch/dev database, never production.
The integration tests run all migrations against a fresh scratch
database on every run (`09-testing.md`).

## Local backup (dev cluster only)

```bash
pg_dump -U diceup -d diceup_dev > diceup_dev.sql
```

NFR-34 (PostgreSQL daily backup, RPO ≤ 24 h, RTO ≤ 4 h, restore
rehearsed) is an operations concern: no production backup is set up
or claimed here.
