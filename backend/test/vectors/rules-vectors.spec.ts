import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import {
  DART_RULESET_DEFAULTS,
  EXPECTED_VECTOR_COUNT,
  assertDefaultCaseMatchesDartDefaults,
  loadRuleVectors,
  rulesetDiffFromDefaults,
  vectorsFilePath,
} from './rules-vectors.loader';

describe('rule-vector loader — NFR-39 (Stage 4: full case shape)', () => {
  it('parses 39/39 cases from the single repo copy', () => {
    const vectors = loadRuleVectors();
    expect(vectors.formatVersion).toBe(1);
    expect(vectors.rulesetVersion).toBe('1.0.0');
    expect(vectors.cases).toHaveLength(EXPECTED_VECTOR_COUNT);
    expect(vectorsFilePath()).toContain(
      path.join('diceup_app', 'test', 'vectors', 'rules.json'),
    );
  });

  it('the canonical case embeds the Dart RulesetConfig defaults (SDD §6.2)', () => {
    const vectors = loadRuleVectors();
    expect(() => assertDefaultCaseMatchesDartDefaults(vectors)).not.toThrow();
    expect(DART_RULESET_DEFAULTS).toEqual({
      releaseOnSix: true,
      releaseOnOne: false,
      extraTurnOnSix: true,
      extraTurnOnCapture: true,
      extraTurnOnHome: true,
      maxConsecutiveSixes: 3,
      exactFinish: true,
      version: '1.0.0',
    });
  });

  it('the 10 variant cases differ from the defaults as documented', () => {
    // Plan §2.1.2 said every case equals the defaults; the real file
    // has 10 deliberate variants (see loader doc). 29/39 cases match
    // the defaults exactly. The 6 Phase 4 variants each differ in
    // exactly one field; the 4 Stage 4 variants differ as listed.
    const vectors = loadRuleVectors();
    const byId = new Map(vectors.cases.map((c) => [c.id, c.ruleset]));
    expect(
      vectors.cases.filter(
        (c) => rulesetDiffFromDefaults(c.ruleset).length === 0,
      ),
    ).toHaveLength(29);
    expect(
      rulesetDiffFromDefaults(byId.get('release-on-one-variant')!),
    ).toEqual(['releaseOnOne']);
    expect(
      rulesetDiffFromDefaults(byId.get('extra-turn-on-six-disabled')!),
    ).toEqual(['extraTurnOnSix']);
    expect(
      rulesetDiffFromDefaults(byId.get('extra-turn-on-capture-disabled')!),
    ).toEqual(['extraTurnOnCapture']);
    expect(
      rulesetDiffFromDefaults(byId.get('extra-turn-on-home-disabled')!),
    ).toEqual(['extraTurnOnHome']);
    expect(rulesetDiffFromDefaults(byId.get('third-six-limit-off')!)).toEqual([
      'maxConsecutiveSixes',
    ]);
    expect(
      rulesetDiffFromDefaults(
        byId.get('exact-finish-off-overshoot-lands-home')!,
      ),
    ).toEqual(['exactFinish']);
    expect(rulesetDiffFromDefaults(byId.get('release-on-one-only')!)).toEqual([
      'releaseOnSix',
      'releaseOnOne',
    ]);
    expect(
      rulesetDiffFromDefaults(byId.get('max-consecutive-sixes-two')!),
    ).toEqual(['maxConsecutiveSixes']);
    expect(
      rulesetDiffFromDefaults(byId.get('max-consecutive-sixes-five')!),
    ).toEqual(['maxConsecutiveSixes']);
    expect(
      rulesetDiffFromDefaults(
        byId.get('combined-variant-release-one-exact-off')!,
      ),
    ).toEqual([
      'releaseOnOne',
      'extraTurnOnCapture',
      'maxConsecutiveSixes',
      'exactFinish',
    ]);
  });

  it('the loader rejects a bad step op and a mismatched embedded ruleset', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'diceup-vectors-'));
    const good = loadRuleVectors();
    const write = (obj: unknown, name: string) => {
      const p = path.join(tmp, name);
      fs.writeFileSync(p, JSON.stringify(obj));
      return p;
    };
    const badOp = JSON.parse(JSON.stringify(good)) as typeof good;
    (badOp.cases[0].steps[0] as unknown as Record<string, unknown>).op =
      'teleport';
    expect(() => loadRuleVectors(write(badOp, 'bad-op.json'))).toThrow(
      /unknown op/,
    );
    const badEmbedded = JSON.parse(JSON.stringify(good)) as typeof good;
    (
      badEmbedded.cases[0].initial as unknown as Record<string, unknown>
    ).ruleset = {
      ...(badEmbedded.cases[0].ruleset as unknown as Record<string, unknown>),
      exactFinish: false,
    };
    expect(() =>
      loadRuleVectors(write(badEmbedded, 'bad-embedded.json')),
    ).toThrow(/initial.ruleset does not match/);
    fs.rmSync(tmp, { recursive: true, force: true });
  });

  it('tampered vectors fail: bad version, missing field, wrong count', () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'diceup-vectors-'));
    const good = loadRuleVectors();
    const write = (obj: unknown, name: string) => {
      const p = path.join(tmp, name);
      fs.writeFileSync(p, JSON.stringify(obj));
      return p;
    };
    expect(() =>
      loadRuleVectors(
        write({ ...good, rulesetVersion: '9.9.9' }, 'bad-version.json'),
      ),
    ).toThrow(/rulesetVersion/);
    expect(() =>
      loadRuleVectors(
        write({ ...good, cases: good.cases.slice(0, 5) }, 'short.json'),
      ),
    ).toThrow(/Expected 39/);
    const missingField = JSON.parse(JSON.stringify(good)) as typeof good;
    delete (missingField.cases[0].ruleset as unknown as Record<string, unknown>)
      .exactFinish;
    expect(() =>
      loadRuleVectors(write(missingField, 'missing-field.json')),
    ).toThrow(/missing required field "exactFinish"/);
    const wrongRuleset = JSON.parse(JSON.stringify(good)) as typeof good;
    wrongRuleset.cases[0].ruleset.releaseOnSix = false;
    wrongRuleset.cases[0].ruleset.releaseOnOne = false;
    expect(() =>
      loadRuleVectors(write(wrongRuleset, 'wrong-ruleset.json')),
    ).toThrow(/at least one release roll/);
    fs.rmSync(tmp, { recursive: true, force: true });
  });
});
