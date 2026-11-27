import { createHash, randomBytes } from 'node:crypto';

/**
 * Email-token helpers (FR-03/FR-06, SDD §13.1).
 * Tokens are 256-bit random values (base64url for transport); only the
 * SHA-256 hash is stored in email_tokens, so a database read alone can
 * never be used to present a token. Lookup is by hash equality in
 * PostgreSQL — the hash is a one-way value, so there is no plaintext
 * comparison to make timing-sensitive.
 */
export function generateEmailToken(): { token: string; hash: string } {
  const token = randomBytes(32).toString('base64url');
  return { token, hash: hashEmailToken(token) };
}

export function hashEmailToken(token: string): string {
  return createHash('sha256').update(token, 'utf8').digest('hex');
}
