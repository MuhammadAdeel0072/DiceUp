import { Injectable, UnauthorizedException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { ConflictException } from '@nestjs/common';
import { DataSource, EntityManager, IsNull, Repository } from 'typeorm';
import { TokenExpiredException } from '../common/errors/token-expired.exception';
import { ErrorCode } from '../common/errors/error-codes';
import { isUniqueViolationError } from '../common/errors/unique-violation';
import { generateEmailToken, hashEmailToken } from './email-token.util';
import {
  EmailToken,
  type EmailTokenPurpose,
} from './entities/email-token.entity';

/**
 * EmailTokenService — issue + consume for the single-use, hashed,
 * time-limited email tokens (FR-03/FR-06, SDD §13.1).
 *
 * `issue` invalidates any live token for the same (user, purpose)
 * first, honouring the partial unique index (at most one live token
 * per purpose). `consume` validates inside a transaction with a
 * pessimistic write lock and marks the token used BEFORE running the
 * caller's work, so two concurrent presents cannot both succeed —
 * the second sees `used_at` set and gets 409 TOKEN_ALREADY_USED.
 * Expired tokens get 410 TOKEN_EXPIRED (D-P4-10); unknown tokens get
 * a generic 401 (no leak about which tokens exist).
 */
@Injectable()
export class EmailTokenService {
  constructor(
    @InjectRepository(EmailToken)
    private readonly tokens: Repository<EmailToken>,
    private readonly dataSource: DataSource,
  ) {}

  /** Issues a token, returning the plaintext value (emailed once). */
  async issue(
    userId: string,
    purpose: EmailTokenPurpose,
    ttlHours: number,
  ): Promise<string> {
    const { token, hash } = generateEmailToken();
    const expiresAt = new Date(Date.now() + ttlHours * 3600 * 1000);
    try {
      await this.insertToken(userId, purpose, hash, expiresAt);
    } catch (err) {
      // NOTE (Stage 4, H-02 class): two concurrent issues for the same
      // (user, purpose) can both delete-then-insert; the loser hits the
      // partial unique index (one live token per purpose). Retry once —
      // the retry deletes the winner's live row first, preserving the
      // single-live-token invariant instead of surfacing a 500.
      if (!isUniqueViolationError(err)) throw err;
      await this.insertToken(userId, purpose, hash, expiresAt);
    }
    return token;
  }

  private async insertToken(
    userId: string,
    purpose: EmailTokenPurpose,
    hash: string,
    expiresAt: Date,
  ): Promise<void> {
    await this.dataSource.transaction(async (manager) => {
      await manager.delete(EmailToken, {
        userId,
        purpose,
        usedAt: IsNull(),
      });
      await manager.save(EmailToken, {
        userId,
        purpose,
        tokenHash: hash,
        expiresAt,
      });
    });
  }

  /**
   * Validates a presented token and runs `work` with it marked used,
   * all in one transaction. Throws 401 (unknown), 409 (already used)
   * or 410 (expired).
   */
  async consume<T>(
    token: string,
    purpose: EmailTokenPurpose,
    work: (manager: EntityManager, row: EmailToken) => Promise<T>,
  ): Promise<T> {
    const hash = hashEmailToken(token);
    return this.dataSource.transaction(async (manager) => {
      const row = await manager.findOne(EmailToken, {
        where: { tokenHash: hash, purpose },
        lock: { mode: 'pessimistic_write' },
      });
      if (!row) {
        throw new UnauthorizedException('Invalid or expired token.');
      }
      if (row.usedAt !== null) {
        throw new ConflictException({
          code: ErrorCode.TokenAlreadyUsed,
          message: 'This token has already been used.',
        });
      }
      if (row.expiresAt.getTime() <= Date.now()) {
        throw new TokenExpiredException();
      }
      await manager.update(EmailToken, { id: row.id }, { usedAt: new Date() });
      return work(manager, row);
    });
  }
}
