import { Board, type Cell } from '../game/board';
import type { GameState } from '../game/game-state';
import type { MoveResult } from '../game/move';

/**
 * Pure gameplay payload helpers (Phase 5, Stage 5).
 *
 * No NestJS, no storage, no network: the same functions describe a
 * transition for the live service, for the socket payloads, and for
 * test harnesses that record scripted engine play. Keeping the
 * derivation in one place means the persisted `move_events` row, the
 * broadcast, and a replayed reconstruction can never disagree about
 * what happened.
 *
 * Token ids are `"{seat}:{tokenIndex}"` (e.g. `"0:2"`). Seats are
 * the join-order seats from `match:started`.
 */

/** One seat of a match, as the service and the socket both see it. */
export interface SeatView {
  userId: string;
  seat: number;
  colour: string;
}

/** Parse a token id; null when malformed (the DTO rejects it first). */
export function parseTokenId(
  tokenId: string,
): { seat: number; tokenIndex: number } | null {
  const match = /^([0-3]):([0-3])$/.exec(tokenId);
  if (!match) return null;
  return { seat: Number(match[1]), tokenIndex: Number(match[2]) };
}

/** The token id for a seat/token pair. */
export function tokenIdOf(seat: number, tokenIndex: number): string {
  return `${seat}:${tokenIndex}`;
}

/** A board cell as JSON (`landing` in `token:moved`). */
export function cellJson(cell: Cell): { kind: string; index: number } {
  return { kind: cell.kind, index: cell.index };
}

/** One row of the final standings (FR-58, `match:ended`). */
export interface Standing {
  userId: string;
  seat: number;
  colour: string;
  rank: number;
  result: 'win' | 'loss' | 'forfeit';
  tokensHome: number;
}

/**
 * Final standings for a finished match [Stage 5 choice]: the winner
 * is rank 1; every other player is ordered by tokens home (desc),
 * then total steps taken (desc), then seat (asc). Forfeits do not
 * exist in Stage 5 (Stage 6), so every non-winner is a `loss`.
 */
export function computeStandings(
  state: GameState,
  seats: SeatView[],
): { winnerId: string; standings: Standing[] } {
  const winnerIndex = state.winnerIndex;
  if (winnerIndex === null) {
    throw new Error('computeStandings: the match has no winner.');
  }
  const scored = state.players.map((player, seat) => ({
    seat,
    tokensHome: player.tokens.filter((t) => t.isHome).length,
    totalSteps: player.tokens.reduce((sum, t) => sum + t.stepsTaken, 0),
  }));
  const losers = scored
    .filter((s) => s.seat !== winnerIndex)
    .sort(
      (a, b) =>
        b.tokensHome - a.tokensHome ||
        b.totalSteps - a.totalSteps ||
        a.seat - b.seat,
    );
  const order = [winnerIndex, ...losers.map((s) => s.seat)];
  const standings: Standing[] = order.map((seat, position) => ({
    userId: seats[seat].userId,
    seat,
    colour: seats[seat].colour,
    rank: position + 1,
    result: seat === winnerIndex ? 'win' : 'loss',
    tokensHome: state.players[seat].tokens.filter((t) => t.isHome).length,
  }));
  return { winnerId: seats[winnerIndex].userId, standings };
}

/**
 * Final standings for a match ended by forfeit (Stage 6, BR-15):
 * the sole remaining player is rank 1 (`win`); every other player
 * is ordered by tokens home (desc), then total steps taken (desc),
 * then seat (asc), and keeps the result the match recorded for
 * them (`forfeit` for a forfeited player, `loss` otherwise). The
 * engine's `computeStandings` cannot be used here — a forfeit win
 * is not an engine win (`winnerIndex` is null).
 */
export function computeForfeitStandings(
  state: GameState,
  seats: SeatView[],
  winnerSeat: number,
  forfeitedSeats: ReadonlySet<number>,
): { winnerId: string; standings: Standing[] } {
  const scored = state.players.map((player, seat) => ({
    seat,
    tokensHome: player.tokens.filter((t) => t.isHome).length,
    totalSteps: player.tokens.reduce((sum, t) => sum + t.stepsTaken, 0),
  }));
  const losers = scored
    .filter((s) => s.seat !== winnerSeat)
    .sort(
      (a, b) =>
        b.tokensHome - a.tokensHome ||
        b.totalSteps - a.totalSteps ||
        a.seat - b.seat,
    );
  const order = [winnerSeat, ...losers.map((s) => s.seat)];
  const standings: Standing[] = order.map((seat, position) => ({
    userId: seats[seat].userId,
    seat,
    colour: seats[seat].colour,
    rank: position + 1,
    result:
      seat === winnerSeat
        ? 'win'
        : forfeitedSeats.has(seat)
          ? 'forfeit'
          : 'loss',
    tokensHome: state.players[seat].tokens.filter((t) => t.isHome).length,
  }));
  return { winnerId: seats[winnerSeat].userId, standings };
}

