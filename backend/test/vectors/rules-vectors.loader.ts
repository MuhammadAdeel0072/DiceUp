import * as fs from 'node:fs';
import * as path from 'node:path';

/**
 * Rule-vector loader — NFR-39 (Stage 4: full case shape).
 * Reads the ONE copy of the vectors file at
 * `diceup_app/test/vectors/rules.json` (never copied) and validates
 * its schema strictly, mirroring the Dart runner
 * (`diceup_app/test/vectors/rules_vectors_test.dart`): unknown
 * fields, unknown cases/ops, missing keys and wrong types all fail
 * loudly instead of being silently ignored.
 *
 * CORRECTION to the plan (§2.1.2/§10.2, recorded for Stage 5): the
 * plan says the loader "asserts the embedded ruleset equals the Dart
 * RulesetConfig defaults". That is NOT true of the real file: 29/39
 * cases embed the defaults, but 10 are deliberate variants
 * (release-on-one-variant, extra-turn-on-six-disabled,
 * extra-turn-on-capture-disabled, extra-turn-on-home-disabled,
 * third-six-limit-off, exact-finish-off-overshoot-lands-home,
 * release-on-one-only, max-consecutive-sixes-two,
 * max-consecutive-sixes-five,
 * combined-variant-release-one-exact-off). The vectors file is
 * authoritative, so the loader instead validates every embedded
 * ruleset for *coherence* (the Dart RulesetConfig.validate() rules:
 * at least one release roll, maxConsecutiveSixes >= 0, version
 * non-empty and == rulesetVersion) and asserts the canonical default
 * case matches the Dart defaults exactly.
 *
 * Structural validation of the starting snapshot itself (strict
 * GameState deserialization) lives in the replay harness, which
 * builds the game through `GameState.fromJson` — the same strict
 * path the Dart runner uses.
 */

export interface RulesetConfig {
  releaseOnSix: boolean;
  releaseOnOne: boolean;
  extraTurnOnSix: boolean;
  extraTurnOnCapture: boolean;
  extraTurnOnHome: boolean;
  maxConsecutiveSixes: number;
  exactFinish: boolean;
  version: string;
}

/** Dart RulesetConfig defaults (ruleset_config.dart, SDD §6.2). */
export const DART_RULESET_DEFAULTS: RulesetConfig = {
  releaseOnSix: true,
  releaseOnOne: false,
  extraTurnOnSix: true,
  extraTurnOnCapture: true,
  extraTurnOnHome: true,
  maxConsecutiveSixes: 3,
  exactFinish: true,
  version: '1.0.0',
};

export type TurnPhase = 'awaitingRoll' | 'awaitingMove' | 'finished';

export const TURN_PHASES: readonly TurnPhase[] = [
  'awaitingRoll',
  'awaitingMove',
  'finished',
];

export interface RollStep {
  op: 'roll';
  expectRoll: number;
  expectLegalMoves: number[];
  expectPhase: TurnPhase;
  expectCurrentPlayer: number;
  expectLastRollWasThirdSix?: boolean;
  expectLastRollHadNoLegalMove?: boolean;
}

export interface MoveExpect {
  fromSteps: number;
  toSteps: number;
  captured: [number, number][];
  enteredHomePath: boolean;
  reachedHome: boolean;
  extraTurn: boolean;
  winnerIndex: number | null;
  expectPhase?: TurnPhase;
  expectCurrentPlayer?: number;
}

export interface MoveStep {
  op: 'move';
  token: number;
  expect: MoveExpect;
}

export interface MoveIllegalStep {
  op: 'moveIllegal';
  token: number;
}

export interface NextTurnStep {
  op: 'nextTurn';
  expectCurrentPlayer: number;
  expectPhase: TurnPhase;
}

export interface RollStateErrorStep {
  op: 'rollStateError';
}

export interface MoveStateErrorStep {
  op: 'moveStateError';
  token: number;
}

export interface MoveWrongPlayerStep {
  op: 'moveWrongPlayer';
  playerIndex: number;
  token: number;
}

export interface SnapshotRoundTripStep {
  op: 'snapshotRoundTrip';
}

export type RuleVectorStep =
  | RollStep
  | MoveStep
  | MoveIllegalStep
  | NextTurnStep
  | RollStateErrorStep
  | MoveStateErrorStep
  | MoveWrongPlayerStep
  | SnapshotRoundTripStep;

