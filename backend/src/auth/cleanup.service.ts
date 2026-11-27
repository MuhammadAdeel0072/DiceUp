import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { EmailToken } from './entities/email-token.entity';
import { AuthSession } from './entities/auth-session.entity';

/**
 * AuthCleanupService (plan §4.5, SDD §9.2 "expired rows purged by a
 * job"). Daily purge, low-traffic hour (03:00), logged with row counts.
 *
 * - auth_sessions: rows whose expires_at is past. Revoked-but-
 *   unexpired rows are KEPT: refresh-token reuse detection depends on
 *   finding the revoked predecessor while its family still has a live
 *   session; once the row itself has expired it can no longer be
 *   presented for a refresh, so it is safe to delete.
 * - email_tokens: used rows and expired rows.
 */
@Injectable()
export class AuthCleanupService {
  private readonly logger = new Logger(AuthCleanupService.name);

  constructor(
    @InjectRepository(AuthSession)
    private readonly sessions: Repository<AuthSession>,
    @InjectRepository(EmailToken)
    private readonly tokens: Repository<EmailToken>,
  ) {}

  @Cron('0 3 * * *')
  async purgeExpired(): Promise<{
    sessionsDeleted: number;
    tokensDeleted: number;
  }> {
    const sessionsResult = await this.sessions
      .createQueryBuilder()
      .delete()
      .where('expires_at < now()')
      .execute();
    const tokensResult = await this.tokens
      .createQueryBuilder()
      .delete()
      .where('used_at IS NOT NULL OR expires_at < now()')
      .execute();
    const sessionsDeleted = sessionsResult.affected ?? 0;
    const tokensDeleted = tokensResult.affected ?? 0;
    this.logger.log(
      `Purged ${sessionsDeleted} expired auth sessions, ${tokensDeleted} used/expired email tokens`,
    );
    return { sessionsDeleted, tokensDeleted };
  }
}
