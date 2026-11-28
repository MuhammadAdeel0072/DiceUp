import { randomInt } from 'node:crypto';

/**
 * Room-code generation (SDD §8.3 DA-02, G-12; FR-43/44).
 *
 * 6-char uppercase alphanumerics excluding confusables: no `I`, `O`
 * (look like 1/0), no `0`, no `1`. Codes are the invitation mechanism
 * (share/copy); there is no external notification provider.
 * Uniqueness is enforced by the partial unique index on `rooms`
 * (`WHERE status = 'open'`); generation itself is random, and the
 * service retries on a 23505 collision.
 */
export const ROOM_CODE_LENGTH = 6;

/** Alphabet without confusables (I, O, 0, 1). */
export const ROOM_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

const CODE_PATTERN = /^[A-HJ-NP-Z2-9]{6}$/;

/** Generate one 6-char code with crypto-secure randomness. */
export function generateRoomCode(): string {
  let code = '';
  for (let i = 0; i < ROOM_CODE_LENGTH; i += 1) {
    code += ROOM_CODE_ALPHABET[randomInt(ROOM_CODE_ALPHABET.length)];
  }
  return code;
}

/** True when `value` is a well-formed room code (upper-cased first). */
export function isValidRoomCode(value: unknown): value is string {
  return typeof value === 'string' && CODE_PATTERN.test(value);
}

/** Normalise user-typed codes: trim + upper-case (codes are case-insensitive on entry). */
export function normalizeRoomCode(value: string): string {
  return value.trim().toUpperCase();
}
