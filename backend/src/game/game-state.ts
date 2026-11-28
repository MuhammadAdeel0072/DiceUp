/**
 * An immutable snapshot of a whole match (mirrors Dart
 * `game_state.dart`, SDD §6.1).
 *
 * Every transition takes a {@link GameState} and returns a new one;
 * the UI, the AI and the resume store all observe snapshots and never
 * mutate live state. A snapshot serialises to JSON, which is how
 * resume (SRS FR-29) and the shared rule test vectors (SDD §6.9)
 * work.
 *
 * Deserialization is strict (M1.1, D-22): {@link GameState.fromJson}
 * throws {@link FormatException} on any malformed or unsupported
 * snapshot instead of silently repairing it.
 */
import { FormatException } from './errors';
import {
  requireBool,
  requireEnum,
  requireInt,
  requireIntInRange,
  requireIso8601DateTime,
  requireList,
  requireMap,
  requireString,
} from './json-validation';
import { Player } from './player';
import { RulesetConfig } from './ruleset-config';

/** Turn state machine (SDD §6.4). Exactly three phases (D-20). */
export const TURN_PHASES = [
  'awaitingRoll',
  'awaitingMove',
  'finished',
] as const;

export type TurnPhase = (typeof TURN_PHASES)[number];

export class GameState {
  constructor(opts: {
    players: readonly Player[];
    currentPlayerIndex: number;
    rulesetVersion: string;
    ruleset?: RulesetConfig;
    startedAt?: Date | null;
    phase?: TurnPhase;
    lastRoll?: number;
    consecutiveSixes?: number;
    winnerIndex?: number | null;
    moveCount?: number;
    lastRollWasThirdSix?: boolean;
    lastRollHadNoLegalMove?: boolean;
  }) {
    this.players = opts.players;
    this.currentPlayerIndex = opts.currentPlayerIndex;
    this.rulesetVersion = opts.rulesetVersion;
    this.ruleset = opts.ruleset ?? new RulesetConfig();
    this.startedAt = opts.startedAt ?? null;
    this.phase = opts.phase ?? 'awaitingRoll';
    this.lastRoll = opts.lastRoll ?? 0;
    this.consecutiveSixes = opts.consecutiveSixes ?? 0;
    this.winnerIndex = opts.winnerIndex ?? null;
    this.moveCount = opts.moveCount ?? 0;
    this.lastRollWasThirdSix = opts.lastRollWasThirdSix ?? false;
    this.lastRollHadNoLegalMove = opts.lastRollHadNoLegalMove ?? false;
  }

  /** Players in clockwise seat order. */
  readonly players: readonly Player[];

  /** Index into `players` of the player whose turn it is. */
  readonly currentPlayerIndex: number;

  /** Version of the frozen ruleset (BR-14). */
  readonly rulesetVersion: string;

  /**
   * The frozen ruleset this match plays under (BR-14). Its `version`
   * always agrees with `rulesetVersion`; {@link fromJson} rejects a
   * snapshot where they disagree.
   */
  readonly ruleset: RulesetConfig;

  /**
   * Wall-clock time the match started. Used by the resume store to
   * compute match duration. Null for states built directly in
   * tests; stamped at match start by {@link GameState.initial}.
   * Required in persisted snapshots: {@link fromJson} rejects a
   * missing `startedAt`.
   */
  readonly startedAt: Date | null;

  readonly phase: TurnPhase;

  /** Most recent dice value (0 = no roll yet in this turn). */
  readonly lastRoll: number;

  /** Sixes rolled in the current turn sequence (BR-07). */
  readonly consecutiveSixes: number;

  /** Index of the winner once the match is finished (BR-11). */
  readonly winnerIndex: number | null;

  /** Number of moves applied since the match started. */
  readonly moveCount: number;

  /**
   * The last roll was a third consecutive six: it was shown but not
   * played, and the turn passed (BR-07).
   */
  readonly lastRollWasThirdSix: boolean;

  /** The last roll offered no legal move (BR-13). */
  readonly lastRollHadNoLegalMove: boolean;

  get currentPlayer(): Player {
    return this.players[this.currentPlayerIndex];
  }

  get isFinished(): boolean {
    return this.phase === 'finished';
  }