export interface RuleVectorExpectFinal {
  currentPlayerIndex: number;
  phase: TurnPhase;
  winnerIndex: number | null;
  lastRoll: number;
  consecutiveSixes: number;
  lastRollWasThirdSix: boolean;
  lastRollHadNoLegalMove: boolean;
  tokens: number[][];
}

export interface RuleVectorCase {
  id: string;
  title: string;
  rules: string[];
  ruleset: RulesetConfig;
  initial: Record<string, unknown>;
  dice: number[];
  steps: RuleVectorStep[];
  expectFinal: RuleVectorExpectFinal;
}

export interface RuleVectors {
  formatVersion: number;
  rulesetVersion: string;
  cases: RuleVectorCase[];
}

export const EXPECTED_VECTOR_COUNT = 39;
export const EXPECTED_RULESET_VERSION = '1.0.0';

export function vectorsFilePath(): string {
  // test/vectors/ -> repo root is three levels up.
  return path.resolve(
    __dirname,
    '..',
    '..',
    '..',
    'diceup_app',
    'test',
    'vectors',
    'rules.json',
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function fail(message: string): never {
  throw new Error(message);
}

function exactKeys(
  obj: Record<string, unknown>,
  allowed: readonly string[],
  where: string,
  optional: readonly string[] = [],
): void {
  for (const key of Object.keys(obj)) {
    if (!allowed.includes(key)) fail(`${where}: unknown field "${key}".`);
  }
  for (const key of allowed) {
    if (!optional.includes(key) && !(key in obj)) {
      fail(`${where}: missing required field "${key}".`);
    }
  }
}

function asString(value: unknown, where: string): string {
  if (typeof value !== 'string') fail(`${where} must be a string.`);
  return value;
}

function asList(value: unknown, where: string): unknown[] {
  if (!Array.isArray(value)) fail(`${where} must be a list.`);
  return value;
}

function asNonNegativeInt(value: unknown, where: string): number {
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0) {
    fail(`${where} must be a non-negative integer.`);
  }
  return value;
}

function asTokenIndex(value: unknown, where: string): number {
  if (
    typeof value !== 'number' ||
    !Number.isInteger(value) ||
    value < 0 ||
    value > 3
  ) {
    fail(`${where} must be a token index 0..3.`);
  }
  return value;
}

function asSteps(value: unknown, where: string): number {
  if (
    typeof value !== 'number' ||
    !Number.isInteger(value) ||
    value < 0 ||
    value > 56
  ) {
    fail(`${where} must be a step count 0..56.`);
  }
  return value;
}

function asPhase(value: unknown, where: string): TurnPhase {
  if (
    typeof value !== 'string' ||
    !(TURN_PHASES as readonly string[]).includes(value)
  ) {
    fail(`${where} must be awaitingRoll, awaitingMove, or finished.`);
  }
  return value as TurnPhase;
}

function asOptionalBool(
  obj: Record<string, unknown>,
  key: string,
  where: string,
): void {
  if (key in obj && typeof obj[key] !== 'boolean') {
    fail(`${where}.${key} must be a bool.`);
  }
}

function deepEquals(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (isRecord(a) && isRecord(b)) {
    const aKeys = Object.keys(a);
    const bKeys = Object.keys(b);
    if (aKeys.length !== bKeys.length) return false;
    return aKeys.every((key) => key in b && deepEquals(a[key], b[key]));
  }
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false;
    return a.every((v, i) => deepEquals(v, b[i]));
  }
  return false;
}

function isRuleset(value: unknown): value is RulesetConfig {
  if (!isRecord(value)) return false;
  return (
    typeof value.releaseOnSix === 'boolean' &&
    typeof value.releaseOnOne === 'boolean' &&
    typeof value.extraTurnOnSix === 'boolean' &&
    typeof value.extraTurnOnCapture === 'boolean' &&
    typeof value.extraTurnOnHome === 'boolean' &&
    typeof value.maxConsecutiveSixes === 'number' &&
    Number.isInteger(value.maxConsecutiveSixes) &&
    typeof value.exactFinish === 'boolean' &&
    typeof value.version === 'string'
  );
}

