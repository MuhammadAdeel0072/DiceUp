import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  PrimaryGeneratedColumn,
} from 'typeorm';

/** Email-token purpose — SDD §9.2 CHECK (verify/reset). */
export type EmailTokenPurpose = 'verify' | 'reset';

/**
 * email_tokens — SDD §9.2 verbatim. Single-use, time-limited tokens
 * (FR-03/FR-06): stored SHA-256 hashed, `used_at` set on first use.
 * Partial unique index enforces at most one live token per
 * (user_id, purpose). Expiry is enforced in the service, never by
 * trusting the client.
 */
@Entity('email_tokens')
// NOTE: the live-token uniqueness is a *partial* unique index
// (user_id, purpose) WHERE used_at IS NULL, created by migration 0001.
// It cannot be expressed with @Unique (full unique), so it lives only
// in the migration — deliberately, so the migration is the schema truth.
@Index(['userId', 'purpose'])
export class EmailToken {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'uuid' })
  userId!: string;

  @Column({ type: 'text' })
  purpose!: EmailTokenPurpose;

  @Column({ type: 'text' })
  tokenHash!: string;

  @Column({ type: 'timestamptz' })
  expiresAt!: Date;

  @Column({ type: 'timestamptz', nullable: true })
  usedAt!: Date | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt!: Date;
}
