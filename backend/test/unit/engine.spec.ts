import {
  ArgumentError,
  Board,
  CryptoDiceRoller,
  FixedDiceRoller,
  FormatException,
  GameState,
  InvalidMatchConfig,
  InvalidRulesetConfig,
  LudoGame,
  Move,
  Player,
  RULESET_DEFAULTS,
  RulesetConfig,
  StateError,
  Token,
  type DiceRoller,
  type TurnPhase,
} from '../../src/game';

/**
 * Authoritative TypeScript engine — unit tests (Stage 4).
 *
 * Every behaviour mirrors the Dart engine; the shared vectors in
 * `rules-vectors.parity.spec.ts` prove cross-language parity, while
 * these tests pin the error taxonomy, the strict snapshot rules and
 * the paths the vectors do not reach (dice distribution, setup
 * errors, malformed snapshots).
 */

const COLOURS = ['red', 'green', 'yellow', 'blue'] as const;

function tokensJson(steps: number[]): Record<string, unknown>[] {
  return steps.map((s) => ({ stepsTaken: s }));
}

function snapshotJson(opts: {
  tokenSteps?: number[][];
  types?: ('human' | 'ai')[];
  difficulties?: (string | undefined)[];
  current?: number;
  phase?: TurnPhase;
  lastRoll?: number;
  sixes?: number;
  winner?: number | null;
  moveCount?: number;
  ruleset?: Record<string, unknown>;
  startedAt?: string | null;
  omitStartedAt?: boolean;
  extraKeys?: Record<string, unknown>;
}): Record<string, unknown> {
  const steps = opts.tokenSteps ?? [
    [0, 0, 0, 0],
    [0, 0, 0, 0],
  ];
  const players = steps.map((tokens, i) => {
    const p: Record<string, unknown> = {
      name: `Player ${i + 1}`,
      colour: COLOURS[i],
      type: opts.types?.[i] ?? 'human',
      tokens: tokensJson(tokens),
    };
    const difficulty = opts.difficulties?.[i];
    if (difficulty !== undefined) p.difficulty = difficulty;
    return p;
  });
  const json: Record<string, unknown> = {
    formatVersion: 1,
    rulesetVersion: '1.0.0',
    ruleset: opts.ruleset ?? { ...RULESET_DEFAULTS },
    startedAt: '2026-11-22T10:00:00.000Z',
    currentPlayerIndex: opts.current ?? 0,
    phase: opts.phase ?? 'awaitingRoll',
    lastRoll: opts.lastRoll ?? 0,
    consecutiveSixes: opts.sixes ?? 0,
    winnerIndex: opts.winner ?? null,
    moveCount: opts.moveCount ?? 0,
    lastRollWasThirdSix: false,
    lastRollHadNoLegalMove: false,
    players,
    ...(opts.extraKeys ?? {}),
  };
  if (opts.startedAt !== undefined) json.startedAt = opts.startedAt;
  if (opts.omitStartedAt) delete json.startedAt;
  return json;
}

function gameFromSteps(
  tokenSteps: number[][],
  opts: {
    dice?: number[];
    ruleset?: RulesetConfig;
    phase?: TurnPhase;
    lastRoll?: number;
    sixes?: number;
    current?: number;
  } = {},
): LudoGame {
  return LudoGame.fromState(
    GameState.fromJson(
      snapshotJson({
        tokenSteps,
        phase: opts.phase,
        lastRoll: opts.lastRoll,
        sixes: opts.sixes,
        current: opts.current,
      }),
    ),
    {
      ruleset: opts.ruleset ?? new RulesetConfig(),
      diceRoller: new FixedDiceRoller(opts.dice ?? [1]),
    },
  );
}

function newMatch(dice: number[], ruleset?: RulesetConfig): LudoGame {
  return LudoGame.newMatch({
    seats: [
      { name: 'Red', colour: 'red' },
      { name: 'Green', colour: 'green' },
    ],
    ruleset,
    diceRoller: new FixedDiceRoller(dice),
  });
}