function validateStep(
  step: unknown,
  caseId: string,
  index: number,
): RuleVectorStep {
  const where = `case "${caseId}".steps[${index}]`;
  if (!isRecord(step)) fail(`${where} must be an object.`);
  const op = asString(step.op, `${where}.op`);
  switch (op) {
    case 'roll': {
      exactKeys(
        step,
        [
          'op',
          'expectRoll',
          'expectLegalMoves',
          'expectPhase',
          'expectCurrentPlayer',
          'expectLastRollWasThirdSix',
          'expectLastRollHadNoLegalMove',
        ],
        where,
        ['expectLastRollWasThirdSix', 'expectLastRollHadNoLegalMove'],
      );
      const roll = step.expectRoll;
      if (
        typeof roll !== 'number' ||
        !Number.isInteger(roll) ||
        roll < 1 ||
        roll > 6
      ) {
        fail(`${where}.expectRoll must be an integer 1..6.`);
      }
      const legal = asList(step.expectLegalMoves, `${where}.legal`);
      let previous = -1;
      for (const token of legal) {
        if (
          typeof token !== 'number' ||
          !Number.isInteger(token) ||
          token < 0 ||
          token > 3 ||
          token <= previous
        ) {
          fail(
            `${where}.expectLegalMoves must be token indices 0..3 in ` +
              `increasing order.`,
          );
        }
        previous = token;
      }
      asPhase(step.expectPhase, `${where}.expectPhase`);
      asNonNegativeInt(
        step.expectCurrentPlayer,
        `${where}.expectCurrentPlayer`,
      );
      asOptionalBool(step, 'expectLastRollWasThirdSix', where);
      asOptionalBool(step, 'expectLastRollHadNoLegalMove', where);
      return step as unknown as RollStep;
    }
    case 'move': {
      exactKeys(step, ['op', 'token', 'expect'], where);
      asTokenIndex(step.token, `${where}.token`);
      if (!isRecord(step.expect)) fail(`${where}.expect must be an object.`);
      const expect = step.expect;
      exactKeys(
        expect,
        [
          'fromSteps',
          'toSteps',
          'captured',
          'enteredHomePath',
          'reachedHome',
          'extraTurn',
          'winnerIndex',
          'expectPhase',
          'expectCurrentPlayer',
        ],
        `${where}.expect`,
        ['expectPhase', 'expectCurrentPlayer'],
      );
      asSteps(expect.fromSteps, `${where}.expect.fromSteps`);
      asSteps(expect.toSteps, `${where}.expect.toSteps`);
      const captured = asList(expect.captured, `${where}.expect.captured`);
      for (const ref of captured) {
        const pair = asList(ref, `${where}.expect.captured entry`);
        if (
          pair.length !== 2 ||
          typeof pair[0] !== 'number' ||
          !Number.isInteger(pair[0]) ||
          (pair[0] as number) < 0 ||
          typeof pair[1] !== 'number' ||
          !Number.isInteger(pair[1]) ||
          (pair[1] as number) < 0 ||
          (pair[1] as number) > 3
        ) {
          fail(
            `${where}.expect.captured entries must be [playerIndex, ` +
              `tokenIndex] pairs.`,
          );
        }
      }
      for (const key of ['enteredHomePath', 'reachedHome', 'extraTurn']) {
        if (typeof expect[key] !== 'boolean') {
          fail(`${where}.expect.${key} must be a bool.`);
        }
      }
      const winner = expect.winnerIndex;
      if (
        winner !== null &&
        (typeof winner !== 'number' || !Number.isInteger(winner) || winner < 0)
      ) {
        fail(`${where}.expect.winnerIndex must be null or a non-negative int.`);
      }
      if ('expectPhase' in expect) {
        asPhase(expect.expectPhase, `${where}.expect.expectPhase`);
      }
      if ('expectCurrentPlayer' in expect) {
        asNonNegativeInt(
          expect.expectCurrentPlayer,
          `${where}.expect.expectCurrentPlayer`,
        );
      }
      return step as unknown as MoveStep;
    }
    case 'moveIllegal':
      exactKeys(step, ['op', 'token'], where);
      asTokenIndex(step.token, `${where}.token`);
      return step as unknown as MoveIllegalStep;
    case 'nextTurn':
      exactKeys(step, ['op', 'expectCurrentPlayer', 'expectPhase'], where);
      asNonNegativeInt(
        step.expectCurrentPlayer,
        `${where}.expectCurrentPlayer`,
      );
      asPhase(step.expectPhase, `${where}.expectPhase`);
      return step as unknown as NextTurnStep;
    case 'rollStateError':
      exactKeys(step, ['op'], where);
      return step as unknown as RollStateErrorStep;
    case 'moveStateError':
      exactKeys(step, ['op', 'token'], where);
      asTokenIndex(step.token, `${where}.token`);
      return step as unknown as MoveStateErrorStep;
    case 'moveWrongPlayer':
      exactKeys(step, ['op', 'playerIndex', 'token'], where);
      asNonNegativeInt(step.playerIndex, `${where}.playerIndex`);
      asTokenIndex(step.token, `${where}.token`);
      return step as unknown as MoveWrongPlayerStep;
    case 'snapshotRoundTrip':
      exactKeys(step, ['op'], where);
      return step as unknown as SnapshotRoundTripStep;
    default:
      return fail(`${where}: unknown op "${op}".`);
  }
}

