/**
 * One playing piece (mirrors Dart `token.dart`).
 *
 * Immutable: every transition produces a new {@link Token} via
 * {@link Token.copyWith}.
 *
 * `stepsTaken` is the token's progress along its own 56-step path:
 * 0 = in the yard, 1 = on its start cell, 51 = last outer-track cell,
 * 52..55 = home path, 56 = home.
 */
import { Board, type Cell } from './board';
import { requireIntInRange } from './json-validation';
import type { PlayerColour } from './player-colour';

export class Token {
  constructor(
    /** Index of the owning player in the match (0..3). */
    readonly playerIndex: number,
    /** Index of this token among its owner's four tokens (0..3). */
    readonly index: number,
    readonly colour: PlayerColour,
    readonly stepsTaken = 0,
  ) {}

  get isInYard(): boolean {
    return this.stepsTaken === 0;
  }

  get isHome(): boolean {
    return this.stepsTaken === Board.stepsToHome;
  }

  get isInHomePath(): boolean {
    return (
      this.stepsTaken > Board.lastTrackStep &&
      this.stepsTaken < Board.stepsToHome
    );
  }

  get isOnTrack(): boolean {
    return this.stepsTaken >= 1 && this.stepsTaken <= Board.lastTrackStep;
  }

  /** Logical board cell for this token. */
  get cell(): Cell {
    return new Board().cellAt(this.colour, this.stepsTaken);
  }

  /**
   * Whether this token may move by `roll` under the given rules
   * (BR-04 release, BR-10 exact finish). The caller (the engine)
   * additionally checks turn ownership and phase.
   */
  canMove(
    roll: number,
    opts: { releaseRolls: ReadonlySet<number>; exactFinish: boolean },
  ): boolean {
    if (this.isInYard) return opts.releaseRolls.has(roll);
    if (opts.exactFinish) {
      return this.stepsTaken + roll <= Board.stepsToHome;
    }
    return !this.isHome; // Non-exact variant: any roll moves it home.
  }

  copyWith(opts: { stepsTaken?: number } = {}): Token {
    return new Token(
      this.playerIndex,
      this.index,
      this.colour,
      opts.stepsTaken ?? this.stepsTaken,
    );
  }

  /** A token sent back to its yard (BR-08 capture). */
  get sentToYard(): Token {
    return this.copyWith({ stepsTaken: 0 });
  }

  toJson(): { stepsTaken: number } {
    return { stepsTaken: this.stepsTaken };
  }

  /**
   * Strict deserialization (M1.1, D-22): `stepsTaken` must be a
   * present integer in 0..56; anything else throws
   * {@link FormatException} — never a silent default.
   */
  static fromJson(opts: {
    playerIndex: number;
    index: number;
    colour: PlayerColour;
    json: Record<string, unknown>;
  }): Token {
    return new Token(
      opts.playerIndex,
      opts.index,
      opts.colour,
      requireIntInRange(
        opts.json.stepsTaken,
        'stepsTaken',
        0,
        Board.stepsToHome,
      ),
    );
  }

  equals(other: Token): boolean {
    return (
      other instanceof Token &&
      this.playerIndex === other.playerIndex &&
      this.index === other.index &&
      this.colour === other.colour &&
      this.stepsTaken === other.stepsTaken
    );
  }

  toString(): string {
    return (
      `Token(p${this.playerIndex}:${this.index} ` +
      `${this.colour} steps=${this.stepsTaken})`
    );
  }
}
