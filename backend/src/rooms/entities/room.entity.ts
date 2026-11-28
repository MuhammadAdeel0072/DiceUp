import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/** Room status — SDD §9.2 CHECK (open/playing/closed). */
export type RoomStatus = 'open' | 'playing' | 'closed';

/** How the room came to be (Stage 3 scope record). */
export type RoomSource = 'manual' | 'matchmaking';

/**
 * rooms — SDD §9.2 (Phase 5, Stage 3).
 *
 * `code` is unique only among open rooms (partial index, see
 * migration 0003): a closed room's code may be reused by a later
 * room, so the code alone never identifies a room — lookups always
 * filter `status = 'open'`. `host_id` is the current host (host
 * transfer rewrites it, FR-59); `room_members.is_host` mirrors it
 * for the transfer query. `ruleset_version` is the frozen version
 * (OD-11: every Phase 5 match uses RULESET_VERSION; there are no
 * host-selectable rule options).
 */
@Entity('rooms')
@Index(['code'], { where: `"status" = 'open'`, unique: true })
@Index(['hostId', 'status'])
export class Room {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'varchar', length: 6 })
  code!: string;

  @Column({ type: 'uuid' })
  hostId!: string;

  @Column({ type: 'int' })
  maxPlayers!: number;

  @Column({ type: 'text', default: 'open' })
  status!: RoomStatus;

  @Column({ type: 'text' })
  rulesetVersion!: string;

  /** 'manual' (POST /rooms) or 'matchmaking' (FR-45 grouping). */
  @Column({ type: 'text', default: 'manual' })
  source!: RoomSource;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @Column({ type: 'timestamptz', nullable: true })
  closedAt!: Date | null;
}
