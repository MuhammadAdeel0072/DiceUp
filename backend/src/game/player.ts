/**
 * One seat in a match (mirrors Dart `player.dart` + `ai_player.dart`).
 *
 * A match has 2–4 players with distinct colours and at least one
 * human seat (BR-01, FR-14). Each player owns exactly 4 tokens.
 *
 * The Dart engine models AI seats as an `AiPlayer` subclass so the
 * difficulty survives `copyWith` and snapshots; here a single
 * {@link Player} carries an optional `difficulty` (meaningful only
 * for AI seats) and {@link Player.copyWith} preserves it.
 */
import { ArgumentError, FormatException } from './errors';
import {
  requireEnum,
  requireList,
  requireMap,
  requireString,
} from './json-validation';
import { PLAYER_COLOURS, type PlayerColour } from './player-colour';
import { Token } from './token';

export const PLAYER_TYPES = ['human', 'ai'] as const;
export type PlayerType = (typeof PLAYER_TYPES)[number];

export const AI_DIFFICULTIES = ['easy', 'medium', 'hard'] as const;
export type AiDifficulty = (typeof AI_DIFFICULTIES)[number];

export interface SeatConfig {
  name: string;
  colour: PlayerColour;
  type?: PlayerType;
  /**
   * AI difficulty for an AI seat. Ignored for human seats. Absent
   * means the setup default (`easy`).
   */
  difficulty?: AiDifficulty;
}

export class Player {
  constructor(opts: {
    index: number;
    name: string;
    colour: PlayerColour;
    type: PlayerType;
    tokens?: readonly Token[];
    /**
     * AI difficulty. Carried into the live state so snapshots
     * preserve the true difficulty instead of defaulting to easy on
     * resume. Ignored for human seats.
     */
    difficulty?: AiDifficulty;
  }) {
    if (opts.tokens !== undefined && opts.tokens.length !== 4) {
      throw new ArgumentError('A player must own exactly 4 tokens.');
    }
    this.index = opts.index;
    this.name = opts.name;
    this.colour = opts.colour;
    this.type = opts.type;
    this.difficulty = opts.difficulty;
    this.tokens =
      opts.tokens ??
      [0, 1, 2, 3].map((i) => new Token(opts.index, i, opts.colour));
  }

  /** Seat index (0..3); also the turn-order position. */
  readonly index: number;

  readonly name: string;
  readonly colour: PlayerColour;
  readonly type: PlayerType;
  readonly difficulty?: AiDifficulty;

  /** The player's four tokens, in token-index order. */
  readonly tokens: readonly Token[];

  get isHuman(): boolean {
    return this.type === 'human';
  }

  get isAi(): boolean {
    return this.type === 'ai';
  }

  /** Number of tokens that have reached home. */
  get tokensHome(): number {
    return this.tokens.filter((t) => t.isHome).length;
  }

  /** Winning condition (BR-11): all four tokens home. */
  get hasWon(): boolean {
    return this.tokens.every((t) => t.isHome);
  }

  copyWith(opts: {
    tokens?: readonly Token[];
    difficulty?: AiDifficulty;
  }): Player {
    return new Player({
      index: this.index,
      name: this.name,
      colour: this.colour,
      type: this.type,
      difficulty: opts.difficulty ?? this.difficulty,
      tokens: opts.tokens ?? this.tokens,
    });
  }

  toJson(): Record<string, unknown> {
    const json: Record<string, unknown> = {
      name: this.name,
      colour: this.colour,
      type: this.type,
      tokens: this.tokens.map((t) => t.toJson()),
    };
    if (this.type === 'ai') {
      // Serialise the AI difficulty (M1.1): without this it would
      // not survive a snapshot round-trip.
      json.difficulty = this.difficulty ?? 'easy';
    }
    return json;
  }

  /**
   * Strict deserialization (M1.1, D-22): every field must be present
   * with the correct type. An unknown colour or type label throws
   * {@link FormatException} — it is never silently substituted with
   * another colour and an unknown type never flips an AI seat to
   * human. `tokens` must be a list of exactly four maps, checked
   * before any {@link Player} is constructed, so a bad count throws
   * {@link FormatException} rather than {@link ArgumentError} from
   * the constructor.
   *
   * A missing difficulty defaults to `easy` (the setup default);
   * a present-but-unknown difficulty throws {@link FormatException}.
   */
  static fromJson(index: number, json: Record<string, unknown>): Player {
    const name = requireString(json.name, 'name');
    const colour = requireEnum(json.colour, 'colour', PLAYER_COLOURS);
    const type = requireEnum(json.type, 'type', PLAYER_TYPES);
    const rawTokens = requireList(json.tokens, 'tokens');
    if (rawTokens.length !== 4) {
      throw new FormatException(
        `Player ${index} must have exactly 4 tokens ` +
          `(got ${rawTokens.length}).`,
      );
    }
    const tokens = [0, 1, 2, 3].map((i) => {
      const raw = requireMap(rawTokens[i], `tokens[${i}]`);
      return Token.fromJson({
        playerIndex: index,
        index: i,
        colour,
        json: raw,
      });
    });
    if (type === 'ai') {
      return new Player({
        index,
        name,
        colour,
        type,
        difficulty: Player.aiDifficulty(json),
        tokens,
      });
    }
    return new Player({ index, name, colour, type, tokens });
  }

  /**
   * Reads an AI difficulty from a serialized player: absent (or
   * null) means `easy`; a present value must name a known
   * difficulty, otherwise {@link FormatException}.
   */
  private static aiDifficulty(json: Record<string, unknown>): AiDifficulty {
    const raw = json.difficulty;
    if (raw === undefined || raw === null) return 'easy';
    return requireEnum(raw, 'difficulty', AI_DIFFICULTIES);
  }
}