/**
 * Advance the turn past forfeited players (Stage 6, BR-15).
 *
 * The engine knows nothing about forfeits: its `advancedTurn`
 * lands on the next seat by index, which may belong to a forfeited
 * player. After every engine transition — live and in replay —
 * the service applies this so the player to move is always an
 * active one. The state is unchanged when the current player is
 * active (or when no active player exists, which the match-end
 * logic prevents). A skipped turn is a fresh turn: phase
 * `awaitingRoll`, no outstanding roll, no consecutive sixes.
 */
export function skipForfeitedPlayers(
  state: GameState,
  forfeitedSeats: ReadonlySet<number>,
): GameState {
  if (forfeitedSeats.size === 0) return state;
  if (state.isFinished) return state;
  if (!forfeitedSeats.has(state.currentPlayerIndex)) return state;
  for (let step = 1; step <= state.players.length; step += 1) {
    const next = (state.currentPlayerIndex + step) % state.players.length;
    if (!forfeitedSeats.has(next)) {
      return state.copyWith({
        currentPlayerIndex: next,
        phase: 'awaitingRoll',
        lastRoll: 0,
        consecutiveSixes: 0,
        lastRollWasThirdSix: false,
        lastRollHadNoLegalMove: false,
      });
    }
  }
  return state;
}

/**
 * Apply a forfeit to an engine state (Stage 6, BR-15): the
 * forfeited player's tokens leave the board (back to the yard)
 * and, when it was their turn, the turn passes to the next
 * active player. `forfeitedSeats` must already include `seat`.
 * Pure — the same function builds the live post-forfeit state
 * and (via the stored snapshot) the replayed one.
 */
export function applyForfeitToState(
  state: GameState,
  seat: number,
  forfeitedSeats: ReadonlySet<number>,
): GameState {
  const players = state.players.map((player, index) =>
    index === seat
      ? player.copyWith({
          tokens: player.tokens.map((token) => token.sentToYard),
        })
      : player,
  );
  const yarded = state.copyWith({ players });
  return skipForfeitedPlayers(yarded, forfeitedSeats);
}

/** Stored `dice_rolled` payload (also the checkpoint snapshot). */
export interface DiceRolledPayload {
  playerId: string;
  value: number;
  /** The player the turn passed to, or null when it did not pass. */
  turnChangedPlayerId: string | null;
  /**
   * Deadline (ISO) of the turn that is current after this roll —
   * persisted so a duplicate `requestId` re-emits the exact
   * original result (FR-53), including its deadline.
   */
  turnEndsAt?: string | null;
  snapshot: Record<string, unknown>;
}

/** Stored `token_moved` payload (also the checkpoint snapshot). */
export interface TokenMovedPayload {
  playerId: string;
  tokenId: string;
  fromSteps: number;
  toSteps: number;
  landing: { kind: string; index: number };
  captured: string[];
  extraTurn: boolean;
  winnerId: string | null;
  /** Player to move next (the winner, when the match ended). */
  currentPlayerId: string;
  /** The player the turn passed to, or null (extra turn / win). */
  turnChangedPlayerId: string | null;
  matchEnded: { winnerId: string; standings: Standing[] } | null;
  /**
   * Deadline (ISO) of the turn that is current after this move —
   * persisted so a duplicate `requestId` re-emits the exact
   * original result (FR-53), including its deadline; null when
   * the match ended with the move.
   */
  turnEndsAt?: string | null;
  snapshot: Record<string, unknown>;
}

/** Stored `turn_changed` payload (also a checkpoint snapshot). */
export interface TurnChangedPayload {
  playerId: string;
  snapshot: Record<string, unknown>;
}

/** Stored `match_ended` payload (also the final checkpoint). */
export interface MatchEndedPayload {
  winnerId: string;
  standings: Standing[];
  snapshot: Record<string, unknown>;
}

/**
 * What a dice roll did to the turn: the turn passed exactly when
 * the current player changed (no legal move, or a third six).
 */
