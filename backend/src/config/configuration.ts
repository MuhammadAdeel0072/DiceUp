import * as fs from 'node:fs';
import * as path from 'node:path';
import { registerAs } from '@nestjs/config';

/**
 * Typed application configuration (plan §8.1).
 *
 * Values that are rules, not secrets, live here with their SDD defaults
 * (RULESET_VERSION=1.0.0, BR-14). There is no default JWT key, database
 * URL, or password anywhere — ever. Production-only requirements are
 * enforced by `validateProductionConfig` in config.validation.ts, which
 * fails fast at boot (see main.ts).
 *
 * JWT keys (RS256, NFR-15) can be supplied two ways:
 *   1. Inline PEM in JWT_PRIVATE_KEY / JWT_PUBLIC_KEY, or
 *   2. A file path in JWT_PRIVATE_KEY_FILE / JWT_PUBLIC_KEY_FILE
 *      (resolved relative to the process working directory, i.e.
 *      backend/ when run from backend/). The file form is the
 *      recommended dev path: the local dev keypair lives in
 *      backend/.keys/ (git-ignored, generated with openssl — see
 *      README "RS256 keys"). Inline values win over files when both
 *      are set. A missing/unreadable file resolves to undefined here;
 *      the Auth module then generates an ephemeral in-memory keypair
 *      in non-production (with a warning) and production still fails
 *      fast via validateProductionConfig.
 */
export interface AppConfig {
  nodeEnv: string;
  port: number;
  logLevel: string;
  databaseUrl: string;
  redisUrl: string;
  rulesetVersion: string;
  corsOrigins: string[];
  /** Express `trust proxy` setting (Stage 4, H-03). */
  trustProxy: boolean | number | string;
  jwtPrivateKey?: string;
  jwtPublicKey?: string;
  jwtIssuer: string;
  mailerProvider?: string;
  mailerFrom?: string;
  mailerSmtpHost?: string;
  mailerSmtpPort?: number;
  mailerSmtpUser?: string;
  mailerSmtpPass?: string;
}

/**
 * Resolve one JWT key: inline env value wins; otherwise read the file
 * named by the *_FILE variable. Returns undefined (never throws) when
 * neither is usable — callers decide how to fail.
 */
export function resolveJwtKey(
  inlineValue: string | undefined,
  fileValue: string | undefined,
): string | undefined {
  if (inlineValue) return inlineValue;
  if (!fileValue) return undefined;
  try {
    const fullPath = path.resolve(process.cwd(), fileValue);
    const contents = fs.readFileSync(fullPath, 'utf8').trim();
    return contents.length > 0 ? contents : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Parse TRUST_PROXY into an Express `trust proxy` value (Stage 4, H-03).
 *
 * Without this, behind the TLS-terminating reverse proxy the plan
 * requires (NFR-14), `req.ip` is the proxy's address for EVERY client:
 * the per-IP login throttle (NFR-16) and per-IP register/refresh
 * limits collapse into one shared bucket — five failed logins from
 * any one user would throttle logins for everyone, and one client's
 * failures would spend everyone else's budget. The value must name
 * the number of trusted proxies in front of the app (usually `1` in
 * production); `0`/`false` (default) trusts nobody, which is correct
 * for direct local runs. Unknown values fall back to `false` rather
 * than trusting an arbitrary `X-Forwarded-For` sender.
 */
export function parseTrustProxy(
  value: string | undefined,
): boolean | number | string {
  if (value === undefined) return false;
  const v = value.trim().toLowerCase();
  if (v === '' || v === '0' || v === 'false') return false;
  if (v === '1' || v === 'true') return 1;
  if (/^\d+$/.test(v)) return Number(v);
  if (v === 'loopback' || v === 'linklocal' || v === 'uniquelocal') {
    return v;
  }
  return false;
}

export const appConfig = registerAs('app', (): AppConfig => ({
  nodeEnv: process.env.NODE_ENV ?? 'development',
  port: Number(process.env.PORT ?? 3000),
  logLevel: process.env.LOG_LEVEL ?? 'info',
  databaseUrl: process.env.DATABASE_URL ?? '',
  redisUrl: process.env.REDIS_URL ?? '',
  rulesetVersion: process.env.RULESET_VERSION ?? '1.0.0',
  corsOrigins: (process.env.CORS_ORIGINS ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean),
  trustProxy: parseTrustProxy(process.env.TRUST_PROXY),
  jwtPrivateKey: resolveJwtKey(
    process.env.JWT_PRIVATE_KEY || undefined,
    process.env.JWT_PRIVATE_KEY_FILE || undefined,
  ),
  jwtPublicKey: resolveJwtKey(
    process.env.JWT_PUBLIC_KEY || undefined,
    process.env.JWT_PUBLIC_KEY_FILE || undefined,
  ),
  jwtIssuer: process.env.JWT_ISSUER ?? 'diceup',
  mailerProvider: process.env.MAILER_PROVIDER || undefined,
  mailerFrom: process.env.MAILER_FROM || undefined,
  mailerSmtpHost: process.env.MAILER_SMTP_HOST || undefined,
  mailerSmtpPort: process.env.MAILER_SMTP_PORT
    ? Number(process.env.MAILER_SMTP_PORT)
    : undefined,
  mailerSmtpUser: process.env.MAILER_SMTP_USER || undefined,
  mailerSmtpPass: process.env.MAILER_SMTP_PASS || undefined,
}));
