import {
  Inject,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { MAILER } from '../mailer/mailer.interface';
import type { Mailer } from '../mailer/mailer.interface';
import { User } from '../users/entities/user.entity';
import { PASSWORD_RESET_TOKEN_TTL_HOURS } from './auth.constants';
import { EmailTokenService } from './email-token.service';
import { PasswordHasherService } from './password-hasher.service';
import { AuthSession } from './entities/auth-session.entity';

/**
 * PasswordResetService (FR-06).
 * - request: always succeeds silently (200 neutral, even for unknown
 *   emails — no account enumeration, §7.3). For a real account it
 *   issues a 1 h single-use hashed token and dispatches it.
 * - reset: consumes the token, hashes the new password, revokes ALL
 *   sessions for the user and invalidates the token — one transaction
 *   (NFR-31 pattern). A reset token can therefore never be replayed
 *   after a password change.
 */
@Injectable()
export class PasswordResetService {
  private readonly logger = new Logger(PasswordResetService.name);

  constructor(
    @InjectRepository(User) private readonly users: Repository<User>,
    private readonly emailTokens: EmailTokenService,
    private readonly hasher: PasswordHasherService,
    @Inject(MAILER) private readonly mailer: Mailer,
  ) {}

  async request(email: string): Promise<void> {
    const user = await this.users.findOne({ where: { email } });
    if (!user) return;
    const token = await this.emailTokens.issue(
      user.id,
      'reset',
      PASSWORD_RESET_TOKEN_TTL_HOURS,
    );
    try {
      await this.mailer.sendPasswordReset(user.email, token);
    } catch (err) {
      this.logger.error(
        `Failed to send password-reset email to ${user.email}: ${(err as Error).message}`,
      );
      throw new ServiceUnavailableException(
        'Email service is temporarily unavailable. Try again later.',
      );
    }
  }

  async reset(token: string, newPassword: string): Promise<void> {
    const passwordHash = await this.hasher.hash(newPassword);
    await this.emailTokens.consume(token, 'reset', async (manager, row) => {
      await manager.update(User, { id: row.userId }, { passwordHash });
      await manager.update(
        AuthSession,
        { userId: row.userId },
        { revokedAt: new Date() },
      );
    });
  }
}
