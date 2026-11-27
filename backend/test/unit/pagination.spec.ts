import {
  decodeCursor,
  encodeCursor,
  normalizeLimit,
} from '../../src/common/pagination/cursor-pagination';

describe('cursor pagination (plan §6.4)', () => {
  it('defaults to 20, caps at 100, rejects non-positive/non-numeric', () => {
    expect(normalizeLimit(undefined)).toBe(20);
    expect(normalizeLimit('20')).toBe(20);
    expect(normalizeLimit(500)).toBe(100);
    expect(normalizeLimit(0)).toBe(20);
    expect(normalizeLimit(-3)).toBe(20);
    expect(normalizeLimit('abc')).toBe(20);
  });

  it('cursor is opaque and round-trips; garbage decodes to null', () => {
    const cursor = encodeCursor('some-uuid-or-sort-key');
    expect(cursor).not.toContain('some-uuid');
    expect(decodeCursor(cursor)).toBe('some-uuid-or-sort-key');
    expect(decodeCursor('')).toBeNull();
    expect(decodeCursor(123)).toBeNull();
  });
});
