import { Column, Entity, Index, PrimaryColumn } from 'typeorm';

/** Seat colours, in join order (SDD DA-03; Dart PlayerColour). */
export const SEAT_COLOURS = ['red', 'green', 'yellow', 'blue'] as const;
export type SeatColour = (typeof SEAT_COLOURS)[number];

/** Match result — SDD §9.2 CHECK, NULL until the match ends. */
export type MatchPlayerResult = 'win' | 'loss' | 'forfeit';

/**
 * match_players — SDD §9.2 (Phase 5, Stage 3).
 *
 * PK (match_id, user_id). `seat` 0–3 in join order (G-11, DA-03);
 * `colour` is the seat colour from SEAT_COLOURS. `result`,
 * `finish_rank` and `missed_turns` are filled by later stages
 * (turn timers / forfeit / match end); Stage 3 only writes seat +
 * colour. FR-58 records the rows at match creation; FR-67 ranking
 * does not run (Stage 3 scope).
 */
@Entity('match_players')
@Index(['userId', 'matchId'])
export class MatchPlayer {
  @PrimaryColumn({ type: 'uuid' })
  matchId!: string;

  @PrimaryColumn({ type: 'uuid' })
  userId!: string;

  @Column({ type: 'int' })
  seat!: number;

  @Column({ type: 'text' })
  colour!: string;

  @Column({ type: 'text', nullable: true })
  result!: MatchPlayerResult | null;

  @Column({ type: 'int', nullable: true })
  finishRank!: number | null;

  @Column({ type: 'int', default: 0 })
  missedTurns!: number;

  /**
   * Stage 6 (FR-54/55): when the player was last marked
   * DISCONNECTED, and when their 60 s grace expires. Both NULL
   * while connected; cleared on reconnect, read by the grace
   * sweeper for the BR-15 forfeit. Survives a restart (the
   * grace keeps running across one).
   */
  @Column({ type: 'timestamptz', nullable: true })
  disconnectedAt!: Date | null;

  @Column({ type: 'timestamptz', nullable: true })
  graceEndsAt!: Date | null;
}