export function loadRuleVectors(filePath = vectorsFilePath()): RuleVectors {
  const raw = fs.readFileSync(filePath, 'utf8');
  const parsed: unknown = JSON.parse(raw);
  if (!isRecord(parsed)) {
    throw new Error('Rule vectors file is not a JSON object');
  }
  const doc = parsed;
  exactKeys(doc, ['formatVersion', 'rulesetVersion', 'cases'], 'top level');
  if (doc.formatVersion !== 1) {
    throw new Error(
      `Unsupported rule vectors formatVersion: ${String(doc.formatVersion)} (expected 1)`,
    );
  }
  if (doc.rulesetVersion !== EXPECTED_RULESET_VERSION) {
    throw new Error(
      `Unexpected rulesetVersion: ${String(doc.rulesetVersion)} (expected ${EXPECTED_RULESET_VERSION})`,
    );
  }
  const rawCases = asList(doc.cases, 'cases');
  if (rawCases.length === 0) {
    throw new Error('Rule vectors file has no cases array');
  }
  const ids = new Set<string>();
  const cases: RuleVectorCase[] = rawCases.map((rawCase, i) => {
    if (!isRecord(rawCase)) {
      throw new Error(`Rule vector case ${i} is not an object`);
    }
    const c = rawCase;
    exactKeys(
      c,
      [
        'id',
        'title',
        'rules',
        'ruleset',
        'initial',
        'dice',
        'steps',
        'expectFinal',
      ],
      `cases[${i}]`,
    );
    const id = asString(c.id, `cases[${i}].id`);
    if (!id) throw new Error(`cases[${i}].id must not be empty.`);
    if (ids.has(id)) throw new Error(`duplicate case id "${id}".`);
    ids.add(id);
    const title = asString(c.title, `case "${id}".title`);
    if (!title) throw new Error(`case "${id}": title must not be empty.`);
    const rules = asList(c.rules, `case "${id}".rules`);
    if (rules.length === 0) {
      throw new Error(`case "${id}": rules must not be empty.`);
    }
    for (const rule of rules) {
      const label = asString(rule, `case "${id}".rules entry`);
      if (!/^(BR|FR)-\d+$/.test(label)) {
        throw new Error(
          `case "${id}": bad rule label "${label}" (expected BR-NN/FR-NN).`,
        );
      }
    }
    if (!isRecord(c.ruleset)) {
      throw new Error(`Rule vector case ${id} has no ruleset object`);
    }
    const ruleset = c.ruleset;
    exactKeys(
      ruleset,
      [
        'releaseOnSix',
        'releaseOnOne',
        'extraTurnOnSix',
        'extraTurnOnCapture',
        'extraTurnOnHome',
        'maxConsecutiveSixes',
        'exactFinish',
        'version',
      ],
      `case "${id}".ruleset`,
    );
    if (!isRuleset(ruleset)) {
      throw new Error(
        `Rule vector case ${id} has an invalid ruleset (all eight fields required)`,
      );
    }
    // Coherence = Dart RulesetConfig.validate() (see module doc).
    validateRuleset(ruleset, id);
    if (!isRecord(c.initial)) {
      throw new Error(`Rule vector case ${id} has no initial state`);
    }
    const initial = c.initial;
    if (!deepEquals(initial.ruleset, ruleset)) {
      throw new Error(
        `case "${id}": initial.ruleset does not match the case ruleset.`,
      );
    }
    if (initial.rulesetVersion !== EXPECTED_RULESET_VERSION) {
      throw new Error(
        `case "${id}": initial.rulesetVersion does not match ` +
          `rulesetVersion "${EXPECTED_RULESET_VERSION}".`,
      );
    }
    const dice = asList(c.dice, `case "${id}".dice`);
    if (dice.length === 0) {
      throw new Error(`case "${id}": dice must not be empty.`);
    }
    for (const value of dice) {
      if (
        typeof value !== 'number' ||
        !Number.isInteger(value) ||
        value < 1 ||
        value > 6
      ) {
        throw new Error(`case "${id}": dice values must be integers in 1..6.`);
      }
    }
    const rawSteps = asList(c.steps, `case "${id}".steps`);
    if (rawSteps.length === 0) {
      throw new Error(`case "${id}": steps must not be empty.`);
    }
    const steps = rawSteps.map((s, sIdx) => validateStep(s, id, sIdx));
    if (!isRecord(c.expectFinal)) {
      throw new Error(`case "${id}": expectFinal must be an object.`);
    }
    const expectFinal = c.expectFinal;
    exactKeys(
      expectFinal,
      [
        'currentPlayerIndex',
        'phase',
        'winnerIndex',
        'lastRoll',
        'consecutiveSixes',
        'lastRollWasThirdSix',
        'lastRollHadNoLegalMove',
        'tokens',
      ],
      `case "${id}".expectFinal`,
    );
    asPhase(expectFinal.phase, `case "${id}".expectFinal.phase`);
    const players = asList(initial.players, `case "${id}".initial.players`);
    const tokens = asList(
      expectFinal.tokens,
      `case "${id}".expectFinal.tokens`,
    );
    if (tokens.length !== players.length) {
      throw new Error(
        `case "${id}": expectFinal.tokens must have one entry per player ` +
          `(${players.length}).`,
      );
    }
    for (let p = 0; p < tokens.length; p++) {
      const row = asList(tokens[p], `case "${id}".tokens[${p}]`);
      if (row.length !== 4) {
        throw new Error(
          `case "${id}": expectFinal.tokens[${p}] must have 4 entries.`,
        );
      }
      for (const stepsTaken of row) {
        if (
          typeof stepsTaken !== 'number' ||
          !Number.isInteger(stepsTaken) ||
          stepsTaken < 0 ||
          stepsTaken > 56
        ) {
          throw new Error(
            `case "${id}": expectFinal.tokens[${p}] entries must be ` +
              `integers in 0..56.`,
          );
        }
      }
    }
    // Return the case with the validated (typed) steps, not the raw JSON.
    return { ...c, steps } as unknown as RuleVectorCase;
  });
  if (cases.length !== EXPECTED_VECTOR_COUNT) {
    throw new Error(
      `Expected ${EXPECTED_VECTOR_COUNT} rule vector cases, found ${cases.length}`,
    );
  }
  return {
    formatVersion: doc.formatVersion as number,
    rulesetVersion: doc.rulesetVersion as string,
    cases,
  };
}

