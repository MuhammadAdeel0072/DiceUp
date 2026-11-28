import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/** Move-event types — SDD §9.2 CHECK. Stage 3 writes only match_started. */
export type MoveEventType =
  | 'dice_rolled'
  | 'token_moved'
  | 'turn_changed'
  | 'player_forfeited'
  | 'match_started'
  | 'match_ended';

/**
 * move_events — SDD §9.2 (Phase 5, Stage 3).
 *
 * The append-only match log and (from Stage 5) the state checkpoint:
 * replaying a match's rows in `seq_no` order reproduces its state.
 * `UNIQUE (match_id, seq_no)` orders the log; `UNIQUE (match_id,
 * request_id) WHERE request_id IS NOT NULL` is the FR-53 at-most-once
 * guarantee — a retried client intent with the same `requestId`
 * collides here instead of double-applying. Stage 3 writes one row
 * per match (`match_started`, seq 1, `request_id` NULL); gameplay
 * rows land in Stage 5.
 */
@Entity('move_events')
@Index(['matchId', 'seqNo'], { unique: true })
@Index(['matchId', 'requestId'], {
  unique: true,
  where: `"request_id" IS NOT NULL`,
})
export class MoveEvent {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'uuid' })
  matchId!: string;

  @Column({ type: 'int' })
  seqNo!: number;

  @Column({ type: 'uuid', nullable: true })
  actorId!: string | null;

  @Column({ type: 'text' })
  type!: MoveEventType;

  @Column({ type: 'jsonb' })
  payload!: Record<string, unknown>;

  @Column({ type: 'uuid', nullable: true })
  requestId!: string | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;
}
