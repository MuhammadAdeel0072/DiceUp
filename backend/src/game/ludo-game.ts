/**
 * The online Ludo match aggregate (mirrors Dart `ludo_game.dart`,
 * SDD §6, SRS FR-15..FR-32).
 *
 * Pure TypeScript: no NestJS, storage or network dependency. Every
 * transition is atomic — it either applies fully to a new immutable
 * {@link GameState} or throws before changing anything (FR-21).
 *
 * The engine takes no client-supplied dice values, positions, or
 * winners: its API only accepts intents (roll, move token X) and
 * computes everything itself. Server validation of who may act lives
 * in Stage 5; the engine simply never accepts authoritative state
 * from a caller.
 *
 * Turn flow (SDD §6.4, D-20 — exactly three phases, no MOVING phase):
 * `awaitingRoll --rollDice()--> awaitingMove --applyMove()-->`
 * `awaitingRoll` (same player on an extra turn, otherwise next
 * player). A roll that offers no legal move resolves inside
 * {@link rollDice}: the turn passes, except a six still grants its
 * extra roll (BR-13).
 */
import { Board } from './board';
import { CryptoDiceRoller, type DiceRoller } from './dice-roller';
import { ArgumentError, InvalidMatchConfig, StateError } from './errors';
import { GameState } from './game-state';
import { Move, MoveResult, TokenRef } from './move';
import { Player, type SeatConfig } from './player';
import { RulesetConfig } from './ruleset-config';

export class LudoGame {
  /**
   * Starts a new match (SDD §6.3).
   *
   * Validates: 2–4 seats, distinct colours, at least one human seat
   * (BR-01, FR-14) and a valid ruleset. Throws
   * {@link InvalidMatchConfig} or {@link InvalidRulesetConfig}; no
   * match is created on failure.
   */
  static newMatch(opts: {
    seats: SeatConfig[];
    ruleset?: RulesetConfig;
    diceRoller?: DiceRoller;
    board?: Board;
  }): LudoGame {
    const ruleset = opts.ruleset ?? new RulesetConfig();
    ruleset.validate();
    if (opts.seats.length < 2 || opts.seats.length > 4) {
      throw new InvalidMatchConfig('A match needs 2–4 players (FR-13).');
    }
    const colours = new Set(opts.seats.map((s) => s.colour));
    if (colours.size !== opts.seats.length) {
      throw new InvalidMatchConfig(
        'Each player needs a distinct colour (BR-01).',
      );
    }
    if (opts.seats.every((s) => (s.type ?? 'human') !== 'human')) {
      throw new InvalidMatchConfig(
        'A match needs at least one human seat (FR-14).',
      );
    }
    const players = opts.seats.map((seat, i) => {
      if (seat.type === 'ai') {
        return new Player({
          index: i,
          name: seat.name,
          colour: seat.colour,
          type: 'ai',
          difficulty: seat.difficulty ?? 'easy',
        });
      }
      return new Player({
        index: i,
        name: seat.name,
        colour: seat.colour,
        type: seat.type ?? 'human',
      });
    });
    const state = GameState.initial({ players, ruleset });
    return new LudoGame(
      state,
      opts.board ?? new Board(),
      ruleset,
      opts.diceRoller ?? new CryptoDiceRoller(),
    );
  }

  /**
   * Builds a game around an existing `state` — used by snapshot
   * restore and by tests / rule-vector harnesses that need an exact
   * board position (SDD §6.9). The state's ruleset version must
   * match `ruleset`.
   */
  static fromState(
    state: GameState,
    opts: {
      ruleset?: RulesetConfig;
      diceRoller?: DiceRoller;
      board?: Board;
    } = {},
  ): LudoGame {
    const ruleset = opts.ruleset ?? new RulesetConfig();
    ruleset.validate();
    if (state.rulesetVersion !== ruleset.version) {
      throw new ArgumentError(
        `Snapshot ruleset ${state.rulesetVersion} does not match ` +
          `ruleset ${ruleset.version}.`,
      );
    }
    return new LudoGame(
      state,
      opts.board ?? new Board(),
      ruleset,
      opts.diceRoller ?? new CryptoDiceRoller(),
    );
  }

  private constructor(
    private stateValue: GameState,
    readonly board: Board,
    readonly ruleset: RulesetConfig,
    private readonly diceRoller: DiceRoller,
  ) {}

  /** The current immutable snapshot. Observers must treat it as read-only. */
  get state(): GameState {
    return this.stateValue;
  }

  get players(): readonly Player[] {
    return this.stateValue.players;
  }

  get currentPlayer(): Player {
    return this.stateValue.currentPlayer;
  }

  get currentPlayerIndex(): number {
    return this.stateValue.currentPlayerIndex;
  }

  get isFinished(): boolean {
    return this.stateValue.isFinished;
  }

  get winnerIndex(): number | null {
    return this.stateValue.winnerIndex;
  }

