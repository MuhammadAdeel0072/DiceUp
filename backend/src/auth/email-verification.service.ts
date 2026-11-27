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
import { Profile } from '../users/entities/profile.entity';
import { User } from '../users/entities/user.entity';
import { EMAIL_VERIFY_TOKEN_TTL_HOURS } from './auth.constants';
import type { UserPublic } from './dto/auth-response';
import { toUserPublic } from './dto/auth-response';
import { EmailTokenService } from './email-token.service';

/**
 * EmailVerificationService (FR-03).
 * - issue: creates a 24 h single-use hashed token and dispatches it
 *   via Mailer. A mailer failure becomes 503 (the account already
 *   exists; the user can resend) — never a silent success.
 * - verify: consumes the token, sets users.email_verified_at.
 * - resend: neutral by design — unknown email and already-verified
 *   accounts get the same silent success as a real resend (no
 *   account enumeration, §7.3).
 */
@Injectable()
export class EmailVerificationService {
  private readonly logger = new Logger(EmailVerificationService.name);

  constructor(
    @InjectRepository(User) private readonly users: Repository<User>,
    private readonly emailTokens: EmailTokenService,
    @Inject(MAILER) private readonly mailer: Mailer,
  ) {}

  async sendVerificationEmail(user: User): Promise<void> {
    const token = await this.emailTokens.issue(
      user.id,
      'verify',
      EMAIL_VERIFY_TOKEN_TTL_HOURS,
    );
    try {
      await this.mailer.sendVerification(user.email, token);
    } catch (err) {
      this.logger.error(
        `Failed to send verification email to ${user.email}: ${(err as Error).message}`,
      );
      throw new ServiceUnavailableException(
        'Email service is temporarily unavailable. Try resending later.',
      );
    }
  }

  async verify(token: string): Promise<{ user: UserPublic }> {
    return this.emailTokens.consume(token, 'verify', async (manager, row) => {
      await manager.update(
        User,
        { id: row.userId },
        { emailVerifiedAt: new Date() },
      );
      const user = await manager.findOneOrFail(User, {
        where: { id: row.userId },
      });
      const profile = await manager.findOne(Profile, {
        where: { userId: row.userId },
      });
      return { user: toUserPublic(user, profile) };
    });
  }

  async resend(email: string): Promise<void> {
    const user = await this.users.findOne({ where: { email } });
    if (!user || user.emailVerifiedAt !== null) return;
    await this.sendVerificationEmail(user);
  }
}
