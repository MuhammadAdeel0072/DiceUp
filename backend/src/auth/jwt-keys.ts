import { generateKeyPairSync } from 'node:crypto';
import { Logger } from '@nestjs/common';
import type { AppConfig } from '../config/configuration';

/**
 * RS256 key material (NFR-15, plan §7.1).
 *
 * Resolution order (in AuthModule's factory, `buildJwtKeys`):
 *   1. Keys from validated config (inline PEM or *_FILE — see
 *      configuration.ts). Production boot fails fast without them
 *      (validateProductionConfig + the throw below).
 *   2. In dev/test only, an ephemeral in-memory RSA-2048 keypair
 *      generated at boot. Tokens signed with it die on restart —
 *      acceptable for dev/test, never for production. A warning is
 *      logged so the fallback is never silent.
 * NEVER commit a real key. Dev keys live in backend/.keys/ (git-ignored).
 */
export interface JwtKeys {
  privateKey: string;
  publicKey: string;
  issuer: string;
}

export const JWT_KEYS = 'JWT_KEYS';

export function buildJwtKeys(config: AppConfig): JwtKeys {
  if (config.jwtPrivateKey && config.jwtPublicKey) {
    return {
      privateKey: config.jwtPrivateKey,
      publicKey: config.jwtPublicKey,
      issuer: config.jwtIssuer,
    };
  }
  // Stage 4, M-07: exactly one half of the pair configured is always
  // a mistake (e.g. a typo'd *_FILE path, which resolveJwtKey turns
  // into undefined). Previously the app silently fell through to an
  // ephemeral dev keypair while the operator believed their file keys
  // were in use. Fail fast in every environment instead.
  if (config.jwtPrivateKey || config.jwtPublicKey) {
    throw new Error(
      'JWT configuration error: JWT_PRIVATE_KEY and JWT_PUBLIC_KEY (or *_FILE) must be configured together — only one half is present',
    );
  }
  if (config.nodeEnv === 'production') {
    throw new Error(
      'Production JWT configuration error: JWT_PRIVATE_KEY and JWT_PUBLIC_KEY (or *_FILE) are required in production',
    );
  }
  const logger = new Logger('JwtKeys');
  logger.warn(
    'No JWT keys configured — generating an ephemeral dev/test RS256 keypair (tokens will not survive a restart)',
  );
  const { privateKey, publicKey } = generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  });
  return { privateKey, publicKey, issuer: config.jwtIssuer };
}
