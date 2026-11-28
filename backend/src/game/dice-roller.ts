/**
 * Dice source (mirrors Dart `dice_roller.dart`).
 *
 * Injectable so tests can feed a fixed sequence while production
 * uses a uniform random source (SRS FR-15, SDD §6.4). The AI and the
 * UI never roll dice themselves — only the engine, through a
 * {@link DiceRoller}, does. The server never accepts a
 * client-supplied dice value (FR-49).
 */
import { randomInt } from 'node:crypto';
import { ArgumentError, StateError } from './errors';

export interface DiceRoller {
  /** Returns a uniform integer in 1..6 (BR-02). */
  roll(): number;
}

/**
 * Production dice: uniform 1..6 from `crypto.randomInt`, which is
 * rejection-based and therefore has no modulo bias. Online results
 * are ranked, so a cryptographically secure source is required
 * (the offline Dart engine uses `Random`, which is not enough here).
 */
export class CryptoDiceRoller implements DiceRoller {
  roll(): number {
    return randomInt(1, 7);
  }
}

/** Test dice: returns a predetermined sequence of values. */
export class FixedDiceRoller implements DiceRoller {
  constructor(values: readonly number[], opts: { cycle?: boolean } = {}) {
    if (values.length === 0) {
      throw new ArgumentError('FixedDiceRoller needs at least one value.');
    }
    for (const value of values) {
      if (!Number.isInteger(value) || value < 1 || value > 6) {
        throw new ArgumentError(`Dice values must be in 1..6, got ${value}.`);
      }
    }
    this.values = [...values];
    this.cycle = opts.cycle ?? false;
  }

  /** Mutable: `reseed()` replaces the sequence (test support). */
  private values: number[];

  /**
   * When true, the sequence repeats from the start instead of
   * throwing once exhausted (handy for long simulations).
   */
  private readonly cycle: boolean;

  private position = 0;

  roll(): number {
    if (this.position >= this.values.length) {
      if (!this.cycle) {
        throw new StateError('FixedDiceRoller sequence exhausted.');
      }
      this.position = 0;
    }
    const value = this.values[this.position];
    this.position += 1;
    return value;
  }

  /**
   * Replace the sequence and restart from the beginning (test
   * support: a gameplay e2e test reseeds the shared roller before
   * each match so its rolls are deterministic from roll one).
   */
  reseed(values: readonly number[]): void {
    if (values.length === 0) {
      throw new ArgumentError('FixedDiceRoller needs at least one value.');
    }
    for (const value of values) {
      if (!Number.isInteger(value) || value < 1 || value > 6) {
        throw new ArgumentError(`Dice values must be in 1..6, got ${value}.`);
      }
    }
    this.values = [...values];
    this.position = 0;
  }
}
