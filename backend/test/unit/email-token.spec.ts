import {
  generateEmailToken,
  hashEmailToken,
} from '../../src/auth/email-token.util';

describe('email-token helpers (FR-03/FR-06)', () => {
  it('generates a 256-bit token whose hash is a stable SHA-256 hex', () => {
    const { token, hash } = generateEmailToken();
    expect(token.length).toBeGreaterThanOrEqual(43);
    expect(hash).toBe(hashEmailToken(token));
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it('different tokens have different hashes; the hash never leaks the token', () => {
    const a = generateEmailToken();
    const b = generateEmailToken();
    expect(a.token).not.toBe(b.token);
    expect(a.hash).not.toBe(b.hash);
    expect(a.hash).not.toContain(a.token);
  });
});