export function describeRollTransition(opts: {
  before: GameState;
  after: GameState;
  seats: SeatView[];
}): { turnChangedPlayerId: string | null } {
  if (opts.after.currentPlayerIndex === opts.before.currentPlayerIndex) {
    return { turnChangedPlayerId: null };
  }
  return {
    turnChangedPlayerId: opts.seats[opts.after.currentPlayerIndex].userId,
  };
}

/**
 * What a move did: landing cell, captures, extra turn, winner, and
 * whether the turn passed. `currentPlayerId` is the player to move
 * next — the winner when the move ended the match.
 */
export function describeMoveTransition(opts: {
  before: GameState;
  after: GameState;
  result: MoveResult;
  seats: SeatView[];
  board?: Board;
}): {
  landing: { kind: string; index: number };
  captured: string[];
  extraTurn: boolean;
  winnerId: string | null;
  currentPlayerId: string;
  turnChangedPlayerId: string | null;
  standings: Standing[] | null;
} {
  const board = opts.board ?? new Board();
  const mover = opts.after.players[opts.result.move.playerIndex];
  const landing = board.cellAt(mover.colour, opts.result.toSteps);
  const winnerId =
    opts.result.winnerIndex === null
      ? null
      : opts.seats[opts.result.winnerIndex].userId;
  const currentPlayerId =
    winnerId ?? opts.seats[opts.after.currentPlayerIndex].userId;
  let turnChangedPlayerId: string | null = null;
  if (
    winnerId === null &&
    !opts.result.extraTurn &&
    opts.after.currentPlayerIndex !== opts.before.currentPlayerIndex
  ) {
    turnChangedPlayerId = opts.seats[opts.after.currentPlayerIndex].userId;
  }
  return {
    landing: cellJson(landing),
    captured: opts.result.captured.map((ref) =>
      tokenIdOf(ref.playerIndex, ref.tokenIndex),
    ),
    extraTurn: opts.result.extraTurn,
    winnerId,
    currentPlayerId,
    turnChangedPlayerId,
    standings:
      winnerId === null
        ? null
        : computeStandings(opts.after, opts.seats).standings,
  };
}

// -- Socket payloads (SDD §12.6; every game event carries `seq`) -----

/** `dice:rolled { matchId, playerId, value, seq }`. */
export function toDiceRolledSocketPayload(
  matchId: string,
  seq: number,
  payload: DiceRolledPayload,
): Record<string, unknown> {
  return {
    matchId,
    playerId: payload.playerId,
    value: payload.value,
    seq,
  };
}

/**
 * `token:moved { matchId, tokenId, landing, captured[], extraTurn,
 * winner, seq, turn: { playerId, turnEndsAt } }`. `turnEndsAt` is
 * the deadline of the turn that is current AFTER this move (Stage
 * 6, FR-52) — null only when the match ended with the move. The
 * caller may pass it explicitly (live broadcast) or let it fall
 * back to the deadline persisted on the stored payload, so a
 * duplicate `requestId` re-emits the exact original result (FR-53).
 */
export function toTokenMovedSocketPayload(
  matchId: string,
  seq: number,
  payload: TokenMovedPayload,
  turnEndsAt?: string | null,
): Record<string, unknown> {
  return {
    matchId,
    tokenId: payload.tokenId,
    landing: payload.landing,
    captured: payload.captured,
    extraTurn: payload.extraTurn,
    winner: payload.winnerId,
    seq,
    turn: {
      playerId: payload.currentPlayerId,
      turnEndsAt: turnEndsAt ?? payload.turnEndsAt ?? null,
    },
  };
}

/**
 * `turn:changed { matchId, playerId, turnEndsAt, seq }` (Stage 6,
 * FR-52): `turnEndsAt` is the deadline of the turn that just
 * started; null only when the match ended (no turn runs).
 */
export function toTurnChangedSocketPayload(
  matchId: string,
  seq: number,
  playerId: string,
  turnEndsAt?: string | null,
): Record<string, unknown> {
  return { matchId, playerId, turnEndsAt: turnEndsAt ?? null, seq };
}

/** `match:ended { matchId, winnerId, standings[], seq }`. */
export function toMatchEndedSocketPayload(
  matchId: string,
  seq: number,
  payload: MatchEndedPayload,
): Record<string, unknown> {
  return {
    matchId,
    winnerId: payload.winnerId,
    standings: payload.standings,
    seq,
  };
}

