import {
  ROOM_CODE_ALPHABET,
  ROOM_CODE_LENGTH,
  generateRoomCode,
  isValidRoomCode,
  normalizeRoomCode,
} from '../../src/rooms/room-code';

/**
 * Room-code generation (SDD §8.3 DA-02, G-12): 6-char uppercase
 * alphanumerics excluding confusables (I, O, 0, 1).
 */
describe('room codes', () => {
  it('generates 6-char codes from the confusable-free alphabet', () => {
    for (let i = 0; i < 100; i += 1) {
      const code = generateRoomCode();
      expect(code).toHaveLength(ROOM_CODE_LENGTH);
      expect(code).toMatch(/^[A-HJ-NP-Z2-9]{6}$/);
      for (const ch of code) {
        expect(ROOM_CODE_ALPHABET).toContain(ch);
      }
    }
  });

  it('is effectively unique across 10,000 generations', () => {
    const codes = new Set<string>();
    for (let i = 0; i < 10_000; i += 1) codes.add(generateRoomCode());
    // 32^6 ≈ 1.07e9 possible codes; a collision in 10k draws would
    // mean the generator is broken (birthday p ≈ 5e-5).
    expect(codes.size).toBe(10_000);
  });

  it('validates and normalises codes', () => {
    expect(isValidRoomCode('K7Q2XA')).toBe(true);
    expect(isValidRoomCode('k7q2xa')).toBe(false);
    expect(isValidRoomCode('K7Q2XI')).toBe(false); // I is confusable
    expect(isValidRoomCode('K7Q2X0')).toBe(false); // 0 is confusable
    expect(isValidRoomCode('K7Q2X')).toBe(false); // too short
    expect(isValidRoomCode('K7Q2XAA')).toBe(false); // too long
    expect(isValidRoomCode(42)).toBe(false);
    expect(normalizeRoomCode('  k7q2xa ')).toBe('K7Q2XA');
  });
});
