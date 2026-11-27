import { PasswordHasherService } from '../../src/auth/password-hasher.service';

describe('PasswordHasherService (NFR-13, Argon2id)', () => {
  const hasher = new PasswordHasherService();

  it('hashes with Argon2id parameters (memory 64 MiB, 3 iterations)', async () => {
    const hash = await hasher.hash('CorrectHorse!9');
    expect(hash).toMatch(/^\$argon2id\$v=19\$m=65536,t=3,p=1\$/);
  });

  it('same password yields different hashes (per-password salt)', async () => {
    const a = await hasher.hash('same-password');
    const b = await hasher.hash('same-password');
    expect(a).not.toBe(b);
    expect(await hasher.verify(a, 'same-password')).toBe(true);
    expect(await hasher.verify(b, 'same-password')).toBe(true);
  });

  it('verifies the correct password and rejects a wrong one', async () => {
    const hash = await hasher.hash('CorrectHorse!9');
    await expect(hasher.verify(hash, 'CorrectHorse!9')).resolves.toBe(true);
    await expect(hasher.verify(hash, 'correcthorse!9')).resolves.toBe(false);
    await expect(hasher.verify(hash, '')).resolves.toBe(false);
  });

  it('verify never throws on a malformed stored hash', async () => {
    await expect(hasher.verify('not-a-hash', 'x')).resolves.toBe(false);
    await expect(hasher.verify('', 'x')).resolves.toBe(false);
  });

  it('verifyDummy always returns false (unknown-user login path)', async () => {
    await expect(hasher.verifyDummy('anything')).resolves.toBe(false);
    await expect(hasher.verifyDummy('anything')).resolves.toBe(false);
  });
});