/** One player's presence/standing inside a `match:state` payload. */
export interface MatchStatePlayerView {
  userId: string;
  seat: number;
  colour: string;
  /** True while the player is inside their disconnect grace. */
  disconnected: boolean;
  /** Grace deadline (ISO), or null while connected. */
  graceEndsAt: string | null;
  missedTurns: number;
  result: 'win' | 'loss' | 'forfeit' | null;
}

/** Extra Stage 6 fields on a `match:state` payload (all optional). */
export interface MatchStateExtras {
  /** The player to move (null when the match has ended). */
  turnPlayerId: string | null;
  /** Deadline of the current turn (ISO), or null when no turn runs. */
  turnEndsAt: string | null;
  players: MatchStatePlayerView[];
}

/**
 * `match:state { matchId, snapshot, seq, seats }` — the full
 * snapshot, replacing the client mirror wholesale (FR-57). Stage 6
 * adds `turn` (current player + timer deadline) and per-player
 * presence (`players`), so a reconnecting client learns the timer
 * state without trusting anything it stored locally (FR-55).
 */
export function toMatchStatePayload(
  matchId: string,
  snapshot: Record<string, unknown>,
  seq: number,
  seats: SeatView[],
  extras?: MatchStateExtras,
): Record<string, unknown> {
  return {
    matchId,
    snapshot,
    seq,
    seats,
    ...(extras
      ? {
          turn: {
            playerId: extras.turnPlayerId,
            turnEndsAt: extras.turnEndsAt,
          },
          players: extras.players,
        }
      : {}),
  };
}

/** `player:disconnected { matchId, playerId, graceEndsAt, seq }`. */
export function toPlayerDisconnectedSocketPayload(
  matchId: string,
  seq: number,
  playerId: string,
  graceEndsAt: string,
): Record<string, unknown> {
  return { matchId, playerId, graceEndsAt, seq };
}

/** `player:reconnected { matchId, playerId, seq }`. */
export function toPlayerReconnectedSocketPayload(
  matchId: string,
  seq: number,
  playerId: string,
): Record<string, unknown> {
  return { matchId, playerId, seq };
}

/** `player:forfeited { matchId, playerId, seq }`. */
export function toPlayerForfeitedSocketPayload(
  matchId: string,
  seq: number,
  playerId: string,
): Record<string, unknown> {
  return { matchId, playerId, seq };
}

/**
 * The socket events a stored primary intent row re-emits on a
 * duplicate `requestId` (FR-53): the original result, with the
 * original seqs, never a second transition. The primary row's
 * payload carries its follow-up (turn change / match end), because
 * the `UNIQUE (match_id, request_id)` index forbids storing the
 * same `requestId` on the follow-up row itself.
 */
export function socketEventsForStoredIntent(
  matchId: string,
  row: { type: string; seqNo: number; payload: Record<string, unknown> },
): Array<{ event: string; payload: Record<string, unknown> }> {
  if (row.type === 'dice_rolled') {
    const payload = row.payload as unknown as DiceRolledPayload;
    const events: Array<{
      event: string;
      payload: Record<string, unknown>;
    }> = [
      {
        event: 'dice:rolled',
        payload: toDiceRolledSocketPayload(matchId, row.seqNo, payload),
      },
    ];
    if (payload.turnChangedPlayerId) {
      events.push({
        event: 'turn:changed',
        payload: toTurnChangedSocketPayload(
          matchId,
          row.seqNo + 1,
          payload.turnChangedPlayerId,
          payload.turnEndsAt ?? null,
        ),
      });
    }
    return events;
  }
  if (row.type === 'token_moved') {
    const payload = row.payload as unknown as TokenMovedPayload;
    const events: Array<{
      event: string;
      payload: Record<string, unknown>;
    }> = [
      {
        event: 'token:moved',
        payload: toTokenMovedSocketPayload(
          matchId,
          row.seqNo,
          payload,
          payload.turnEndsAt ?? null,
        ),
      },
    ];
    if (payload.turnChangedPlayerId) {
      events.push({
        event: 'turn:changed',
        payload: toTurnChangedSocketPayload(
          matchId,
          row.seqNo + 1,
          payload.turnChangedPlayerId,
          payload.turnEndsAt ?? null,
        ),
      });
    }
    if (payload.matchEnded) {
      events.push({
        event: 'match:ended',
        payload: toMatchEndedSocketPayload(matchId, row.seqNo + 1, {
          winnerId: payload.matchEnded.winnerId,
          standings: payload.matchEnded.standings,
          snapshot: payload.snapshot,
        }),
      });
    }
    return events;
  }
  return [];
}
