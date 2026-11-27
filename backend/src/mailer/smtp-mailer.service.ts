import { Injectable, Logger } from '@nestjs/common';
import type { Transporter } from 'nodemailer';
import type { Mailer } from './mailer.interface';

/**
 * SMTP transport for Mailer (plan §7.4 / CI-07), via nodemailer.
 * Selected when MAILER_PROVIDER=smtp. Sends a plain-text code email:
 * there is no player-facing web frontend in Phase 4, so the token is
 * delivered as a code the client pastes into the app's verify/reset
 * screen (a link form needs a frontend URL — a Phase 5 client concern,
 * not a second token format). The token travels in the email body by
 * design — that is what the email is for — and is never logged.
 *
 * Constructed by MailerModule (not by DI) so the transport can be
 * built from validated config; unit tests construct it directly with
 * a fake transport.
 */
@Injectable()
export class SmtpMailerService implements Mailer {
  private readonly logger = new Logger(SmtpMailerService.name);

  constructor(
    private readonly transport: Transporter,
    private readonly from: string,
  ) {}

  async sendVerification(email: string, token: string): Promise<void> {
    await this.transport.sendMail({
      from: this.from,
      to: email,
      subject: 'Verify your DiceUp email',
      text:
        'Welcome to DiceUp! Verify your email with this code:\n\n' +
        `${token}\n\n` +
        'The code expires in 24 hours and can only be used once.',
    });
    this.logger.log(`Verification email sent to ${email}`);
  }

  async sendPasswordReset(email: string, token: string): Promise<void> {
    await this.transport.sendMail({
      from: this.from,
      to: email,
      subject: 'Reset your DiceUp password',
      text:
        'Reset your DiceUp password with this code:\n\n' +
        `${token}\n\n` +
        'The code expires in 1 hour and can only be used once. ' +
        'If you did not request this, ignore this email.',
    });
    this.logger.log(`Password-reset email sent to ${email}`);
  }
}
