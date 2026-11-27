import { Column, Entity, PrimaryColumn, UpdateDateColumn } from 'typeorm';

/** Notification preferences stored on the profile (FR-08). */
export interface NotificationPreferences {
  emailNotifications?: boolean;
  pushNotifications?: boolean;
}

/**
 * profiles — SDD §9.2 verbatim, plus one [P4 choice] column added by
 * migration 0002: `notification_preferences` JSONB (FR-08 — the plan
 * says the persistence column lives on profiles; 0001 did not create
 * it). 1—1 with users (user_id is both PK and FK, ON DELETE CASCADE).
 * Cached counters stay 0 until Phase 6 populates them (FR-63); no
 * ranking computation exists in Phase 4.
 */
@Entity('profiles')
export class Profile {
  @PrimaryColumn({ type: 'uuid' })
  userId!: string;

  @Column({ type: 'varchar', length: 50 })
  displayName!: string;

  @Column({ type: 'varchar', length: 50, default: 'default' })
  avatarKey!: string;

  @Column({ type: 'int', default: 0 })
  matchesPlayed!: number;

  @Column({ type: 'int', default: 0 })
  matchesWon!: number;

  /** FR-08 notification preferences (migration 0002). */
  @Column({ type: 'jsonb', default: {} })
  notificationPreferences!: NotificationPreferences;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}