/** Dart RulesetConfig.validate() coherence rules, per case. */
export function validateRuleset(ruleset: RulesetConfig, caseId: string): void {
  if (!ruleset.releaseOnSix && !ruleset.releaseOnOne) {
    throw new Error(
      `Rule vector case ${caseId}: at least one release roll must be enabled`,
    );
  }
  if (ruleset.maxConsecutiveSixes < 0) {
    throw new Error(
      `Rule vector case ${caseId}: maxConsecutiveSixes must be 0 (off) or positive`,
    );
  }
  if (!ruleset.version) {
    throw new Error(`Rule vector case ${caseId}: version must not be empty`);
  }
  if (ruleset.version !== EXPECTED_RULESET_VERSION) {
    throw new Error(
      `Rule vector case ${caseId}: ruleset.version is ${ruleset.version}, expected ${EXPECTED_RULESET_VERSION}`,
    );
  }
}

/** Keys on which a case's ruleset differs from the Dart defaults. */
export function rulesetDiffFromDefaults(
  ruleset: RulesetConfig,
): (keyof RulesetConfig)[] {
  return (Object.keys(DART_RULESET_DEFAULTS) as (keyof RulesetConfig)[]).filter(
    (key) => ruleset[key] !== DART_RULESET_DEFAULTS[key],
  );
}

/**
 * Asserts the canonical default case embeds the Dart defaults exactly.
 * Variant cases are expected to differ (see module doc) and are
 * checked individually by the spec, not here.
 */
export function assertDefaultCaseMatchesDartDefaults(
  vectors: RuleVectors,
): void {
  const canonical = vectors.cases.find((c) => c.id === 'release-only-on-six');
  if (!canonical) {
    throw new Error('Rule vectors are missing the release-only-on-six case');
  }
  const diff = rulesetDiffFromDefaults(canonical.ruleset);
  if (diff.length > 0) {
    throw new Error(
      `Rule vector case release-only-on-six differs from Dart defaults on: ${diff.join(', ')}`,
    );
  }
}
