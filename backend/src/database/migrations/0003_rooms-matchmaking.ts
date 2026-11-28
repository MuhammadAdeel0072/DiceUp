import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * 0003_rooms-matchmaking — the Phase 5 Stage 3 tables (SDD §9.2),
 * verbatim from the Phase 5 assessment §4.
 *
 * Implements: FR-43/44/45/46/47/59, FR-58 (match rows), FR-53
 * (move_events idempotency unique index), G-4/C-11 (seeded
 * game_configurations row: turn 30 s, grace 60 s, missed-turn
 * limit 3, max room players 4, version = RULESET_VERSION 1.0.0).
 *
 * Expand-then-contract (SDD §15.4): all new tables, nothing altered.
 * `rooms.code` is UNIQUE only among open rooms (partial index):
 * a closed room's code may be reused later. `matches.room_id` is
 * UNIQUE: one room → at most one match. `room_members` PK
 * (room_id, user_id) and `match_players` PK (match_id, user_id)
 * are the TOCTOU guards for concurrent joins (23505, never a
 * silent double-seat). Child FKs use ON DELETE CASCADE so no
 * orphaned member/player/event rows survive a room/match row.
 */
export class RoomsMatchmaking1795822100000 implements MigrationInterface {
  name = 'RoomsMatchmaking1795822100000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "rooms" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "code" varchar(6) NOT NULL,
        "host_id" uuid NOT NULL,
        "max_players" integer NOT NULL,
        "status" text NOT NULL DEFAULT 'open',
        "ruleset_version" text NOT NULL,
        "source" text NOT NULL DEFAULT 'manual',
        "created_at" timestamptz NOT NULL DEFAULT now(),
        "closed_at" timestamptz,
        CONSTRAINT "CHK_rooms_max_players" CHECK ("max_players" BETWEEN 2 AND 4),
        CONSTRAINT "CHK_rooms_status" CHECK ("status" IN ('open', 'playing', 'closed')),
        CONSTRAINT "CHK_rooms_source" CHECK ("source" IN ('manual', 'matchmaking')),
        CONSTRAINT "PK_rooms" PRIMARY KEY ("id"),
        CONSTRAINT "FK_rooms_host" FOREIGN KEY ("host_id")
          REFERENCES "users" ("id") ON DELETE CASCADE
      )`);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_rooms_code_open" ON "rooms" ("code") WHERE "status" = 'open'`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_rooms_host_status" ON "rooms" ("host_id", "status")`,
    );

    await queryRunner.query(`
      CREATE TABLE "room_members" (
        "room_id" uuid NOT NULL,
        "user_id" uuid NOT NULL,
        "is_ready" boolean NOT NULL DEFAULT false,
        "is_host" boolean NOT NULL DEFAULT false,
        "joined_at" timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT "PK_room_members" PRIMARY KEY ("room_id", "user_id"),
        CONSTRAINT "FK_room_members_room" FOREIGN KEY ("room_id")
          REFERENCES "rooms" ("id") ON DELETE CASCADE,
        CONSTRAINT "FK_room_members_user" FOREIGN KEY ("user_id")
          REFERENCES "users" ("id") ON DELETE CASCADE
      )`);
    await queryRunner.query(
      `CREATE INDEX "IDX_room_members_user" ON "room_members" ("user_id")`,
    );

    await queryRunner.query(`
      CREATE TABLE "matches" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "room_id" uuid NOT NULL,
        "ruleset_version" text NOT NULL,
        "status" text NOT NULL DEFAULT 'in_progress',
        "winner_id" uuid,
        "started_at" timestamptz NOT NULL DEFAULT now(),
        "ended_at" timestamptz,
        CONSTRAINT "CHK_matches_status" CHECK ("status" IN ('in_progress', 'completed', 'cancelled')),
        CONSTRAINT "PK_matches" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_matches_room" UNIQUE ("room_id"),
        CONSTRAINT "FK_matches_room" FOREIGN KEY ("room_id")
          REFERENCES "rooms" ("id") ON DELETE CASCADE,
        CONSTRAINT "FK_matches_winner" FOREIGN KEY ("winner_id")
          REFERENCES "users" ("id") ON DELETE SET NULL
      )`);
    await queryRunner.query(
      `CREATE INDEX "IDX_matches_winner_ended" ON "matches" ("winner_id", "ended_at")`,
    );

    await queryRunner.query(`
      CREATE TABLE "match_players" (
        "match_id" uuid NOT NULL,
        "user_id" uuid NOT NULL,
        "seat" integer NOT NULL,
        "colour" text NOT NULL,
        "result" text,
        "finish_rank" integer,
        "missed_turns" integer NOT NULL DEFAULT 0,
        CONSTRAINT "CHK_match_players_seat" CHECK ("seat" BETWEEN 0 AND 3),
        CONSTRAINT "CHK_match_players_result" CHECK ("result" IN ('win', 'loss', 'forfeit')),
        CONSTRAINT "PK_match_players" PRIMARY KEY ("match_id", "user_id"),
        CONSTRAINT "FK_match_players_match" FOREIGN KEY ("match_id")
          REFERENCES "matches" ("id") ON DELETE CASCADE,
        CONSTRAINT "FK_match_players_user" FOREIGN KEY ("user_id")
          REFERENCES "users" ("id") ON DELETE CASCADE
      )`);
    await queryRunner.query(
      `CREATE INDEX "IDX_match_players_user_match" ON "match_players" ("user_id", "match_id")`,
    );

    await queryRunner.query(`
      CREATE TABLE "move_events" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "match_id" uuid NOT NULL,
        "seq_no" integer NOT NULL,
        "actor_id" uuid,
        "type" text NOT NULL,
        "payload" jsonb NOT NULL,
        "request_id" uuid,
        "created_at" timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT "CHK_move_events_type" CHECK ("type" IN ('dice_rolled', 'token_moved', 'turn_changed', 'player_forfeited', 'match_started', 'match_ended')),
        CONSTRAINT "PK_move_events" PRIMARY KEY ("id"),
        CONSTRAINT "FK_move_events_match" FOREIGN KEY ("match_id")
          REFERENCES "matches" ("id") ON DELETE CASCADE,
        CONSTRAINT "FK_move_events_actor" FOREIGN KEY ("actor_id")
          REFERENCES "users" ("id") ON DELETE SET NULL
      )`);
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_move_events_match_seq" ON "move_events" ("match_id", "seq_no")`,
    );
    await queryRunner.query(
      `CREATE UNIQUE INDEX "UQ_move_events_match_request" ON "move_events" ("match_id", "request_id") WHERE "request_id" IS NOT NULL`,
    );

    await queryRunner.query(`
      CREATE TABLE "game_configurations" (
        "id" uuid NOT NULL DEFAULT gen_random_uuid(),
        "version" text NOT NULL,
        "turn_timer_seconds" integer NOT NULL DEFAULT 30,
        "grace_period_seconds" integer NOT NULL DEFAULT 60,
        "missed_turn_limit" integer NOT NULL DEFAULT 3,
        "max_room_players" integer NOT NULL DEFAULT 4,
        "created_by" uuid,
        "effective_from" timestamptz,
        "created_at" timestamptz NOT NULL DEFAULT now(),
        CONSTRAINT "PK_game_configurations" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_game_configurations_version" UNIQUE ("version")
      )`);
    // Seed (G-4/C-11): the documented 30/60/3 defaults + max 4
    // players, for ruleset version 1.0.0 (RULESET_VERSION). The only
    // writer is FR-79 admin config (Stage 3 / Phase 7); Phase 5
    // only reads this row.
    await queryRunner.query(`
      INSERT INTO "game_configurations"
        ("version", "turn_timer_seconds", "grace_period_seconds", "missed_turn_limit", "max_room_players", "effective_from")
      VALUES ('1.0.0', 30, 60, 3, 4, now())`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE "game_configurations"`);
    await queryRunner.query(`DROP TABLE "move_events"`);
    await queryRunner.query(`DROP TABLE "match_players"`);
    await queryRunner.query(`DROP TABLE "matches"`);
    await queryRunner.query(`DROP TABLE "room_members"`);
    await queryRunner.query(`DROP TABLE "rooms"`);
  }
}
