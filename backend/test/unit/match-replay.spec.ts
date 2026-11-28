import { CryptoDiceRoller, FixedDiceRoller, LudoGame } from '../../src/game';
import {
  replayMatchEvents,
  type ReplayEventRow,
} from '../../src/match/match-replay';

/**
 * Replay from move_events (SDD §8.6) — pure unit tests, no DB.
 * The log IS the checkpoint: replaying its rows reproduces the
 * live state, including turn passes (third six, no legal move) and
 * the refusal of a log that could not have happened.
 */
describe('replayMatchEvents', () => {
  const seats = [
    { seat: 0, colour: 'red', name: 'red-player' },
    { seat: 1, colour: 'green', name: 'green-player' },
  ];
  const startedAt = new Date('2026-11-28T00:00:00.000Z');

  function dice(seqNo: number, value: number): ReplayEventRow {
    return {
      seqNo,
      type: 'dice_rolled',
      payload: { playerId: 'p0', value },
    };
  }

  function move(seqNo: number, tokenId: string): ReplayEventRow {
    return { seqNo, type: 'token_moved', payload: { tokenId } };
  }

  function turn(seqNo: number): ReplayEventRow {
    return { seqNo, type: 'turn_changed', payload: {} };
  }

  const started: ReplayEventRow = {
    seqNo: 1,
    type: 'match_started',
    payload: {},
  };

  function replay(events: ReplayEventRow[]): LudoGame {
    return replayMatchEvents({
      seats,
      rulesetVersion: '1.0.0',
      startedAt,
      events,
      liveDiceRoller: new CryptoDiceRoller(),
    });
  }

  it('replays a release: token on its start cell, extra roll pending', () => {
    const game = replay([started, dice(2, 6), move(3, '0:0')]);
    expect(game.state.players[0].tokens[0].stepsTaken).toBe(1);
    // A six grants an extra turn (BR-06), so the phase is
    // awaitingRoll for the same player — not awaitingMove.
    expect(game.state.phase).toBe('awaitingRoll');
    expect(game.state.currentPlayerIndex).toBe(0);
    expect(game.state.startedAt).toEqual(startedAt);
  });

  it('replays a third six as a turn pass (no move is applied)', () => {
    const game = replay([
      started,
      dice(2, 6),
      move(3, '0:0'),
      dice(4, 6),
      move(5, '0:0'),
      dice(6, 6),
      turn(7),
    ]);
    expect(game.state.players[0].tokens[0].stepsTaken).toBe(7);
    expect(game.state.currentPlayerIndex).toBe(1);
    expect(game.state.phase).toBe('awaitingRoll');
  });

  it('replays a no-legal-move roll as a turn pass', () => {
    const game = replay([started, dice(2, 2), turn(3)]);
    expect(game.state.currentPlayerIndex).toBe(1);
    expect(game.state.phase).toBe('awaitingRoll');
    expect(game.state.lastRollHadNoLegalMove).toBe(true);
  });

  it('reproduces the live snapshot exactly (same startedAt)', () => {
    const live = LudoGame.newMatch({
      seats: seats.map((s) => ({
        name: s.name,
        colour: s.colour as 'red' | 'green',
        type: 'human' as const,
      })),
      diceRoller: new FixedDiceRoller([6, 6]),
    });
    live.rollDice();
    live.applyMove(live.legalMoves()[0]);
    const liveStartedAt = live.state.startedAt!;
    const replayed = replayMatchEvents({
      seats,
      rulesetVersion: '1.0.0',
      startedAt: liveStartedAt,
      events: [started, dice(2, 6), move(3, '0:0')],
      liveDiceRoller: new CryptoDiceRoller(),
    });
    expect(replayed.snapshot()).toEqual(live.snapshot());
  });

  it('rejects a log with no match_started event', () => {
    expect(() => replay([dice(2, 6)])).toThrow('no match_started event');
  });

  it('rejects a log whose move could not have happened', () => {
    // Roll 2 with every token in the yard: no token may move, so a
    // token_moved row here is a corrupt log, not a legal game.
    expect(() => replay([started, dice(2, 2), move(3, '0:0')])).toThrow();
  });

  it('rejects an unknown event type', () => {
    expect(() =>
      replay([
        started,
        { seqNo: 2, type: 'dice_rolled_twice', payload: { value: 6 } },
      ]),
    ).toThrow('unknown move event type');
  });

  it('rejects a recorded dice value outside 1..6', () => {
    expect(() => replay([started, dice(2, 9)])).toThrow('not in 1..6');
  });
});