describe('CryptoDiceRoller', () => {
  it('rolls only 1..6, covers every face, and is roughly uniform', () => {
    const roller = new CryptoDiceRoller();
    const counts = [0, 0, 0, 0, 0, 0];
    const n = 6000;
    for (let i = 0; i < n; i++) {
      const value = roller.roll();
      expect(value).toBeGreaterThanOrEqual(1);
      expect(value).toBeLessThanOrEqual(6);
      counts[value - 1] += 1;
    }
    // Mean 1000 per face, sd ≈ 29; ±200 is ~7 sd — a failure here
    // means the generator is broken, not unlucky.
    for (const count of counts) {
      expect(count).toBeGreaterThan(800);
      expect(count).toBeLessThan(1200);
    }
  });
});

describe('FixedDiceRoller', () => {
  it('replays its sequence in order', () => {
    const roller = new FixedDiceRoller([6, 1, 3]);
    expect([roller.roll(), roller.roll(), roller.roll()]).toEqual([6, 1, 3]);
  });

  it('throws StateError once exhausted', () => {
    const roller = new FixedDiceRoller([2]);
    expect(roller.roll()).toBe(2);
    expect(() => roller.roll()).toThrow(StateError);
  });

  it('cycles when asked to', () => {
    const roller = new FixedDiceRoller([4, 5], { cycle: true });
    expect([roller.roll(), roller.roll(), roller.roll()]).toEqual([4, 5, 4]);
  });

  it('rejects an empty sequence and out-of-range values', () => {
    expect(() => new FixedDiceRoller([])).toThrow(ArgumentError);
    expect(() => new FixedDiceRoller([0])).toThrow(ArgumentError);
    expect(() => new FixedDiceRoller([7])).toThrow(ArgumentError);
    expect(() => new FixedDiceRoller([3.5])).toThrow(ArgumentError);
  });
});

describe('Board', () => {
  const board = new Board();

  it('maps steps to cells: yard, start, track, home path, home', () => {
    expect(board.cellAt('red', 0).kind).toBe('yard');
    expect(board.cellAt('red', 1)).toEqual(
      expect.objectContaining({ kind: 'track', index: 0 }),
    );
    expect(board.cellAt('red', 51)).toEqual(
      expect.objectContaining({ kind: 'track', index: 50 }),
    );
    expect(board.cellAt('red', 52)).toEqual(
      expect.objectContaining({ kind: 'homePath', index: 0 }),
    );
    expect(board.cellAt('red', 55)).toEqual(
      expect.objectContaining({ kind: 'homePath', index: 3 }),
    );
    expect(board.cellAt('red', 56).kind).toBe('home');
    // Green starts 13 cells on: step 1 is track 13, step 51 is 11.
    expect(board.cellAt('green', 1).index).toBe(13);
    expect(board.cellAt('green', 51).index).toBe(11);
    // Blue step 14 wraps to track 0.
    expect(board.cellAt('blue', 14).index).toBe(0);
  });

  it('rejects steps beyond home', () => {
    expect(() => board.cellAt('red', 57)).toThrow(ArgumentError);
  });

  it('knows start cells, star cells and the 8 safe cells', () => {
    expect(board.startCell('red')).toBe(0);
    expect(board.startCell('green')).toBe(13);
    expect(board.startCell('yellow')).toBe(26);
    expect(board.startCell('blue')).toBe(39);
    for (const cell of [0, 8, 13, 21, 26, 34, 39, 47]) {
      expect(board.isSafeTrackCell(cell)).toBe(true);
    }
    for (const cell of [1, 7, 9, 20, 22, 33, 40, 51]) {
      expect(board.isSafeTrackCell(cell)).toBe(false);
    }
    expect(board.isSafe(board.cellAt('red', 52))).toBe(true);
    expect(board.isSafe(board.cellAt('red', 56))).toBe(true);
  });
});