  get winner(): Player | null {
    return this.winnerIndex === null
      ? null
      : this.stateValue.players[this.winnerIndex];
  }

  /**
   * Rolls the dice for the active player (FR-15, BR-02, BR-03).
   *
   * Only the active player may roll, and only while a roll is
   * pending; otherwise throws {@link StateError} with state
   * unchanged. Returns the value (1..6). After the call, inspect
   * {@link state}:
   * * `phase == awaitingMove` — choose one of {@link legalMoves};
   * * `phase == awaitingRoll` and the player changed — the roll
   *   offered no legal move (BR-13) or was a third six (BR-07);
   * * `phase == awaitingRoll` and the player is unchanged — a six
   *   with no legal move granted an extra roll (BR-13).
   */
  rollDice(): number {
    if (this.stateValue.isFinished) {
      throw new StateError('Cannot roll: the match is finished.');
    }
    if (this.stateValue.phase !== 'awaitingRoll') {
      throw new StateError('Cannot roll: a roll is already outstanding.');
    }
    const value = this.diceRoller.roll();
    if (!Number.isInteger(value) || value < 1 || value > 6) {
      throw new StateError(`DiceRoller returned an invalid value: ${value}.`);
    }

    const consecutive = value === 6 ? this.stateValue.consecutiveSixes + 1 : 0;
    const isThirdSix =
      value === 6 &&
      this.ruleset.maxConsecutiveSixes > 0 &&
      consecutive >= this.ruleset.maxConsecutiveSixes;

    if (isThirdSix) {
      // BR-07: the third consecutive six is shown but not played.
      this.stateValue = this.advancedTurn({
        lastRoll: value,
        lastRollWasThirdSix: true,
      });
      return value;
    }

    const next = this.stateValue.copyWith({
      phase: 'awaitingMove',
      lastRoll: value,
      consecutiveSixes: consecutive,
      lastRollWasThirdSix: false,
      lastRollHadNoLegalMove: false,
    });
    this.stateValue = next;

    if (this.legalMoves().length === 0) {
      // BR-13: no legal move — the turn passes, except a six still
      // grants its extra roll.
      if (value === 6) {
        this.stateValue = next.copyWith({
          phase: 'awaitingRoll',
          lastRollHadNoLegalMove: true,
        });
      } else {
        this.stateValue = this.advancedTurn({
          from: next,
          lastRoll: value,
          lastRollHadNoLegalMove: true,
        });
      }
    }
    return value;
  }

  /**
   * Legal moves for the outstanding roll (FR-16, SDD §6.5).
   * Empty unless the phase is `awaitingMove`.
   */
  legalMoves(): Move[] {
    if (this.stateValue.phase !== 'awaitingMove') return [];
    return LudoGame.legalMovesFor(
      this.stateValue,
      this.stateValue.lastRoll,
      this.ruleset,
      this.board,
    );
  }

  /**
   * Pure legal-move computation, shared by the engine and the AI
   * (FR-35) and usable standalone in rule-vector tests.
   */
  static legalMovesFor(
    state: GameState,
    roll: number,
    ruleset: RulesetConfig,
    // Kept in the signature for parity with the Dart engine and the
    // AI call-site (FR-35); legality needs no board geometry today.
    _board: Board,
  ): Move[] {
    const player = state.currentPlayer;
    const moves: Move[] = [];
    for (const token of player.tokens) {
      const canMove = token.canMove(roll, {
        releaseRolls: ruleset.releaseRolls,
        exactFinish: ruleset.exactFinish,
      });
      if (canMove) {
        moves.push(new Move(player.index, token.index));
      }
    }
    return moves;
  }

