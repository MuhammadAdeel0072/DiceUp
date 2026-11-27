import { Injectable, Logger } from '@nestjs/common';
import type { Mailer, SentMailMessage } from './mailer.interface';

/**
 * Log transport for Mailer (plan §7.4, [P4 choice] D-P4-18).
 * Dev/test only — registered when MAILER_PROVIDER is unset or 'log'
 * and NODE_ENV is not production.
 *
 * Messages are stored in memory (so tests can read the verification /
 * reset token back out of the service instead of scraping logs) and a
 * one-line log entry is written with the recipient + kind only. The
 * token is NEVER written to a log line: the pino redaction list would
 * censor a `token` key anyway, but the transport does not rely on that
 * — it simply never logs the token. NEVER sends real email.
 */
@Injectable()
export class LogMailerService implements Mailer {
  private readonly logger = new Logger(LogMailerService.name);
  private readonly sent: SentMailMessage[] = [];

  async sendVerification(email: string, token: string): Promise<void> {
    this.record(email, 'verification', token);
    this.logger.log(`Verification email queued for ${email}`);
  }

  async sendPasswordReset(email: string, token: string): Promise<void> {
    this.record(email, 'password-reset', token);
    this.logger.log(`Password-reset email queued for ${email}`);
  }

  /** Messages captured by this transport, oldest first. Test inspection. */
  getSentMessages(): SentMailMessage[] {
    return [...this.sent];
  }

  /** Most recent message of a kind for an address, if any. */
  findLatest(
    email: string,
    kind: SentMailMessage['kind'],
  ): SentMailMessage | undefined {
    for (let i = this.sent.length - 1; i >= 0; i--) {
      const m = this.sent[i];
      if (m.to === email && m.kind === kind) return m;
    }
    return undefined;
  }

  clear(): void {
    this.sent.length = 0;
  }

  private record(
    email: string,
    kind: SentMailMessage['kind'],
    token: string,
  ): void {
    this.sent.push({ to: email, kind, token, sentAt: new Date() });
    // Bound the in-memory store; the transport is dev/test-only and
    // nothing reads messages older than the most recent few hundred.
    if (this.sent.length > 1000) this.sent.splice(0, this.sent.length - 1000);
  }
}
