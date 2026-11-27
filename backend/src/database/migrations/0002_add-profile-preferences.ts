import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * 0002_add-profile-preferences — adds the notification-preferences
 * column the plan (§2.1.1 FR-08) says lives on `profiles`.
 * Implements: FR-08 (preferences persistence).
 *
 * Why a second migration instead of editing 0001: 0001 has already
 * run (Stage 2a, dev + test scratch DBs). Schema changes only via new
 * migrations, expand-then-contract (SDD §15.4, plan §4.4).
 *
 * `notification_preferences` is JSONB, NOT NULL, default '{}':
 * `{ "emailNotifications": bool, "pushNotifications": bool }`.
 * Sound/vibration are local Flutter settings and never reach the
 * server (FR-08); only notification preferences are stored.
 */
export class AddProfilePreferences1764249000000 implements MigrationInterface {
  name = 'AddProfilePreferences1764249000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "profiles"
      ADD COLUMN "notification_preferences" jsonb NOT NULL DEFAULT '{}'::jsonb
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "profiles" DROP COLUMN "notification_preferences"
    `);
  }
}
