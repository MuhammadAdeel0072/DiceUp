import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';
import type { AppConfig } from '../config/configuration';
import { MAILER } from './mailer.interface';
import type { Mailer } from './mailer.interface';
import { LogMailerService } from './log-mailer.service';
import { SmtpMailerService } from './smtp-mailer.service';

/**
 * MailerModule (plan §7.4 / CI-07).
 *
 * Provider selection (OPEN-1 / OD-09 — no provider is decided yet):
 * - `MAILER_PROVIDER` unset or `log` (default): LogMailerService —
 *   dev/test only, stores messages in memory, never sends real email.
 * - `MAILER_PROVIDER=smtp`: SmtpMailerService via nodemailer, from
 *   MAILER_SMTP_HOST / MAILER_SMTP_PORT / MAILER_SMTP_USER /
 *   MAILER_SMTP_PASS (+ MAILER_FROM). Missing SMTP host fails fast
 *   with a named error at boot.
 * - Production with anything other than `smtp` fails fast: the log
 *   transport is never an acceptable production substitute (config
 *   validation also requires MAILER_PROVIDER in production).
 * - Any other provider value fails fast (unknown provider).
 *
 * `LogMailerService` is exported as a class so tests can read the
 * captured messages (`app.get(LogMailerService)`); production code
 * only ever depends on the `MAILER` token.
 */
@Module({
  providers: [
    LogMailerService,
    {
      provide: MAILER,
      inject: [ConfigService, LogMailerService],
      useFactory: (
        config: ConfigService,
        logMailer: LogMailerService,
      ): Mailer => {
        const app = config.getOrThrow<AppConfig>('app');
        const provider = app.mailerProvider ?? 'log';
        if (app.nodeEnv === 'production' && provider !== 'smtp') {
          throw new Error(
            'Production mailer configuration error: MAILER_PROVIDER must be "smtp" in production (log transport is dev/test only)',
          );
        }
        if (provider === 'log') return logMailer;
        if (provider === 'smtp') {
          if (!app.mailerSmtpHost) {
            throw new Error(
              'Mailer configuration error: MAILER_SMTP_HOST is required when MAILER_PROVIDER=smtp',
            );
          }
          const transport = nodemailer.createTransport({
            host: app.mailerSmtpHost,
            port: app.mailerSmtpPort ?? 587,
            secure: (app.mailerSmtpPort ?? 587) === 465,
            auth:
              app.mailerSmtpUser && app.mailerSmtpPass
                ? { user: app.mailerSmtpUser, pass: app.mailerSmtpPass }
                : undefined,
          });
          return new SmtpMailerService(
            transport,
            app.mailerFrom ?? 'noreply@diceup.example',
          );
        }
        throw new Error(
          `Mailer configuration error: unknown MAILER_PROVIDER "${provider}"`,
        );
      },
    },
  ],
  exports: [MAILER, LogMailerService],
})
export class MailerModule {}
