import {
  FixedDiceRoller,
  GameState,
  LudoGame,
  Player,
  Token,
} from '../../src/game';
import {
  computeStandings,
  describeMoveTransition,
  describeRollTransition,
  parseTokenId,
  socketEventsForStoredIntent,
  tokenIdOf,
  type SeatView,
} from '../../src/match/match-payloads';

/**
 * Pure payload helpers: token ids, standings, transition
 * descriptions, and the duplicate re-emit mapping (FR-53).
 */
describe('match payloads', () => {
  const seats: SeatView[] = [
    { userId: 'u-red', seat: 0, colour: 'red' },
    { userId: 'u-green', seat: 1, colour: 'green' },
    { userId: 'u-yellow', seat: 2, colour: 'yellow' },
  ];

  describe('token ids', () => {
    it('parses "{seat}:{tokenIndex}" and rejects the rest', () => {
      expect(parseTokenId('0:2')).toEqual({ seat: 0, tokenIndex: 2 });
      expect(parseTokenId('3:3')).toEqual({ seat: 3, tokenIndex: 3 });
      expect(parseTokenId('4:0')).toBeNull();
      expect(parseTokenId('0:4')).toBeNull();
      expect(parseTokenId('0')).toBeNull();
      expect(parseTokenId('red-0')).toBeNull();
      expect(parseTokenId('')).toBeNull();
    });

    it('formats token ids', () => {
      expect(tokenIdOf(1, 3)).toBe('1:3');
    });
  });

  describe('computeStandings', () => {
    function player(
      index: number,
      colour: 'red' | 'green' | 'yellow',
      steps: number[],
    ): Player {
      return new Player({
        index,
        name: colour,
        colour,
        type: 'human',
        tokens: steps.map((s, i) => new Token(index, i, colour, s)),
      });
    }

    it('ranks the winner first, then by tokens home, then steps, then seat', () => {
      const state = new GameState({
        players: [
          player(0, 'red', [56, 56, 56, 56]),
          player(1, 'green', [56, 56, 40, 30]),
          player(2, 'yellow', [56, 56, 20, 10]),
        ],
        currentPlayerIndex: 0,
        rulesetVersion: '1.0.0',
        phase: 'finished',
        winnerIndex: 0,
      });
      const { winnerId, standings } = computeStandings(state, seats);
      expect(winnerId).toBe('u-red');
      expect(standings.map((s) => s.userId)).toEqual([
        'u-red',
        'u-green',
        'u-yellow',
      ]);
      expect(standings.map((s) => s.rank)).toEqual([1, 2, 3]);
      expect(standings.map((s) => s.result)).toEqual(['win', 'loss', 'loss']);
      expect(standings[1].tokensHome).toBe(2);
    });

    it('breaks a tokens-home tie by total steps, then by seat', () => {
      const state = new GameState({
        players: [
          player(0, 'red', [56, 56, 56, 56]),
          player(1, 'green', [56, 10, 10, 10]),
          player(2, 'yellow', [56, 20, 20, 20]),
        ],
        currentPlayerIndex: 0,
        rulesetVersion: '1.0.0',
        phase: 'finished',
        winnerIndex: 0,
      });
      const { standings } = computeStandings(state, seats);
      // Yellow has more total steps than green with equal homes.
      expect(standings.map((s) => s.userId)).toEqual([
        'u-red',
        'u-yellow',
        'u-green',
      ]);
    });

    it('throws without a winner', () => {
      const state = new GameState({
        players: [
          player(0, 'red', [0, 0, 0, 0]),
          player(1, 'green', [0, 0, 0, 0]),
        ],
        currentPlayerIndex: 0,
        rulesetVersion: '1.0.0',
      });
      expect(() => computeStandings(state, seats)).toThrow('no winner');
    });
  });

  describe('transition descriptions', () => {
    function twoPlayerGame(rolls: number[]): LudoGame {
      return LudoGame.newMatch({
        seats: [
          { name: 'red', colour: 'red', type: 'human' },
          { name: 'green', colour: 'green', type: 'human' },
        ],
        diceRoller: new FixedDiceRoller(rolls, { cycle: true }),
      });
    }

    it('a release move lands on the start cell with an extra turn', () => {
      const game = twoPlayerGame([6]);
      const before = game.state;
      const value = game.rollDice();
      expect(value).toBe(6);
      const afterRoll = game.state;
      expect(
        describeRollTransition({ before, after: afterRoll, seats }),
      ).toEqual({ turnChangedPlayerId: null });
      const result = game.applyMove(game.legalMoves()[0]);
      const desc = describeMoveTransition({
        before: afterRoll,
        after: game.state,
        result,
        seats,
      });
      expect(desc.landing).toEqual({ kind: 'track', index: 0 });
      expect(desc.captured).toEqual([]);
      expect(desc.extraTurn).toBe(true);
      expect(desc.winnerId).toBeNull();
      expect(desc.turnChangedPlayerId).toBeNull();
      expect(desc.currentPlayerId).toBe('u-red');
    });

    it('a no-legal-move roll passes the turn', () => {
      const game = twoPlayerGame([2]);
      const before = game.state;
      game.rollDice();
      const { turnChangedPlayerId } = describeRollTransition({
        before,
        after: game.state,
        seats,
      });
      expect(turnChangedPlayerId).toBe('u-green');
    });
  });

  describe('socketEventsForStoredIntent (FR-53 duplicates)', () => {
    it('re-emits a dice roll and its turn change with the original seqs', () => {
      const events = socketEventsForStoredIntent('m1', {
        type: 'dice_rolled',
        seqNo: 5,
        payload: {
          playerId: 'u-red',
          value: 2,
          turnChangedPlayerId: 'u-green',
        },
      });
      expect(events).toEqual([
        {
          event: 'dice:rolled',
          payload: { matchId: 'm1', playerId: 'u-red', value: 2, seq: 5 },
        },
        {
          event: 'turn:changed',
          payload: {
            matchId: 'm1',
            playerId: 'u-green',
            turnEndsAt: null,
            seq: 6,
          },
        },
      ]);
    });

    it('re-emits a winning move and its match end with the original seqs', () => {
      const events = socketEventsForStoredIntent('m1', {
        type: 'token_moved',
        seqNo: 9,
        payload: {
          playerId: 'u-red',
          tokenId: '0:3',
          landing: { kind: 'home', index: -1 },
          captured: [],
          extraTurn: false,
          winnerId: 'u-red',
          currentPlayerId: 'u-red',
          turnChangedPlayerId: null,
          matchEnded: { winnerId: 'u-red', standings: [] },
        },
      });
      expect(events.map((e) => e.event)).toEqual([
        'token:moved',
        'match:ended',
      ]);
      expect(events[0].payload.seq).toBe(9);
      expect(events[1].payload.seq).toBe(10);
      expect(
        (events[0].payload as { turn: { turnEndsAt: unknown } }).turn
          .turnEndsAt,
      ).toBeNull();
    });

    it('returns nothing for a non-intent row', () => {
      expect(
        socketEventsForStoredIntent('m1', {
          type: 'turn_changed',
          seqNo: 6,
          payload: {},
        }),
      ).toEqual([]);
    });
  });
});
