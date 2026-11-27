import * as Joi from 'joi';
import type { AppConfig } from './configuration';

/**
 * Config validation (plan §8.1, [P4 choice] @nestjs/config + Joi).
 *
 * Joi enforces shape/types in every environment. The production-only
 * requirements (JWT keys, issuer, ruleset version, CORS origins, mailer)
 * are enforced separately by `validateProductionConfig`, so unit tests can
 * exercise the fail-fast path without booting the app against production.
 * No secret value is ever included in an error message.
 */
export const configValidationSchema = Joi.object({
  NODE_ENV: Joi.string()
    .valid('development', 'test', 'production')
    .default('development'),
  PORT: Joi.number().port().default(3000),
  LOG_LEVEL: Joi.string()
    .valid('fatal', 'error', 'warn', 'info', 'debug', 'trace')
    .default('info'),
  DATABASE_URL: Joi.string().uri().required(),
  REDIS_URL: Joi.string().uri().required(),
  RULESET_VERSION: Joi.string().default('1.0.0'),
  CORS_ORIGINS: Joi.string().allow('').default(''),
  TRUST_PROXY: Joi.string().allow('').optional(),
  JWT_PRIVATE_KEY: Joi.string().allow('').optional(),
  JWT_PUBLIC_KEY: Joi.string().allow('').optional(),
  JWT_PRIVATE_KEY_FILE: Joi.string().allow('').optional(),
  JWT_PUBLIC_KEY_FILE: Joi.string().allow('').optional(),
  JWT_ISSUER: Joi.string().default('diceup'),
  MAILER_PROVIDER: Joi.string().allow('').optional(),
  MAILER_API_KEY: Joi.string().allow('').optional(),
  MAILER_FROM: Joi.string().allow('').optional(),
  MAILER_SMTP_HOST: Joi.string().allow('').optional(),
  MAILER_SMTP_PORT: Joi.number().port().optional(),
  MAILER_SMTP_USER: Joi.string().allow('').optional(),
  MAILER_SMTP_PASS: Joi.string().allow('').optional(),
});

/** Env vars that must be present (and non-empty) in production. */
export const PRODUCTION_REQUIRED_VARS = [
  'DATABASE_URL',
  'REDIS_URL',
  'JWT_PRIVATE_KEY',
  'JWT_PUBLIC_KEY',
  'JWT_ISSUER',
  'RULESET_VERSION',
  'CORS_ORIGINS',
  'MAILER_PROVIDER',
] as const;

/**
 * Fail-fast production check. Throws a named error listing only the
 * *names* of missing variables (never their values). Called from main.ts
 * before the app listens; also unit-tested directly.
 */
export function validateProductionConfig(config: AppConfig): void {
  if (config.nodeEnv !== 'production') return;
  const missing = PRODUCTION_REQUIRED_VARS.filter((name) => {
    switch (name) {
      case 'DATABASE_URL':
        return !config.databaseUrl;
      case 'REDIS_URL':
        return !config.redisUrl;
      case 'JWT_PRIVATE_KEY':
        return !config.jwtPrivateKey;
      case 'JWT_PUBLIC_KEY':
        return !config.jwtPublicKey;
      case 'JWT_ISSUER':
        return !config.jwtIssuer;
      case 'RULESET_VERSION':
        return !config.rulesetVersion;
      case 'CORS_ORIGINS':
        return config.corsOrigins.length === 0;
      case 'MAILER_PROVIDER':
        // No real mailer provider is selected yet (OPEN-1); in production
        // the log transport is not an acceptable substitute, so a provider
        // name is required even though the provider itself is wired later.
        // Read from the typed config (not process.env directly) so a
        // file-loaded or test-injected value counts.
        return !config.mailerProvider;
      default:
        return false;
    }
  });
  if (missing.length > 0) {
    throw new Error(
      `Missing required production configuration: ${missing.join(', ')}`,
    );
  }
  // Stage 4, M-06: the old check only caught the literal string
  // 'localhost' in DATABASE_URL — `127.0.0.1` / `::1` sailed through,
  // and REDIS_URL was never checked at all. A production database or
  // cache on loopback means the deployment topology is wrong (or the
  // dev .env leaked into production); refuse both, for both URLs.
  for (const [name, url] of [
    ['DATABASE_URL', config.databaseUrl],
    ['REDIS_URL', config.redisUrl],
  ] as const) {
    if (isLoopbackUrl(url)) {
      throw new Error(
        `Production configuration error: ${name} must not point at localhost`,
      );
    }
  }
}

/** True when a URL's host is a loopback address (localhost / 127.0.0.1 / ::1). */
export function isLoopbackUrl(url: string): boolean {
  try {
    const host = new URL(url).hostname.toLowerCase();
    return (
      host === 'localhost' ||
      host === '127.0.0.1' ||
      host === '::1' ||
      host === '[::1]' ||
      host.endsWith('.localhost')
    );
  } catch {
    return false;
  }
}
