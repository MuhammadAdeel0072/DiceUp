import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * 0001_init-auth — the four Phase 4 tables, verbatim from SDD §9.2.
 * Implements: FR-02/03/04/05/06, NFR-13/15.
 *
 * Deviation from the plan (§4.4 numbering): TypeORM requires the
 * migration *class* name to end in a JavaScript timestamp, so the class
 * is `InitAuth1764240000000` (2026-11-27) while the file keeps the
 * plan's `0001_init-auth.ts` numbering. The `migrations` table records
 * the class name; the file name is the human ordering.
 *
 * [P4 choice] columns (plan §4.1, §11.1 D-P4-08/D-P4-09):
 *   users.deletion_requested_at, auth_sessions.family_id.
 * Child FKs use ON DELETE CASCADE so no orphaned session/token rows
 * survive a user row (SDD names CASCADE only for profiles; CASCADE for
 * the other children is the conventional choice and is recorded here).
 * Requires the `citext` extension for case-insensitive uniqueness
 * (FR-02); created by this migration (migration role), not the app role.
 * Expand-then-contract (SDD §15.4) applies from this migration onward.
 */
export class InitAuth1764240000000 implements MigrationInterface {
  name = 'InitAuth1764240000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS "citext"`);

    await queryRunner.query(`
      CREATE TABLE "users" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "email" citext NOT NULL,
        "username" citext NOT NULL,
        "password_hash" text NOT NULL,
        "status" text NOT NULL DEFAULT 'active',
        "email_verified_at" timestamptz,
        "deletion_requested_at" timestamptz,
        "created_at" timestamptz NOT NULL DEFAULT now(),
        "updated_at" timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT "CHK_users_status" CHECK ("status" IN ('active', 'suspended', 'blocked')),
        CONSTRAINT "PK_users" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_users_email" UNIQUE ("email"),
        CONSTRAINT "UQ_users_username" UNIQUE ("username")
      )`);
    await queryRunner.query(
      `CREATE INDEX "IDX_users_status_created_at" ON "users" ("status", "created_at")`,
    );

    await queryRunner.query(`
      CREATE TABLE "profiles" (
        "user_id" uuid NOT NULL,
        "display_name" varchar(50) NOT NULL,
        "avatar_key" varchar(50) NOT NULL DEFAULT 'default',
        "matches_played" integer NOT NULL DEFAULT 0,
        "matches_won" integer NOT NULL DEFAULT 0,
        "updated_at" timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT "PK_profiles" PRIMARY KEY ("user_id"),
        CONSTRAINT "FK_profiles_user" FOREIGN KEY ("user_id")
          REFERENCES "users" ("id") ON DELETE CASCADE
      )`);

    await queryRunner.query(`
      CREATE TABLE "auth_sessions" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "user_id" uuid NOT NULL,
        "refresh_token_hash" text NOT NULL,
        "family_id" uuid,
        "device_label" text,
        "expires_at" timestamptz NOT NULL,
        "revoked_at" timestamptz,
        "created_at" timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT "PK_auth_sessions" PRIMARY KEY ("id"),
        CONSTRAINT "FK_auth_sessions_user" FOREIGN KEY ("user_id")
          REFERENCES "users" ("id") ON DELETE CASCADE
      )`);
    await queryRunner.query(
      `CREATE INDEX "IDX_auth_sessions_user_expires" ON "auth_sessions" ("user_id", "expires_at")`,
    );

    await queryRunner.query(`
      CREATE TABLE "email_tokens" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "user_id" uuid NOT NULL,
        "purpose" text NOT NULL,
        "token_hash" text NOT NULL,
        "expires_at" timestamptz NOT NULL,
        "used_at" timestamptz,
        "created_at" timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT "CHK_email_tokens_purpose" CHECK ("purpose" IN ('verify', 'reset')),
        CONSTRAINT "PK_email_tokens" PRIMARY KEY ("id"),
        CONSTRAINT "FK_email_tokens_user" FOREIGN KEY ("user_id")
          REFERENCES "users" ("id") ON DELETE CASCADE
      )`);
    // SDD §9.2 partial unique: at most one live token per (user, purpose).
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_email_tokens_live" ON "email_tokens" ("user_id", "purpose") WHERE "used_at" IS NULL`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "email_tokens"`);
    await queryRunner.query(`DROP TABLE "auth_sessions"`);
    await queryRunner.query(`DROP TABLE "profiles"`);
    await queryRunner.query(`DROP TABLE "users"`);
  }
}
