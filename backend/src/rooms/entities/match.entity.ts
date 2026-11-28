import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/** Match status — SDD §9.2 CHECK. No 'flagged' state exists (C-12). */
export type MatchStatus = 'in_progress' | 'completed' | 'cancelled';

/**
 * matches — SDD §9.2 (Phase 5, Stage 3).
 *
 * One room → at most one match (`room_id` UNIQUE): a room that has
 * started can never start a second match. Created by `match:start`
 * (FR-47) in the same transaction as its `match_players` seats and
 * its `match_started` move event (FR-58 atomicity pattern — the
 * result/finish columns are filled by later stages, never edited).
 * `winner_id` stays NULL until the match ends (Stage 5/6).
 */
@Entity('matches')
@Index(['winnerId', 'endedAt'])
export class Match {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'uuid', unique: true })
  roomId!: string;

  @Column({ type: 'text' })
  rulesetVersion!: string;

  @Column({ type: 'text', default: 'in_progress' })
  status!: MatchStatus;

  @Column({ type: 'uuid', nullable: true })
  winnerId!: string | null;

  /**
   * Stage 6 (FR-52, NFR-33): deadline of the current turn, and the
   * epoch it belongs to. Written in the same transaction as the
   * turn's `move_events` rows; NULL when no turn is running. The
   * sweeper fires only when the stored epoch still matches, so a
   * stale timer can never fire after the turn advanced; a restart
   * re-arms from these two columns.
   */
  @Column({ type: 'timestamptz', nullable: true })
  turnEndsAt!: Date | null;

  @Column({ type: 'int', default: 0 })
  turnEpoch!: number;

  @CreateDateColumn({ type: 'timestamptz' })
  startedAt!: Date;

  @Column({ type: 'timestamptz', nullable: true })
  endedAt!: Date | null;
}
