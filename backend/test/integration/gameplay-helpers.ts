import type { DataSource } from 'typeorm';
import { LudoGame, Move, type DiceRoller } from '../../src/game';
import {
  describeMoveTransition,
  describeRollTransition,
} from '../../src/match/match-payloads';

/**
 * Scripted engine play for gameplay tests (Stage 5).
 *
 * Drives the real engine in-process with a scripted dice source and
 * records the exact `move_events` rows MatchService would have
 * written — same derivation functions, so the recorded log agrees
 * with the service by construction. A test inserts the rows (seq
 * 2..N; seq 1 is the `match_started` row `startMatch` wrote) and
 * then continues the match live through the service or the socket.
 * Replay must reproduce the recorded position; that is itself
 * asserted by the tests that use these setups.
 */

export interface RecordedSeat {
  userId: string;
  seat: number;
  colour: string;
  name: string;
}

export interface RecordedEvent {
  type: string;
  actorId: string | null;
  payload: Record<string, unknown>;
}

/** Move the furthest token (ties → lowest index); release only when forced. */
export function furthestTokenMove(game: LudoGame): Move | null {
  const legal = game.legalMoves();
  if (legal.length === 0) return null;
  return legal.reduce((best, move) => {
    const steps = (game: LudoGame, m: Move): number =>
      game.state.players[m.playerIndex].tokens[m.tokenIndex].stepsTaken;
    const a = steps(game, move);
    const b = steps(game, best);
    if (a > b) return move;
    if (a === b && move.tokenIndex < best.tokenIndex) return move;
    return best;
  });
}

/**
 * Play until `stopWhen` holds at the top of a turn (checked before
 * rolling, so the final state is always `awaitingRoll` for the
 * player to move). Throws when the game finishes first or the roll
 * budget is spent — a setup failure, never a silent bad position.
 */
export function recordEnginePlay(opts: {
  seats: RecordedSeat[];
  rollFor: (game: LudoGame) => number;
  chooseMove?: (game: LudoGame) => Move | null;
  stopWhen: (game: LudoGame) => boolean;
  maxRolls?: number;
}): { events: RecordedEvent[]; finalState: Record<string, unknown> } {
  const maxRolls = opts.maxRolls ?? 2000;
  const chooseMove = opts.chooseMove ?? furthestTokenMove;
  const holder: { game?: LudoGame } = {};
  const roller: DiceRoller = {
    roll: () => opts.rollFor(holder.game!),
  };
  holder.game = LudoGame.newMatch({
    seats: opts.seats.map((s) => ({
      name: s.name,
      colour: s.colour as 'red' | 'green' | 'yellow' | 'blue',
      type: 'human' as const,
    })),
    diceRoller: roller,
  });
  const game = holder.game;
  const events: RecordedEvent[] = [];
  let rolls = 0;
  while (rolls < maxRolls) {
    if (game.isFinished) {
      throw new Error(
        'recordEnginePlay: the scripted game finished before stopWhen held.',
      );
    }
    if (game.state.phase === 'awaitingRoll' && opts.stopWhen(game)) break;
    const before = game.state;
    const playerId = opts.seats[game.currentPlayerIndex].userId;
    const value = game.rollDice();
    rolls += 1;
    const afterRoll = game.state;
    const { turnChangedPlayerId } = describeRollTransition({
      before,
      after: afterRoll,
      seats: opts.seats,
    });
    events.push({
      type: 'dice_rolled',
      actorId: playerId,
      payload: {
        playerId,
        value,
        turnChangedPlayerId,
        snapshot: afterRoll.toJson(),
      },
    });
    if (turnChangedPlayerId) {
      events.push({
        type: 'turn_changed',
        actorId: null,
        payload: {
          playerId: turnChangedPlayerId,
          snapshot: afterRoll.toJson(),
        },
      });
    }
    if (afterRoll.phase === 'awaitingMove') {
      const move = chooseMove(game);
      if (!move) {
        throw new Error('recordEnginePlay: no move chosen while awaitingMove.');
      }
      const moveBefore = game.state;
      const result = game.applyMove(move);
      const after = game.state;
      const desc = describeMoveTransition({
        before: moveBefore,
        after,
        result,
        seats: opts.seats,
      });
      const tokenId = `${move.playerIndex}:${move.tokenIndex}`;
      events.push({
        type: 'token_moved',
        actorId: playerId,
        payload: {
          playerId,
          tokenId,
          fromSteps: result.fromSteps,
          toSteps: result.toSteps,
          landing: desc.landing,
          captured: desc.captured,
          extraTurn: desc.extraTurn,
          winnerId: desc.winnerId,
          currentPlayerId: desc.currentPlayerId,
          turnChangedPlayerId: desc.turnChangedPlayerId,
          matchEnded:
            desc.winnerId === null
              ? null
              : { winnerId: desc.winnerId, standings: desc.standings },
          snapshot: after.toJson(),
        },
      });
      if (desc.turnChangedPlayerId) {
        events.push({
          type: 'turn_changed',
          actorId: null,
          payload: {
            playerId: desc.turnChangedPlayerId,
            snapshot: after.toJson(),
          },
        });
      }
      if (desc.winnerId) {
        events.push({
          type: 'match_ended',
          actorId: playerId,
          payload: {
            winnerId: desc.winnerId,
            standings: desc.standings,
            snapshot: after.toJson(),
          },
        });
      }
    }
  }
  if (rolls >= maxRolls) {
    throw new Error(
      'recordEnginePlay: maxRolls reached without stopWhen holding.',
    );
  }
  return { events, finalState: game.state.toJson() };
}