  copyWith(opts: {
    players?: readonly Player[];
    currentPlayerIndex?: number;
    ruleset?: RulesetConfig;
    startedAt?: Date | null;
    phase?: TurnPhase;
    lastRoll?: number;
    consecutiveSixes?: number;
    winnerIndex?: number | null;
    moveCount?: number;
    lastRollWasThirdSix?: boolean;
    lastRollHadNoLegalMove?: boolean;
  }): GameState {
    return new GameState({
      players: opts.players ?? this.players,
      currentPlayerIndex: opts.currentPlayerIndex ?? this.currentPlayerIndex,
      rulesetVersion: this.rulesetVersion,
      ruleset: opts.ruleset ?? this.ruleset,
      startedAt: opts.startedAt ?? this.startedAt,
      phase: opts.phase ?? this.phase,
      lastRoll: opts.lastRoll ?? this.lastRoll,
      consecutiveSixes: opts.consecutiveSixes ?? this.consecutiveSixes,
      winnerIndex: opts.winnerIndex ?? this.winnerIndex,
      moveCount: opts.moveCount ?? this.moveCount,
      lastRollWasThirdSix: opts.lastRollWasThirdSix ?? this.lastRollWasThirdSix,
      lastRollHadNoLegalMove:
        opts.lastRollHadNoLegalMove ?? this.lastRollHadNoLegalMove,
    });
  }

  /**
   * Initial state for a fresh match: all tokens in their yards.
   * `startedAt` is stamped with the wall-clock time unless a fixed
   * value is supplied (tests that need deterministic snapshots).
   */
  static initial(opts: {
    players: readonly Player[];
    ruleset?: RulesetConfig;
    startedAt?: Date;
  }): GameState {
    const ruleset = opts.ruleset ?? new RulesetConfig();
    return new GameState({
      players: opts.players,
      currentPlayerIndex: 0,
      rulesetVersion: ruleset.version,
      ruleset,
      startedAt: opts.startedAt ?? new Date(),
    });
  }

  toJson(): Record<string, unknown> {
    return {
      formatVersion: 1,
      rulesetVersion: this.rulesetVersion,
      ruleset: this.ruleset.toJson(),
      startedAt: this.startedAt === null ? null : this.startedAt.toISOString(),
      currentPlayerIndex: this.currentPlayerIndex,
      phase: this.phase,
      lastRoll: this.lastRoll,
      consecutiveSixes: this.consecutiveSixes,
      winnerIndex: this.winnerIndex,
      moveCount: this.moveCount,
      lastRollWasThirdSix: this.lastRollWasThirdSix,
      lastRollHadNoLegalMove: this.lastRollHadNoLegalMove,
      players: this.players.map((p) => p.toJson()),
    };
  }

