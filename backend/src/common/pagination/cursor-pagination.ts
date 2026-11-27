/**
 * Cursor pagination helper (plan §6.4). Phase 4 has no list endpoint yet;
 * this is built now so Phase 6 does not invent a second convention.
 * Rules: limit default 20, max 100; nextCursor is opaque (base64 of the
 * last row's sort key), never a raw offset/id the client can forge.
 */
export const PAGINATION_DEFAULT_LIMIT = 20;
export const PAGINATION_MAX_LIMIT = 100;

export function normalizeLimit(limit: unknown): number {
  const n = typeof limit === 'string' ? Number(limit) : Number(limit);
  if (!Number.isFinite(n) || n <= 0) return PAGINATION_DEFAULT_LIMIT;
  return Math.min(Math.floor(n), PAGINATION_MAX_LIMIT);
}

export function encodeCursor(value: string): string {
  return Buffer.from(value, 'utf8').toString('base64url');
}

export function decodeCursor(cursor: unknown): string | null {
  if (typeof cursor !== 'string' || cursor.length === 0) return null;
  try {
    const decoded = Buffer.from(cursor, 'base64url').toString('utf8');
    return decoded.length > 0 ? decoded : null;
  } catch {
    return null;
  }
}

export interface PaginatedResult<T> {
  items: T[];
  nextCursor: string | null;
}
