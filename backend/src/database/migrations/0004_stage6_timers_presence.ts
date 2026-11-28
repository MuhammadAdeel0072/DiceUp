import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * 0004_stage6_timers_presence — the Phase 5 Stage 6 columns
 * (FR-52/54/55/56, NFR-32/33).
 *
 * `matches.turn_ends_at` + `turn_epoch` persist the turn timer:
 * the deadline of the current turn and the epoch it belongs to.
 * Every turn transition writes a new deadline + epoch in the same
 * transaction as its `move_events` rows, so the timer state is
 * PostgreSQL truth — a restart re-arms from it (NFR-33) and a
 * stale timer (epoch mismatch) can never fire after the turn
 * advanced. NULL `turn_ends_at` means no turn is running (the
 * match has ended, or it predates Stage 6 and has not been
 * re-armed by the recovery pass yet).
 *
 * `match_players.disconnected_at` + `grace_ends_at` persist the
 * disconnect/grace state (FR-54/55): set on disconnect, cleared
 * on reconnect, read by the grace sweeper for forfeit (BR-15).
 *
 * Expand-only (SDD §15.4): new nullable columns + a defaulted
 * counter, nothing altered or dropped.
 */
export class Stage6TimersPresence1796000000000 implements MigrationInterface {
  name = 'Stage6TimersPresence1796000000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "matches" ADD "turn_ends_at" timestamptz`,
    );
    await queryRunner.query(
      `ALTER TABLE "matches" ADD "turn_epoch" integer NOT NULL DEFAULT 0`,
    );
    await queryRunner.query(
      `ALTER TABLE "match_players" ADD "disconnected_at" timestamptz`,
    );
    await queryRunner.query(
      `ALTER TABLE "match_players" ADD "grace_ends_at" timestamptz`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "match_players" DROP COLUMN "grace_ends_at"`,
    );
    await queryRunner.query(
      `ALTER TABLE "match_players" DROP COLUMN "disconnected_at"`,
    );
    await queryRunner.query(`ALTER TABLE "matches" DROP COLUMN "turn_epoch"`);
    await queryRunner.query(`ALTER TABLE "matches" DROP COLUMN "turn_ends_at"`);
  }
}
