/**
 * An intended move: the active player moves one of their tokens
 * (mirrors Dart `move.dart`).
 *
 * A {@link Move} carries no dice value — the roll lives in the
 * {@link GameState} that produced the legal-move list (SDD §6.5).
 * The engine takes no client-supplied dice values, positions, or
 * winners: its API only accepts intents (roll, move token X) and
 * computes everything itself.
 */

/** Identifies one token: its owner and its index among that player's tokens. */
export class TokenRef {
  constructor(
    readonly playerIndex: number,
    readonly tokenIndex: number,
  ) {}

  equals(other: TokenRef): boolean {
    return (
      other instanceof TokenRef &&
      this.playerIndex === other.playerIndex &&
      this.tokenIndex === other.tokenIndex
    );
  }

  toString(): string {
    return `TokenRef(p${this.playerIndex}:${this.tokenIndex})`;
  }
}

export class Move {
  constructor(
    readonly playerIndex: number,
    readonly tokenIndex: number,
  ) {}

  get tokenRef(): TokenRef {
    return new TokenRef(this.playerIndex, this.tokenIndex);
  }

  equals(other: Move): boolean {
    return (
      other instanceof Move &&
      this.playerIndex === other.playerIndex &&
      this.tokenIndex === other.tokenIndex
    );
  }

  toString(): string {
    return `Move(p${this.playerIndex}:${this.tokenIndex})`;
  }
}

/**
 * The outcome of applying one {@link Move} atomically (SDD §6.5,
 * Algorithm 1). The UI animates exactly what this reports — it never
 * re-derives it.
 */
export class MoveResult {
  constructor(
    readonly move: Move,
    /** The moved token's steps before / after the move. */
    readonly fromSteps: number,
    readonly toSteps: number,
    /** Opponent tokens sent back to their yard by this move (BR-08). */
    readonly captured: readonly TokenRef[] = [],
    /** The token entered its home path on this move (BR-10). */
    readonly enteredHomePath = false,
    /** The token reached home on this move (BR-10). */
    readonly reachedHome = false,
    /** The same player rolls again (BR-06). */
    readonly extraTurn = false,
    /** Index of the match winner, if this move ended the match (BR-11). */
    readonly winnerIndex: number | null = null,
  ) {}

  get isWinningMove(): boolean {
    return this.winnerIndex !== null;
  }

  toString(): string {
    return (
      `MoveResult(${this.move} ${this.fromSteps}->${this.toSteps} ` +
      `captured=${JSON.stringify(this.captured)} ` +
      `extraTurn=${this.extraTurn} winner=${this.winnerIndex})`
    );
  }
}