describe('Token.canMove', () => {
  const yard = new Token(0, 0, 'red', 0);
  const mid = new Token(0, 0, 'red', 10);
  const nearHome = new Token(0, 0, 'red', 54);
  const home = new Token(0, 0, 'red', 56);

  it('releases from the yard only on a release roll', () => {
    expect(
      yard.canMove(6, { releaseRolls: new Set([6]), exactFinish: true }),
    ).toBe(true);
    expect(
      yard.canMove(3, { releaseRolls: new Set([6]), exactFinish: true }),
    ).toBe(false);
    expect(
      yard.canMove(1, { releaseRolls: new Set([1]), exactFinish: true }),
    ).toBe(true);
  });

  it('applies exact finish on the track, and the non-exact variant lands home', () => {
    expect(
      mid.canMove(3, { releaseRolls: new Set([6]), exactFinish: true }),
    ).toBe(true);
    expect(
      nearHome.canMove(3, { releaseRolls: new Set([6]), exactFinish: true }),
    ).toBe(false);
    expect(
      nearHome.canMove(2, { releaseRolls: new Set([6]), exactFinish: true }),
    ).toBe(true);
    expect(
      nearHome.canMove(3, { releaseRolls: new Set([6]), exactFinish: false }),
    ).toBe(true);
    expect(
      home.canMove(3, { releaseRolls: new Set([6]), exactFinish: false }),
    ).toBe(false);
    expect(
      home.canMove(3, { releaseRolls: new Set([6]), exactFinish: true }),
    ).toBe(false);
  });
});

describe('RulesetConfig', () => {
  it('defaults match SDD §6.2', () => {
    expect(new RulesetConfig().toJson()).toEqual(RULESET_DEFAULTS);
    expect(new RulesetConfig().releaseRolls).toEqual(new Set([6]));
    expect(
      new RulesetConfig({ releaseOnSix: false, releaseOnOne: true })
        .releaseRolls,
    ).toEqual(new Set([1]));
  });

  it('validate() rejects incoherent configs', () => {
    expect(() =>
      new RulesetConfig({
        releaseOnSix: false,
        releaseOnOne: false,
      }).validate(),
    ).toThrow(InvalidRulesetConfig);
    expect(() =>
      new RulesetConfig({ maxConsecutiveSixes: -1 }).validate(),
    ).toThrow(InvalidRulesetConfig);
    expect(() => new RulesetConfig({ version: '' }).validate()).toThrow(
      InvalidRulesetConfig,
    );
    expect(() =>
      new RulesetConfig({ maxConsecutiveSixes: 0 }).validate(),
    ).not.toThrow();
  });

  it('fromJson is strict and round-trips', () => {
    const config = new RulesetConfig({ releaseOnOne: true });
    expect(
      RulesetConfig.fromJson(
        config.toJson() as unknown as Record<string, unknown>,
      ).equals(config),
    ).toBe(true);
    const missing = { ...RULESET_DEFAULTS } as Record<string, unknown>;
    delete missing.exactFinish;
    expect(() => RulesetConfig.fromJson(missing)).toThrow(FormatException);
    expect(() =>
      RulesetConfig.fromJson({
        ...RULESET_DEFAULTS,
        releaseOnSix: false,
        releaseOnOne: false,
      }),
    ).toThrow(FormatException);
    expect(() =>
      RulesetConfig.fromJson({ ...RULESET_DEFAULTS, maxConsecutiveSixes: '3' }),
    ).toThrow(FormatException);
  });
});