  /**
   * Strict deserialization (M1.1, D-22).
   *
   * Throws {@link FormatException} — never a silent default,
   * substitution, or type coercion — on: a missing/non-integer/`!= 1`
   * `formatVersion`; a missing/invalid embedded `ruleset` (see
   * {@link RulesetConfig.fromJson}); a `rulesetVersion` that
   * disagrees with the embedded ruleset version; a missing/non-list
   * `players`, a player count outside 2–4, a non-map player entry,
   * duplicate colours, or zero human players; an out-of-range
   * `currentPlayerIndex`; a `lastRoll` outside 0–6; a
   * `consecutiveSixes` that the embedded ruleset could not have
   * produced (negative, or `>= maxConsecutiveSixes` when the limit
   * is enabled — the engine resets the count to 0 when the limit
   * fires, so a persisted state never holds it; when the limit is
   * disabled (`maxConsecutiveSixes: 0`, D-29) any count `>= 0` is
   * legitimate); a negative `moveCount`; an unknown `phase`; a
   * `winnerIndex` set while the phase is not finished, a
   * missing/out-of-range `winnerIndex` while finished, or a
   * non-integer `winnerIndex`; a missing, null, non-string, or
   * not-a-complete-ISO-8601-date-time `startedAt`; or any
   * wrong-typed field.
   *
   * Unknown top-level keys are ignored (forward compatibility).
   * No `moveHistory` is read or written (D-23).
   */
  static fromJson(json: Record<string, unknown>): GameState {
    const formatVersion = requireInt(json.formatVersion, 'formatVersion');
    if (formatVersion !== 1) {
      throw new FormatException(
        `Unsupported snapshot formatVersion ${formatVersion}; expected 1.`,
      );
    }
    const ruleset = RulesetConfig.fromJson(requireMap(json.ruleset, 'ruleset'));
    const rulesetVersion = requireString(json.rulesetVersion, 'rulesetVersion');
    if (ruleset.version !== rulesetVersion) {
      throw new FormatException(
        `Snapshot rulesetVersion "${rulesetVersion}" does not match ` +
          `embedded ruleset version "${ruleset.version}".`,
      );
    }
    const rawPlayers = requireList(json.players, 'players');
    if (rawPlayers.length < 2 || rawPlayers.length > 4) {
      throw new FormatException(
        `Snapshot must have 2–4 players (got ${rawPlayers.length}).`,
      );
    }
    const players = rawPlayers.map((raw, i) =>
      Player.fromJson(i, requireMap(raw, `players[${i}]`)),
    );
    const colours = new Set(players.map((p) => p.colour));
    if (colours.size !== players.length) {
      throw new FormatException('Snapshot players must have distinct colours.');
    }
    if (players.every((p) => p.isAi)) {
      throw new FormatException(
        'Snapshot must have at least one human player.',
      );
    }
    const currentPlayerIndex = requireIntInRange(
      json.currentPlayerIndex,
      'currentPlayerIndex',
      0,
      players.length - 1,
    );
    const phase = requireEnum(json.phase, 'phase', TURN_PHASES);
    const lastRoll = requireIntInRange(json.lastRoll, 'lastRoll', 0, 6);
    // Ruleset-aware bound (M1.1 review): the engine resets the count
    // to 0 when the third-six limit fires (see LudoGame.rollDice), so
    // a persisted state can never hold a count >= the limit — except
    // when the limit is disabled (maxConsecutiveSixes: 0, D-29), where
    // the count grows without bound and any value >= 0 is legitimate.
    const consecutiveSixes = requireInt(
      json.consecutiveSixes,
      'consecutiveSixes',
    );
    if (
      consecutiveSixes < 0 ||
      (ruleset.maxConsecutiveSixes > 0 &&
        consecutiveSixes >= ruleset.maxConsecutiveSixes)
    ) {
      throw new FormatException(
        `Snapshot consecutiveSixes ${consecutiveSixes} is impossible ` +
          `under ruleset maxConsecutiveSixes ` +
          `${ruleset.maxConsecutiveSixes}.`,
      );
    }
    const moveCount = requireInt(json.moveCount, 'moveCount');
    if (moveCount < 0) {
      throw new FormatException('Snapshot moveCount must not be negative.');
    }
    const lastRollWasThirdSix = requireBool(
      json.lastRollWasThirdSix,
      'lastRollWasThirdSix',
    );
    const lastRollHadNoLegalMove = requireBool(
      json.lastRollHadNoLegalMove,
      'lastRollHadNoLegalMove',
    );
    const winnerIndex = GameState.winnerIndex(json, phase, players.length);
    const startedAt = GameState.startedAt(json);
    return new GameState({
      players,
      currentPlayerIndex,
      rulesetVersion,
      ruleset,
      startedAt,
      phase,
      lastRoll,
      consecutiveSixes,
      winnerIndex,
      moveCount,
      lastRollWasThirdSix,
      lastRollHadNoLegalMove,
    });
  }

  /** Winner consistency (BR-11): a finished match must name a winner in range; an unfinished match must not name one. */
  private static winnerIndex(
    json: Record<string, unknown>,
    phase: TurnPhase,
    playerCount: number,
  ): number | null {
    const raw = json.winnerIndex;
    if (raw === undefined || raw === null) {
      if (phase === 'finished') {
        throw new FormatException(
          'A finished snapshot must have a winnerIndex.',
        );
      }
      return null;
    }
    if (typeof raw !== 'number' || !Number.isInteger(raw)) {
      throw new FormatException('Snapshot winnerIndex must be an integer.');
    }
    if (phase !== 'finished') {
      throw new FormatException(
        'Snapshot winnerIndex must be null while the match is not finished.',
      );
    }
    if (raw < 0 || raw >= playerCount) {
      throw new FormatException(`Snapshot winnerIndex ${raw} is out of range.`);
    }
    return raw;
  }

  /**
   * `startedAt` is required in a persisted snapshot: a missing key,
   * a null, a non-string, or a string that is not a complete
   * ISO-8601 date-time all throw {@link FormatException} (see
   * {@link requireIso8601DateTime}). The accepted shape is
   * `YYYY-MM-DDTHH:MM:SS` with optional fractional seconds and an
   * optional `Z` or `±HH:MM` zone; the literal `T` separator is
   * required, seconds are required, and every component is checked
   * against its real range. A naive date-time (no zone) is accepted
   * for legacy stored snapshots and Dart offline snapshots; the
   * backend snapshot writer emits a Z-suffixed UTC instant instead
   * (see {@link toJson}).
   */
  private static startedAt(json: Record<string, unknown>): Date {
    if (!('startedAt' in json)) {
      throw new FormatException('Snapshot startedAt is required.');
    }
    return requireIso8601DateTime(json.startedAt, 'startedAt');
  }

  toString(): string {
    return (
      `GameState(player=${this.currentPlayerIndex} phase=${this.phase} ` +
      `roll=${this.lastRoll} sixes=${this.consecutiveSixes} ` +
      `winner=${this.winnerIndex})`
    );
  }
}
