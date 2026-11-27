import { Injectable } from '@nestjs/common';
import * as argon2 from 'argon2';
import { randomBytes } from 'node:crypto';
import {
  ARGON2_MEMORY_KIB,
  ARGON2_PARALLELISM,
  ARGON2_TIME_COST,
} from './auth.constants';

/**
 * PasswordHasherService (NFR-13, SDD §13.1).
 * Argon2id, memory 64 MiB, iterations 3, parallelism 1 (OWASP baseline
 * [Proposed]); per-password salt is handled by argon2. bcrypt is the
 * documented fallback for a future deployment decision — it is NOT
 * implemented in parallel. `verify` never throws on a bad hash: a
 * malformed stored hash is simply a failed verification.
 */
@Injectable()
export class PasswordHasherService {
  /** Lazily-created dummy hash for the unknown-user login path (D-P4-20). */
  private dummyHashPromise: Promise<string> | null = null;

  async hash(password: string): Promise<string> {
    return argon2.hash(password, {
      type: argon2.argon2id,
      memoryCost: ARGON2_MEMORY_KIB,
      timeCost: ARGON2_TIME_COST,
      parallelism: ARGON2_PARALLELISM,
    });
  }

  async verify(hash: string, password: string): Promise<boolean> {
    try {
      return await argon2.verify(hash, password);
    } catch {
      return false;
    }
  }

  /**
   * Runs an Argon2id verification against a fixed dummy hash so the
   * unknown-user login path costs the same as the known-user path
   * (timing does not leak account existence, §7.3). Always false.
   */
  async verifyDummy(password: string): Promise<boolean> {
    if (!this.dummyHashPromise) {
      this.dummyHashPromise = this.hash(randomBytes(16).toString('hex'));
    }
    const dummyHash = await this.dummyHashPromise;
    return this.verify(dummyHash, password);
  }
}
