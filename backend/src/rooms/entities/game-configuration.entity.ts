import {
  Column,
  CreateDateColumn,
  Entity,
  PrimaryGeneratedColumn,
} from 'typeorm';

/**
 * game_configurations — SDD §9.2 (Phase 5, Stage 3).
 *
 * The source of the 30/60/3 timer values (G-4/C-11): the only writer
 * is FR-79 admin config (Stage 3 / Phase 7), so Phase 5 seeds one row
 * (migration 0003, version = RULESET_VERSION) and only ever reads it.
 * No admin UI exists; changing a value is a new row + a code-level
 * decision, never an ad-hoc edit. `version` is the ruleset version
 * the row applies to.
 */
@Entity('game_configurations')
export class GameConfiguration {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'text', unique: true })
  version!: string;

  @Column({ type: 'int', default: 30 })
  turnTimerSeconds!: number;

  @Column({ type: 'int', default: 60 })
  gracePeriodSeconds!: number;

  @Column({ type: 'int', default: 3 })
  missedTurnLimit!: number;

  @Column({ type: 'int', default: 4 })
  maxRoomPlayers!: number;

  @Column({ type: 'uuid', nullable: true })
  createdBy!: string | null;

  @Column({ type: 'timestamptz', nullable: true })
  effectiveFrom!: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;
}