describe('Player', () => {
  it('needs exactly 4 tokens', () => {
    expect(
      () =>
        new Player({
          index: 0,
          name: 'Red',
          colour: 'red',
          type: 'human',
          tokens: [new Token(0, 0, 'red')],
        }),
    ).toThrow(ArgumentError);
  });

  it('reports tokens home and the BR-11 win', () => {
    const player = new Player({
      index: 0,
      name: 'Red',
      colour: 'red',
      type: 'human',
      tokens: [56, 56, 56, 53].map((s, i) => new Token(0, i, 'red', s)),
    });
    expect(player.tokensHome).toBe(3);
    expect(player.hasWon).toBe(false);
    expect(
      player.copyWith({
        tokens: [56, 56, 56, 56].map((s, i) => new Token(0, i, 'red', s)),
      }).hasWon,
    ).toBe(true);
  });

  it('fromJson keeps AI difficulty, defaults it to easy, and rejects unknowns', () => {
    const ai = Player.fromJson(1, {
      name: 'Green',
      colour: 'green',
      type: 'ai',
      difficulty: 'hard',
      tokens: tokensJson([0, 0, 0, 0]),
    });
    expect(ai.isAi).toBe(true);
    expect(ai.difficulty).toBe('hard');
    expect(ai.toJson().difficulty).toBe('hard');
    const defaulted = Player.fromJson(1, {
      name: 'Green',
      colour: 'green',
      type: 'ai',
      tokens: tokensJson([0, 0, 0, 0]),
    });
    expect(defaulted.difficulty).toBe('easy');
    expect(() =>
      Player.fromJson(1, {
        name: 'Green',
        colour: 'green',
        type: 'ai',
        difficulty: 'impossible',
        tokens: tokensJson([0, 0, 0, 0]),
      }),
    ).toThrow(FormatException);
    expect(() =>
      Player.fromJson(1, {
        name: 'Green',
        colour: 'purple',
        type: 'human',
        tokens: tokensJson([0, 0, 0, 0]),
      }),
    ).toThrow(FormatException);
    expect(() =>
      Player.fromJson(1, {
        name: 'Green',
        colour: 'green',
        type: 'human',
        tokens: tokensJson([0, 0, 0]),
      }),
    ).toThrow(FormatException);
    const human = Player.fromJson(0, {
      name: 'Red',
      colour: 'red',
      type: 'human',
      tokens: tokensJson([0, 0, 0, 0]),
    });
    expect('difficulty' in human.toJson()).toBe(false);
  });
});

describe('GameState.fromJson', () => {
  it('round-trips a valid snapshot', () => {
    const json = snapshotJson({
      tokenSteps: [
        [20, 0, 0, 0],
        [10, 0, 0, 0],
      ],
    });
    const state = GameState.fromJson(json);
    expect(state.toJson()).toEqual(json);
    expect(state.currentPlayer.name).toBe('Player 1');
  });

  it('accepts a zoned startedAt and ignores unknown top-level keys', () => {
    expect(() =>
      GameState.fromJson(
        snapshotJson({
          startedAt: '2026-11-22T10:00:00Z',
          extraKeys: { futureField: true },
        }),
      ),
    ).not.toThrow();
  });

  it('accepts a naive startedAt (legacy / Dart offline snapshots)', () => {
    const state = GameState.fromJson(
      snapshotJson({ startedAt: '2026-11-22T10:00:00' }),
    );
    expect(state.startedAt).toBeInstanceOf(Date);
    expect(state.startedAt!.getTime()).toBe(
      new Date('2026-11-22T10:00:00').getTime(),
    );
  });

  it('toJson emits startedAt as a Z-suffixed UTC instant', () => {
    const state = GameState.fromJson(
      snapshotJson({ startedAt: '2026-11-22T10:00:00.123+02:00' }),
    );
    const emitted = state.toJson().startedAt as string;
    expect(emitted).toBe('2026-11-22T08:00:00.123Z');
    expect(emitted.endsWith('Z')).toBe(true);
    // The same instant re-parses, so a snapshot written by this
    // writer round-trips through fromJson unchanged.
    expect(
      GameState.fromJson(snapshotJson({ startedAt: emitted })).startedAt,
    ).toEqual(state.startedAt);
  });

  it.each([
    ['formatVersion 2', { extraKeys: { formatVersion: 2 } }],
    ['missing formatVersion', { extraKeys: { formatVersion: undefined } }],
    ['rulesetVersion mismatch', { extraKeys: { rulesetVersion: '2.0.0' } }],
    [
      'embedded ruleset version mismatch',
      { ruleset: { ...RULESET_DEFAULTS, version: '2.0.0' } },
    ],
    ['one player', { tokenSteps: [[0, 0, 0, 0]] }],
    [
      'five players',
      {
        tokenSteps: [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
        ],
      },
    ],
    ['all AI players', { types: ['ai', 'ai'] as ('human' | 'ai')[] }],
    ['currentPlayerIndex out of range', { current: 2 }],
    ['lastRoll 7', { lastRoll: 7 }],
    ['consecutiveSixes at the limit', { sixes: 3 }],
    ['negative consecutiveSixes', { sixes: -1 }],
    ['negative moveCount', { moveCount: -1 }],
    ['unknown phase', { phase: 'moving' as TurnPhase }],
    ['winner while unfinished', { winner: 0 }],
    ['finished without a winner', { phase: 'finished' as TurnPhase }],
    [
      'finished with an out-of-range winner',
      { phase: 'finished' as TurnPhase, winner: 5 },
    ],
    ['missing startedAt', { omitStartedAt: true }],
    ['null startedAt', { startedAt: null }],
    ['date-only startedAt', { startedAt: '2026-11-22' }],
    ['month 13 startedAt', { startedAt: '2026-13-22T10:00:00' }],
    ['Feb 29 in a non-leap year', { startedAt: '2026-02-29T10:00:00' }],
    ['leap second', { startedAt: '2026-11-22T10:00:60' }],
  ])('rejects %s with FormatException', (_label, overrides) => {
    expect(() => GameState.fromJson(snapshotJson(overrides as never))).toThrow(
      FormatException,
    );
  });

  it('rejects duplicate colours', () => {
    const json = snapshotJson({});
    (
      (json.players as Record<string, unknown>[])[1] as Record<string, unknown>
    ).colour = 'red';
    expect(() => GameState.fromJson(json)).toThrow(FormatException);
  });

  it('allows any consecutiveSixes when the limit is disabled (D-29)', () => {
    expect(() =>
      GameState.fromJson(
        snapshotJson({
          sixes: 9,
          ruleset: { ...RULESET_DEFAULTS, maxConsecutiveSixes: 0 },
        }),
      ),
    ).not.toThrow();
  });

  it('initial() stamps startedAt and starts awaitingRoll', () => {
    const state = GameState.initial({
      players: [
        new Player({ index: 0, name: 'Red', colour: 'red', type: 'human' }),
        new Player({ index: 1, name: 'Green', colour: 'green', type: 'human' }),
      ],
    });
    expect(state.startedAt).toBeInstanceOf(Date);
    expect(state.currentPlayerIndex).toBe(0);
    expect(state.phase).toBe('awaitingRoll');
  });
});

