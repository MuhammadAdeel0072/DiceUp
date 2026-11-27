import * as fs from 'node:fs';
import * as path from 'node:path';

/**
 * Rule-vector loader — NFR-39 foundation only (plan §2.1.2).
 * Reads the ONE copy of the vectors file at
 * `diceup_app/test/vectors/rules.json` (never copied) and validates
 * its schema.
 *
 * CORRECTION to the plan (§2.1.2/§10.2, recorded for Stage 5): the
 * plan says the loader "asserts the embedded ruleset equals the Dart
 * RulesetConfig defaults". That is NOT true of the real file: 17/23
 * cases embed the defaults, but 6 are deliberate single-field
 * *variants* (release-on-one-variant, extra-turn-on-six-disabled,
 * extra-turn-on-capture-disabled, extra-turn-on-home-disabled,
 * third-six-limit-off, exact-finish-off-overshoot-lands-home). The
 * vectors file is authoritative, so the loader instead validates
 * every embedded ruleset for *coherence* (the Dart
 * RulesetConfig.validate() rules: at least one release roll,
 * maxConsecutiveSixes >= 0, version non-empty and == rulesetVersion)
 * and asserts the canonical default case matches the Dart defaults
 * exactly. The TypeScript engine this will test does not exist until
 * Phase 5, so no conformance run is claimed in Phase 4.
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

export interface RuleVectorCase {
  id: string;
  title: string;
  rules: string[];
  ruleset: RulesetConfig;
  initial: Record<string, unknown>;
}

export interface RuleVectors {
  formatVersion: number;
  rulesetVersion: string;
  cases: RuleVectorCase[];
}

export const EXPECTED_VECTOR_COUNT = 23;
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

function isRuleset(value: unknown): value is RulesetConfig {
  if (typeof value !== 'object' || value === null) return false;
  const r = value as Record<string, unknown>;
  return (
    typeof r.releaseOnSix === 'boolean' &&
    typeof r.releaseOnOne === 'boolean' &&
    typeof r.extraTurnOnSix === 'boolean' &&
    typeof r.extraTurnOnCapture === 'boolean' &&
    typeof r.extraTurnOnHome === 'boolean' &&
    typeof r.maxConsecutiveSixes === 'number' &&
    typeof r.exactFinish === 'boolean' &&
    typeof r.version === 'string'
  );
}

export function loadRuleVectors(filePath = vectorsFilePath()): RuleVectors {
  const raw = fs.readFileSync(filePath, 'utf8');
  const parsed: unknown = JSON.parse(raw);
  if (typeof parsed !== 'object' || parsed === null) {
    throw new Error('Rule vectors file is not a JSON object');
  }
  const doc = parsed as Record<string, unknown>;
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
  if (!Array.isArray(doc.cases)) {
    throw new Error('Rule vectors file has no cases array');
  }
  const cases: RuleVectorCase[] = doc.cases.map((c: unknown, i: number) => {
    if (typeof c !== 'object' || c === null) {
      throw new Error(`Rule vector case ${i} is not an object`);
    }
    const cc = c as Record<string, unknown>;
    if (typeof cc.id !== 'string' || !cc.id) {
      throw new Error(`Rule vector case ${i} has no id`);
    }
    if (typeof cc.title !== 'string' || !cc.title) {
      throw new Error(`Rule vector case ${cc.id} has no title`);
    }
    if (!Array.isArray(cc.rules) || cc.rules.length === 0) {
      throw new Error(`Rule vector case ${cc.id} has no rules`);
    }
    if (!isRuleset(cc.ruleset)) {
      throw new Error(
        `Rule vector case ${cc.id} has an invalid ruleset (all eight fields required)`,
      );
    }
    if (typeof cc.initial !== 'object' || cc.initial === null) {
      throw new Error(`Rule vector case ${cc.id} has no initial state`);
    }
    // Coherence = Dart RulesetConfig.validate() (see module doc).
    validateRuleset(cc.ruleset as RulesetConfig, cc.id as string);
    return cc as unknown as RuleVectorCase;
  });
  if (cases.length !== EXPECTED_VECTOR_COUNT) {
    throw new Error(
      `Expected ${EXPECTED_VECTOR_COUNT} rule vector cases, found ${cases.length}`,
    );
  }
  const ids = new Set(cases.map((c) => c.id));
  if (ids.size !== cases.length) {
    throw new Error('Rule vector case ids are not unique');
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
