import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';

/** Account status — SDD §9.2 CHECK (active/suspended/blocked), BR-19. */
export type UserStatus = 'active' | 'suspended' | 'blocked';

/**
 * users — SDD §9.2 verbatim, plus one [P4 choice] column:
 * `deletion_requested_at` (FR-10 request marker; full anonymisation
 * awaits OPEN-5/OD-08, so no deletion workflow is implemented here).
 * CITEXT gives case-insensitive uniqueness for email/username (FR-02).
 * `password_hash` is never selected except by the dedicated auth path
 * (later stage) and never serialised (NFR-13/21).
 */
@Entity('users')
@Index(['status', 'createdAt'])
export class User {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'citext', unique: true })
  email!: string;

  @Column({ type: 'citext', unique: true })
  username!: string;

  @Column({ type: 'text', select: false })
  passwordHash!: string;

  @Column({ type: 'text', default: 'active' })
  status!: UserStatus;

  @Column({ type: 'timestamptz', nullable: true })
  emailVerifiedAt!: Date | null;

  /** [P4 choice] FR-10 request marker — see class doc. */
  @Column({ type: 'timestamptz', nullable: true })
  deletionRequestedAt!: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt!: Date;
}