describe('LudoGame.newMatch / fromState setup', () => {
  it('rejects bad seat counts, duplicate colours and all-AI matches', () => {
    const oneSeat = [{ name: 'Red', colour: 'red' as const }];
    expect(() => LudoGame.newMatch({ seats: oneSeat })).toThrow(
      InvalidMatchConfig,
    );
    expect(() =>
      LudoGame.newMatch({
        seats: [
          { name: 'A', colour: 'red' },
          { name: 'B', colour: 'green' },
          { name: 'C', colour: 'yellow' },
          { name: 'D', colour: 'blue' },
          { name: 'E', colour: 'red' },
        ],
      }),
    ).toThrow(InvalidMatchConfig);
    expect(() =>
      LudoGame.newMatch({
        seats: [
          { name: 'A', colour: 'red' },
          { name: 'B', colour: 'red' },
        ],
      }),
    ).toThrow(InvalidMatchConfig);
    expect(() =>
      LudoGame.newMatch({
        seats: [
          { name: 'A', colour: 'red', type: 'ai' },
          { name: 'B', colour: 'green', type: 'ai' },
        ],
      }),
    ).toThrow(InvalidMatchConfig);
  });

  it('rejects an invalid ruleset and a ruleset-version mismatch', () => {
    expect(() =>
      LudoGame.newMatch({
        seats: [
          { name: 'A', colour: 'red' },
          { name: 'B', colour: 'green' },
        ],
        ruleset: new RulesetConfig({
          releaseOnSix: false,
          releaseOnOne: false,
        }),
      }),
    ).toThrow(InvalidRulesetConfig);
    const state = GameState.fromJson(snapshotJson({}));
    expect(() =>
      LudoGame.fromState(state, {
        ruleset: new RulesetConfig({ version: '2.0.0' }),
      }),
    ).toThrow(ArgumentError);
  });

  it('builds AI seats with the requested difficulty', () => {
    const game = LudoGame.newMatch({
      seats: [
        { name: 'Red', colour: 'red' },
        { name: 'Bot', colour: 'green', type: 'ai', difficulty: 'hard' },
      ],
    });
    expect(game.players[1].isAi).toBe(true);
    expect(game.players[1].difficulty).toBe('hard');
  });
});

