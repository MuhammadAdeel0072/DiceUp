/**
 * Mailer interface (plan §7.4 / CI-07). Provider selection is OPEN
 * (OD-09/A-04); Phase 4 implements two transports behind this
 * interface: a log transport (dev/test — stores messages in memory,
 * never sends real email) and an SMTP transport (nodemailer,
 * config-driven, used when MAILER_PROVIDER=smtp). The log transport
 * is registered only when NODE_ENV != 'production'; production boot
 * with no real provider fails fast (config validation + module init).
 */
export const MAILER = 'MAILER';

export interface Mailer {
  sendVerification(email: string, token: string): Promise<void>;
  sendPasswordReset(email: string, token: string): Promise<void>;
}

/** Push interface (plan §2.1.3 CI-08): declared only, no implementation. */
export interface PushSender {
  sendPush(userId: string, title: string, body: string): Promise<void>;
}

/** One message captured by the log transport (dev/test inspection). */
export interface SentMailMessage {
  to: string;
  kind: 'verification' | 'password-reset';
  /** The raw token — kept in memory only, never written to a log line. */
  token: string;
  sentAt: Date;
}