  /**
   * Applies one move atomically (FR-17, SDD §6.5, Algorithm 1).
   *
   * Throws {@link StateError} if no move is pending and
   * {@link ArgumentError} if `move` is not in {@link legalMoves} —
   * in both cases the state is unchanged (FR-21). On success
   * returns a {@link MoveResult} describing exactly what happened
   * (captures, extra turn, winner).
   */
  applyMove(move: Move): MoveResult {
    if (this.stateValue.isFinished) {
      throw new StateError('Cannot move: the match is finished.');
    }
    if (this.stateValue.phase !== 'awaitingMove') {
      throw new StateError('Cannot move: roll the dice first.');
    }
    if (move.playerIndex !== this.stateValue.currentPlayerIndex) {
      throw new ArgumentError("Cannot move: it is not that player's turn.");
    }
    const legal = this.legalMoves();
    if (!legal.some((m) => m.equals(move))) {
      throw new ArgumentError(`Illegal move: ${move} is not a legal move.`);
    }

    const player = this.stateValue.currentPlayer;
    const token = player.tokens[move.tokenIndex];
    const fromSteps = token.stepsTaken;
    // A release spends the roll entering the board: the token lands
    // on its start cell (step 1), it does not advance by the roll
    // (BR-04). Any other move advances by exactly the roll (BR-05).
    let toSteps = token.isInYard ? 1 : fromSteps + this.stateValue.lastRoll;
    if (!this.ruleset.exactFinish && toSteps > Board.stepsToHome) {
      toSteps = Board.stepsToHome; // Non-exact variant: overshoot lands home.
    }

    // BR-08: capture opponent tokens on the landing cell, unless it
    // is a safe cell (BR-09). Passing over tokens never captures.
    const captured: TokenRef[] = [];
    const landing = this.board.cellAt(token.colour, toSteps);
    const isCaptureCell =
      landing.kind === 'track' && !this.board.isSafe(landing);
    // Mutable working copies; new immutable Players are built below.
    const tokenLists = this.stateValue.players.map((p) => [...p.tokens]);
    if (isCaptureCell) {
      for (let pi = 0; pi < tokenLists.length; pi++) {
        if (pi === player.index) continue;
        for (let i = 0; i < tokenLists[pi].length; i++) {
          const other = tokenLists[pi][i];
          if (other.isOnTrack && other.cell.equals(landing)) {
            tokenLists[pi][i] = other.sentToYard;
            captured.push(new TokenRef(pi, i));
          }
        }
      }
    }

    tokenLists[player.index][move.tokenIndex] = token.copyWith({
      stepsTaken: toSteps,
    });
    const updatedPlayers = this.stateValue.players.map((p, i) =>
      p.copyWith({ tokens: tokenLists[i] }),
    );

    const enteredHomePath =
      fromSteps <= Board.lastTrackStep &&
      toSteps > Board.lastTrackStep &&
      toSteps < Board.stepsToHome;
    const reachedHome = toSteps === Board.stepsToHome;
    const won = updatedPlayers[player.index].hasWon;

    const extraTurn =
      !won &&
      ((this.ruleset.extraTurnOnSix && this.stateValue.lastRoll === 6) ||
        (this.ruleset.extraTurnOnCapture && captured.length > 0) ||
        (this.ruleset.extraTurnOnHome && reachedHome));

    const result = new MoveResult(
      move,
      fromSteps,
      toSteps,
      captured,
      enteredHomePath,
      reachedHome,
      extraTurn,
      won ? player.index : null,
    );

    if (won) {
      // BR-11: first player with all four tokens home wins; the
      // match ends (default; see report note on ranking play).
      this.stateValue = this.stateValue.copyWith({
        players: updatedPlayers,
        phase: 'finished',
        winnerIndex: player.index,
        moveCount: this.stateValue.moveCount + 1,
        lastRoll: 0,
      });
      return result;
    }
    if (extraTurn) {
      this.stateValue = this.stateValue.copyWith({
        players: updatedPlayers,
        phase: 'awaitingRoll',
        lastRoll: 0,
        moveCount: this.stateValue.moveCount + 1,
      });
      return result;
    }
    this.stateValue = this.advancedTurn({
      from: this.stateValue.copyWith({
        players: updatedPlayers,
        moveCount: this.stateValue.moveCount + 1,
      }),
      lastRoll: 0,
    });
    return result;
  }

  /**
   * Passes the turn to the next player clockwise (FR-19).
   * Only valid between turns (phase `awaitingRoll`).
   */
  nextTurn(): void {
    if (this.stateValue.isFinished) {
      throw new StateError('Cannot pass the turn: the match is finished.');
    }
    if (this.stateValue.phase !== 'awaitingRoll') {
      throw new StateError(
        'Cannot pass the turn while a roll or move is pending.',
      );
    }
    this.stateValue = this.advancedTurn({ lastRoll: 0 });
  }

  /** Serialises the current snapshot to JSON (SRS FR-29 resume). */
  snapshot(): Record<string, unknown> {
    return this.stateValue.toJson();
  }

  /**
   * Restores a game from a `snapshot` produced by {@link snapshot}.
   * The snapshot's ruleset version must match `ruleset`.
   */
  static restore(
    snapshot: Record<string, unknown>,
    opts: {
      ruleset?: RulesetConfig;
      diceRoller?: DiceRoller;
      board?: Board;
    } = {},
  ): LudoGame {
    return LudoGame.fromState(GameState.fromJson(snapshot), opts);
  }

  /** Advances to the next player clockwise, clearing turn state. */
  private advancedTurn(opts: {
    from?: GameState;
    lastRoll: number;
    lastRollWasThirdSix?: boolean;
    lastRollHadNoLegalMove?: boolean;
  }): GameState {
    const base = opts.from ?? this.stateValue;
    const nextPlayer = (base.currentPlayerIndex + 1) % base.players.length;
    return base.copyWith({
      currentPlayerIndex: nextPlayer,
      phase: 'awaitingRoll',
      lastRoll: opts.lastRoll,
      consecutiveSixes: 0,
      lastRollWasThirdSix: opts.lastRollWasThirdSix ?? false,
      lastRollHadNoLegalMove: opts.lastRollHadNoLegalMove ?? false,
    });
  }
}
