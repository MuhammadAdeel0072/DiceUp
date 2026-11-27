import { parseTrustProxy } from '../../src/config/configuration';

describe('parseTrustProxy (Stage 4, H-03)', () => {
  it('defaults to trusting nobody', () => {
    expect(parseTrustProxy(undefined)).toBe(false);
    expect(parseTrustProxy('')).toBe(false);
    expect(parseTrustProxy('0')).toBe(false);
    expect(parseTrustProxy('false')).toBe(false);
    expect(parseTrustProxy('FALSE')).toBe(false);
  });

  it('parses hop counts', () => {
    expect(parseTrustProxy('1')).toBe(1);
    expect(parseTrustProxy('true')).toBe(1);
    expect(parseTrustProxy('2')).toBe(2);
  });

  it('passes through the Express named trust values', () => {
    expect(parseTrustProxy('loopback')).toBe('loopback');
    expect(parseTrustProxy('uniquelocal')).toBe('uniquelocal');
  });

  it('falls back to false for unknown values (never trusts blindly)', () => {
    expect(parseTrustProxy('yes')).toBe(false);
    expect(parseTrustProxy('10.0.0.1')).toBe(false);
    expect(parseTrustProxy('*')).toBe(false);
  });
});
