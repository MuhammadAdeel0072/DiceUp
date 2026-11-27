import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/**
 * auth_sessions — SDD §9.2 verbatim, plus one [P4 choice] column:
 * `family_id` — refresh-token lineage (SDD §12.4 requires family
 * revocation on refresh-token reuse but names no column; this is the
 * minimal lineage marker). Refresh tokens are stored SHA-256 hashed,
 * never in plaintext (NFR-15). Rows are the server-side revocation
 * source of truth; expired/revoked rows are purged by a scheduled job
 * (later stage, §4.5).
 */
@Entity('auth_sessions')
@Index(['userId', 'expiresAt'])
export class AuthSession {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'uuid' })
  userId!: string;

  @Column({ type: 'text' })
  refreshTokenHash!: string;

  /** [P4 choice] lineage marker for family revocation (NFR-15). */
  @Column({ type: 'uuid', nullable: true })
  familyId!: string | null;

  @Column({ type: 'text', nullable: true })
  deviceLabel!: string | null;

  @Column({ type: 'timestamptz' })
  expiresAt!: Date;

  @Column({ type: 'timestamptz', nullable: true })
  revokedAt!: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;
}