describe('LudoGame.rollDice', () => {
  it('a non-six with no legal move passes the turn (BR-13)', () => {
    const game = newMatch([3]);
    expect(game.rollDice()).toBe(3);
    expect(game.state.phase).toBe('awaitingRoll');
    expect(game.currentPlayerIndex).toBe(1);
    expect(game.state.lastRoll).toBe(3);
    expect(game.state.lastRollHadNoLegalMove).toBe(true);
  });

  it('a six with no legal move keeps the turn for an extra roll', () => {
    const game = gameFromSteps(
      [
        [54, 56, 56, 56],
        [0, 0, 0, 0],
      ],
      {
        dice: [6],
      },
    );
    expect(game.rollDice()).toBe(6);
    expect(game.state.phase).toBe('awaitingRoll');
    expect(game.currentPlayerIndex).toBe(0);
    expect(game.state.consecutiveSixes).toBe(1);
    expect(game.state.lastRollHadNoLegalMove).toBe(true);
  });

  it('a six with a legal move waits for the move', () => {
    const game = newMatch([6]);
    expect(game.rollDice()).toBe(6);
    expect(game.state.phase).toBe('awaitingMove');
    expect(game.legalMoves().map((m) => m.tokenIndex)).toEqual([0, 1, 2, 3]);
  });

  it('throws StateError on a second roll while a move is pending', () => {
    const game = newMatch([6]);
    game.rollDice();
    expect(() => game.rollDice()).toThrow(StateError);
  });

  it('a third consecutive six is shown but not played (BR-07)', () => {
    const game = gameFromSteps(
      [
        [10, 0, 0, 0],
        [0, 0, 0, 0],
      ],
      {
        dice: [6],
        sixes: 2,
      },
    );
    expect(game.rollDice()).toBe(6);
    expect(game.state.phase).toBe('awaitingRoll');
    expect(game.currentPlayerIndex).toBe(1);
    expect(game.state.lastRoll).toBe(6);
    expect(game.state.lastRollWasThirdSix).toBe(true);
    expect(game.state.consecutiveSixes).toBe(0);
  });

  it('throws StateError when the dice roller returns an invalid value', () => {
    const bad: DiceRoller = { roll: () => 7 };
    const game = LudoGame.newMatch({
      seats: [
        { name: 'Red', colour: 'red' },
        { name: 'Green', colour: 'green' },
      ],
      diceRoller: bad,
    });
    expect(() => game.rollDice()).toThrow(StateError);
  });

  it('throws StateError when the fixed sequence is exhausted', () => {
    const game = newMatch([3]);
    game.rollDice(); // 3, no legal move, turn passes to green.
    expect(() => game.rollDice()).toThrow(StateError);
  });
});

describe('LudoGame.legalMoves', () => {
  it('is empty outside awaitingMove', () => {
    const game = newMatch([6]);
    expect(game.legalMoves()).toEqual([]);
    game.rollDice();
    expect(game.legalMoves()).toHaveLength(4);
  });

  it('legalMovesFor is a pure function of state, roll and ruleset', () => {
    const game = gameFromSteps([
      [10, 0, 0, 0],
      [0, 0, 0, 0],
    ]);
    const moves = LudoGame.legalMovesFor(
      game.state,
      3,
      new RulesetConfig(),
      new Board(),
    );
    expect(moves.map((m) => [m.playerIndex, m.tokenIndex])).toEqual([[0, 0]]);
  });
});

