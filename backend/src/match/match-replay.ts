import {
  CryptoDiceRoller,
  FixedDiceRoller,
  LudoGame,
  Move,
  RulesetConfig,
  type DiceRoller,
} from '../game';
import {
  applyForfeitToState,
  parseTokenId,
  skipForfeitedPlayers,
} from './match-payloads';

/**
 * Replay a match from its `move_events` rows (Phase 5, Stage 5;
 * SDD §8.6). The log IS the checkpoint: replaying the rows in
 * `seq_no` order reproduces the live state.
 *
 * How it works: the recorded dice values (in order) seed a
 * FixedDiceRoller, so `rollDice()` returns exactly the values the
 * live match rolled; `token_moved` rows re-apply the recorded
 * token; `turn_changed` / `match_ended` rows are consequences the
 * preceding roll/move already produced, so replay skips them. The
 * `match_started` row carries the seats; player names come from
 * the users table (loaded by the caller — the event payload stores
 * user ids, not display names).
 *
 * Stage 6: a `player_forfeited` row carries the post-forfeit
 * snapshot, so replay restores it wholesale (the forfeit is a
 * service-level transition, not an engine one); after every roll
 * or move, replay applies the same forfeit-skip the live service
 * applies, so a turn never lands on a forfeited player in either
 * copy. A `player_forfeited` row without a snapshot (pre-Stage 6
 * rows — none exist) is applied from its seat instead.
 *
 * The returned game has the caller's live dice roller installed
 * (the replay roller is exhausted by construction) and its
 * `startedAt` pinned to the match row, so a snapshot taken after a
 * replay is identical to one taken live.
 */

/** One seat for replay (names are usernames, for the snapshot). */
export interface ReplaySeat {
  seat: number;
  colour: string;
  name: string;
}

/** The fields replay reads from a `move_events` row. */
export interface ReplayEventRow {
  seqNo: number;
  type: string;
  payload: Record<string, unknown>;
}

export function replayMatchEvents(opts: {
  seats: ReplaySeat[];
  rulesetVersion: string;
  startedAt: Date;
  events: ReplayEventRow[];
  liveDiceRoller: DiceRoller;
}): LudoGame {
  const ordered = [...opts.events].sort((a, b) => a.seqNo - b.seqNo);
  if (ordered.length === 0 || ordered[0].type !== 'match_started') {
    throw new Error('replay: the move log has no match_started event.');
  }
  const ruleset = new RulesetConfig({ version: opts.rulesetVersion });
  const diceValues = ordered
    .filter((e) => e.type === 'dice_rolled')
    .map((e) => (e.payload as { value: unknown }).value);
  for (const value of diceValues) {
    if (
      !Number.isInteger(value) ||
      (value as number) < 1 ||
      (value as number) > 6
    ) {
      throw new Error(
        `replay: recorded dice value ${String(value)} is not in 1..6.`,
      );
    }
  }
  const replayRoller =
    diceValues.length > 0
      ? new FixedDiceRoller(diceValues as number[])
      : new CryptoDiceRoller();
  const seats = [...opts.seats].sort((a, b) => a.seat - b.seat);
  let game = LudoGame.newMatch({
    seats: seats.map((s) => ({
      name: s.name,
      colour: s.colour as 'red' | 'green' | 'yellow' | 'blue',
      type: 'human' as const,
    })),
    ruleset,
    diceRoller: replayRoller,
  });
  /** Seats forfeited so far in the log (Stage 6). */
  const forfeitedSeats = new Set<number>();
  /** Rebuild `game` around `state` without consuming the roller. */
  const rebuild = (state: typeof game.state): void => {
    game = LudoGame.fromState(state, {
      ruleset: game.state.ruleset,
      diceRoller: replayRoller,
    });
  };
  for (const event of ordered) {
    if (event.type === 'match_started') continue;
    if (event.type === 'dice_rolled') {
      const expected = (event.payload as { value: unknown }).value as number;
      const rolled = game.rollDice();
      if (rolled !== expected) {
        throw new Error(
          `replay: dice mismatch at seq ${event.seqNo} ` +
            `(log says ${expected}, engine rolled ${rolled}).`,
        );
      }
      const skipped = skipForfeitedPlayers(game.state, forfeitedSeats);
      if (skipped !== game.state) rebuild(skipped);
      continue;
    }
    if (event.type === 'token_moved') {
      const tokenId = (event.payload as { tokenId: unknown }).tokenId as string;
      const parsed = parseTokenId(tokenId);
      if (!parsed) {
        throw new Error(
          `replay: malformed tokenId "${tokenId}" at seq ${event.seqNo}.`,
        );
      }
      game.applyMove(new Move(parsed.seat, parsed.tokenIndex));
      const skipped = skipForfeitedPlayers(game.state, forfeitedSeats);
      if (skipped !== game.state) rebuild(skipped);
      continue;
    }
    if (event.type === 'player_forfeited') {
      const payload = event.payload as {
        seat?: unknown;
        snapshot?: unknown;
      };
      if (
        payload.snapshot &&
        typeof payload.snapshot === 'object' &&
        payload.snapshot !== null
      ) {
        game = LudoGame.restore(payload.snapshot as Record<string, unknown>, {
          diceRoller: replayRoller,
        });
      } else if (typeof payload.seat === 'number') {
        forfeitedSeats.add(payload.seat);
        rebuild(applyForfeitToState(game.state, payload.seat, forfeitedSeats));
      } else {
        throw new Error(
          `replay: player_forfeited at seq ${event.seqNo} has ` +
            `neither a snapshot nor a seat.`,
        );
      }
      if (typeof payload.seat === 'number') {
        forfeitedSeats.add(payload.seat);
      }
      continue;
    }
    if (event.type === 'turn_changed' || event.type === 'match_ended') {
      // Consequence of the preceding roll/move — already applied.
      continue;
    }
    throw new Error(`replay: unknown move event type "${event.type}".`);
  }
  // Install the live roller (the replay roller is exhausted) and pin
  // startedAt to the match row, so snapshots are stable across loads.
  return LudoGame.fromState(
    game.state.copyWith({ startedAt: opts.startedAt }),
    { ruleset: game.state.ruleset, diceRoller: opts.liveDiceRoller },
  );
}