/**
 * Capture setup: red token 0 at step 7 (cell 6), green token 0 at
 * step 3 (cell 15), red to move. Live rolls of 6 then 3 move red
 * 7 → 13 → 16 (cell 15) and capture green's token.
 */
export function captureSetup(seats: RecordedSeat[]): {
  events: RecordedEvent[];
  finalState: Record<string, unknown>;
} {
  const index = [0, 0];
  return recordEnginePlay({
    seats,
    rollFor: (game) => {
      const player = game.currentPlayerIndex;
      const seq = player === 0 ? [6, 6, 6] : [6, 2];
      return seq[index[player]++ % seq.length];
    },
    stopWhen: (game) => {
      if (
        game.currentPlayerIndex !== 0 ||
        game.state.phase !== 'awaitingRoll'
      ) {
        return false;
      }
      return (
        game.state.players[0].tokens[0].stepsTaken === 7 &&
        game.state.players[1].tokens[0].stepsTaken === 3
      );
    },
  });
}

/**
 * Near-win setup: red has three tokens home and the fourth at step
 * 55, red to move. A live roll of 1 and a move of that token wins.
 * Green never leaves the yard (it only ever rolls 1).
 */
export function nearWinSetup(seats: RecordedSeat[]): {
  events: RecordedEvent[];
  finalState: Record<string, unknown>;
} {
  const index = [0, 0];
  return recordEnginePlay({
    seats,
    rollFor: (game) => {
      const player = game.currentPlayerIndex;
      if (player === 1) return 1;
      const red = game.state.players[0];
      const homes = red.tokens.filter((t) => t.isHome).length;
      if (homes === 3) {
        // Inch the last token forward — except from the yard, where
        // only a 6 releases it (a 1 would stall forever).
        const last = red.tokens.find((t) => !t.isHome)!;
        return last.stepsTaken === 0 ? 6 : 1;
      }
      const seq = [6, 5, 1];
      return seq[index[0]++ % seq.length];
    },
    stopWhen: (game) => {
      if (
        game.currentPlayerIndex !== 0 ||
        game.state.phase !== 'awaitingRoll'
      ) {
        return false;
      }
      const red = game.state.players[0];
      const homes = red.tokens.filter((t) => t.isHome).length;
      const rest = red.tokens.filter((t) => !t.isHome);
      return homes === 3 && rest.length === 1 && rest[0].stepsTaken === 55;
    },
  });
}

/** Insert recorded rows as `move_events` seq 2..N (1 is match_started). */
export async function insertRecordedEvents(
  ds: DataSource,
  matchId: string,
  events: RecordedEvent[],
): Promise<void> {
  let seq = 2;
  for (const event of events) {
    await ds.query(
      `INSERT INTO "move_events"
         ("match_id", "seq_no", "actor_id", "type", "payload", "request_id")
       VALUES ($1, $2, $3, $4, $5::jsonb, NULL)`,
      [matchId, seq, event.actorId, event.type, JSON.stringify(event.payload)],
    );
    seq += 1;
  }
}

/** Steps taken by one token in a snapshot JSON. */
export function snapshotTokenSteps(
  snapshot: Record<string, unknown>,
  seat: number,
  tokenIndex: number,
): number {
  const players = snapshot.players as Array<{
    tokens: Array<{ stepsTaken: number }>;
  }>;
  return players[seat].tokens[tokenIndex].stepsTaken;
}