describe('LudoGame.applyMove', () => {
  it('releases to step 1, spending the roll (BR-04, D-20)', () => {
    const game = newMatch([6]);
    game.rollDice();
    const result = game.applyMove(new Move(0, 2));
    expect(result.fromSteps).toBe(0);
    expect(result.toSteps).toBe(1);
    expect(result.extraTurn).toBe(true);
    expect(game.state.phase).toBe('awaitingRoll');
    expect(game.currentPlayerIndex).toBe(0);
  });

  it('advances by exactly the roll (BR-05)', () => {
    const game = gameFromSteps(
      [
        [10, 0, 0, 0],
        [0, 0, 0, 0],
      ],
      { dice: [3] },
    );
    game.rollDice();
    const result = game.applyMove(new Move(0, 0));
    expect(result.fromSteps).toBe(10);
    expect(result.toSteps).toBe(13);
    expect(result.extraTurn).toBe(false);
    expect(game.currentPlayerIndex).toBe(1);
  });

  it('captures on a plain track cell and grants an extra turn (BR-08, BR-06)', () => {
    const game = gameFromSteps(
      [
        [20, 0, 0, 0],
        [10, 0, 0, 0],
      ],
      { dice: [3] },
    );
    game.rollDice();
    const result = game.applyMove(new Move(0, 0));
    expect(result.toSteps).toBe(23);
    expect(result.captured.map((t) => [t.playerIndex, t.tokenIndex])).toEqual([
      [1, 0],
    ]);
    expect(result.extraTurn).toBe(true);
    expect(game.state.players[1].tokens[0].stepsTaken).toBe(0);
  });

  it('captures several tokens stacked on the landing cell', () => {
    const game = gameFromSteps(
      [
        [20, 0, 0, 0],
        [10, 10, 0, 0],
      ],
      { dice: [3] },
    );
    game.rollDice();
    const result = game.applyMove(new Move(0, 0));
    expect(result.captured).toHaveLength(2);
    expect(game.state.players[1].tokens[0].stepsTaken).toBe(0);
    expect(game.state.players[1].tokens[1].stepsTaken).toBe(0);
  });

  it('never captures on a safe start cell (BR-09)', () => {
    // Red 11 + 3 lands on track 13, green's start cell.
    const game = gameFromSteps(
      [
        [11, 0, 0, 0],
        [1, 0, 0, 0],
      ],
      { dice: [3] },
    );
    game.rollDice();
    const result = game.applyMove(new Move(0, 0));
    expect(result.captured).toEqual([]);
    expect(result.extraTurn).toBe(false);
    expect(game.state.players[1].tokens[0].stepsTaken).toBe(1);
  });

  it('never captures on a safe star cell (BR-09)', () => {
    // Red 5 + 4 lands on track 8 (star); blue 22 sits on track 8.
    const game = gameFromSteps(
      [
        [5, 0, 0, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
        [22, 0, 0, 0],
      ],
      {
        dice: [4],
      },
    );
    game.rollDice();
    const result = game.applyMove(new Move(0, 0));
    expect(result.captured).toEqual([]);
    expect(game.state.players[3].tokens[0].stepsTaken).toBe(22);
  });

  it('passing over a token never captures (BR-05, BR-08)', () => {
    // Red 18 -> 23 passes track 20, where green's token (steps 8) sits.
    const game = gameFromSteps(
      [
        [18, 0, 0, 0],
        [8, 0, 0, 0],
      ],
      { dice: [5] },
    );
    game.rollDice();
    const result = game.applyMove(new Move(0, 0));
    expect(result.captured).toEqual([]);
    expect(game.state.players[1].tokens[0].stepsTaken).toBe(8);
  });

  it('entering the home path is reported (BR-10)', () => {
    const game = gameFromSteps(
      [
        [50, 0, 0, 0],
        [0, 0, 0, 0],
      ],
      { dice: [3] },
    );
    game.rollDice();
    const result = game.applyMove(new Move(0, 0));
    expect(result.toSteps).toBe(53);
    expect(result.enteredHomePath).toBe(true);
    expect(result.reachedHome).toBe(false);
  });

  it('reaching home grants an extra turn (BR-06, BR-10)', () => {
    const game = gameFromSteps(
      [
        [53, 0, 0, 0],
        [0, 0, 0, 0],
      ],
      { dice: [3] },
    );
    game.rollDice();
    const result = game.applyMove(new Move(0, 0));
    expect(result.reachedHome).toBe(true);
    expect(result.extraTurn).toBe(true);
    expect(game.currentPlayerIndex).toBe(0);
  });

  it('an overshooting move is illegal under exact finish and changes nothing', () => {
    const game = gameFromSteps(
      [
        [54, 10, 0, 0],
        [0, 0, 0, 0],
      ],
      { dice: [3] },
    );
    game.rollDice();
    expect(game.legalMoves().map((m) => m.tokenIndex)).toEqual([1]);
    const before = game.snapshot();
    expect(() => game.applyMove(new Move(0, 0))).toThrow(ArgumentError);
    expect(game.snapshot()).toEqual(before);
  });

  it('an overshoot lands home when exact finish is off', () => {
    const game = gameFromSteps(
      [
        [54, 0, 0, 0],
        [0, 0, 0, 0],
      ],
      {
        dice: [3],
        ruleset: new RulesetConfig({ exactFinish: false }),
      },
    );
    game.rollDice();
    const result = game.applyMove(new Move(0, 0));
    expect(result.toSteps).toBe(56);
    expect(result.reachedHome).toBe(true);
  });

  it('the first player with four tokens home wins (BR-11)', () => {
    const game = gameFromSteps(
      [
        [56, 56, 56, 53],
        [0, 0, 0, 0],
      ],
      {
        dice: [3],
      },
    );
    game.rollDice();
    const result = game.applyMove(new Move(0, 3));
    expect(result.isWinningMove).toBe(true);
    expect(result.winnerIndex).toBe(0);
    expect(result.extraTurn).toBe(false);
    expect(game.isFinished).toBe(true);
    expect(game.state.phase).toBe('finished');
    expect(game.winnerIndex).toBe(0);
    expect(game.winner?.name).toBe('Player 1');
    expect(() => game.rollDice()).toThrow(StateError);
    expect(() => game.applyMove(new Move(0, 0))).toThrow(StateError);
    expect(() => game.nextTurn()).toThrow(StateError);
  });

  it('throws StateError before any roll, ArgumentError for the wrong player, and ArgumentError for an illegal token', () => {
    const game = gameFromSteps(
      [
        [10, 0, 0, 0],
        [0, 0, 0, 0],
      ],
      { dice: [3] },
    );
    const before = game.snapshot();
    expect(() => game.applyMove(new Move(0, 0))).toThrow(StateError);
    expect(game.snapshot()).toEqual(before);
    game.rollDice();
    expect(() => game.applyMove(new Move(1, 0))).toThrow(ArgumentError);
    expect(() => game.applyMove(new Move(0, 5))).toThrow(ArgumentError);
    expect(game.snapshot()).toEqual({
      ...before,
      phase: 'awaitingMove',
      lastRoll: 3,
    });
  });
});

describe('LudoGame.nextTurn', () => {
  it('passes to the next player and clears the six count', () => {
    const game = newMatch([6, 1]);
    game.rollDice();
    game.applyMove(new Move(0, 0)); // Six: extra turn, sixes stays 1.
    expect(game.state.consecutiveSixes).toBe(1);
    game.nextTurn();
    expect(game.currentPlayerIndex).toBe(1);
    expect(game.state.phase).toBe('awaitingRoll');
    expect(game.state.consecutiveSixes).toBe(0);
  });

  it('throws StateError while a move is pending', () => {
    const game = newMatch([6]);
    game.rollDice();
    expect(() => game.nextTurn()).toThrow(StateError);
  });
});

describe('LudoGame snapshot / restore', () => {
  it('round-trips a mid-match snapshot and play continues from it', () => {
    const game = newMatch([6]);
    game.rollDice();
    game.applyMove(new Move(0, 0));
    const snapshot = game.snapshot();
    const restored = LudoGame.restore(snapshot, {
      diceRoller: new FixedDiceRoller([3]),
    });
    expect(restored.snapshot()).toEqual(snapshot);
    expect(restored.state.players[0].tokens[0].stepsTaken).toBe(1);
    expect(restored.rollDice()).toBe(3);
    expect(restored.state.phase).toBe('awaitingMove');
  });

  it('rejects a malformed snapshot and a ruleset-version mismatch on restore', () => {
    expect(() => LudoGame.restore({ formatVersion: 2 })).toThrow(
      FormatException,
    );
    const game = newMatch([6]);
    expect(() =>
      LudoGame.restore(game.snapshot(), {
        ruleset: new RulesetConfig({ version: '2.0.0' }),
      }),
    ).toThrow(ArgumentError);
  });
});
