import { ConfigModule, ConfigService } from '@nestjs/config';
import { LoggerModule as PinoLoggerModule } from 'nestjs-pino';
import type { AppConfig } from '../../config/configuration';

/**
 * Structured JSON logging (plan §8.3, [P4 choice] nestjs-pino, NFR-37).
 * Every line carries a requestId; the redaction list guarantees no
 * password, token, key, or connection string ever reaches a log line,
 * even if a developer logs a request object by accident.
 *
 * Redaction list (never logged): password*, *token*, authorization,
 * mfa*, JWT_PRIVATE_KEY, DATABASE_URL, REDIS_URL.
 *
 * NOTE (Stage 4): built with forRootAsync from the VALIDATED config,
 * not from `process.env.LOG_LEVEL` read at import time. The old form
 * evaluated before ConfigModule loaded backend/.env, so LOG_LEVEL set
 * in .env was silently ignored (only shell env counted) — the same
 * config-precedence class as D-01.
 */
export const LoggerModule = PinoLoggerModule.forRootAsync({
  imports: [ConfigModule],
  inject: [ConfigService],
  useFactory: (config: ConfigService) => ({
    pinoHttp: {
      level: config.get<AppConfig>('app')?.logLevel ?? 'info',
      // pino-http redacts matching paths in req/res objects and log objects.
      redact: {
        paths: [
          'req.headers.authorization',
          'req.body.password',
          'req.body.newPassword',
          'req.body.oldPassword',
          'req.body.token',
          'req.body.refreshToken',
          'res.headers.authorization',
          'password',
          'newPassword',
          'oldPassword',
          'token',
          'refreshToken',
          'accessToken',
          'authorization',
          'mfaSecret',
          'JWT_PRIVATE_KEY',
          'DATABASE_URL',
          'REDIS_URL',
        ],
        censor: '[REDACTED]',
      },
      // Do not let pino-http auto-log every request: LoggingInterceptor
      // owns the one-per-request line (method/path/status/latency).
      autoLogging: false,
      genReqId: (req) =>
        (req.headers['x-request-id'] as string | undefined) ??
        `req-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    },
  }),
});
