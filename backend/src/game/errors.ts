/**
 * Engine error taxonomy (mirrors the Dart engine, D-20).
 *
 * The four kinds stay distinct so callers (Stage 5 socket handlers)
 * can map them to the right rejection code without string matching:
 * - {@link InvalidRulesetConfig} / {@link InvalidMatchConfig}: setup
 *   errors — no match is created.
 * - {@link StateError}: an action in the wrong phase, or after the
 *   match finished. State is unchanged.
 * - {@link ArgumentError}: an illegal move (wrong player, or not in
 *   the legal-move list). State is unchanged.
 * - {@link FormatException}: a malformed snapshot. Never silently
 *   repaired; the caller must reject it.
 */

export class InvalidRulesetConfig extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidRulesetConfig';
  }
}

export class InvalidMatchConfig extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidMatchConfig';
  }
}

export class StateError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'StateError';
  }
}

export class ArgumentError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ArgumentError';
  }
}

export class FormatException extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'FormatException';
  }
}
