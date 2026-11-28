import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryColumn,
} from 'typeorm';

/**
 * room_members — SDD §9.2 (Phase 5, Stage 3).
 *
 * PK (room_id, user_id): one membership per player per room, enforced
 * by the key itself (the TOCTOU guard for concurrent joins — a second
 * concurrent insert fails 23505, never silently double-seats).
 * `is_host` mirrors `rooms.host_id` so host transfer is a single
 * "longest-present member" query (FR-59). `is_ready` is the FR-46
 * readiness flag, default false.
 */
@Entity('room_members')
@Index(['userId'])
export class RoomMember {
  @PrimaryColumn({ type: 'uuid' })
  roomId!: string;

  @PrimaryColumn({ type: 'uuid' })
  userId!: string;

  @Column({ type: 'boolean', default: false })
  isReady!: boolean;

  @Column({ type: 'boolean', default: false })
  isHost!: boolean;

  @CreateDateColumn({ type: 'timestamptz' })
  joinedAt!: Date;
}
