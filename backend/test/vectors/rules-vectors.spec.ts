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

describe('rule-vector loader — NFR-39 foundation (plan §2.1.2)', () => {
  it('parses 23/23 cases from the single repo copy', () => {
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

  it('the 6 variant cases each differ from the defaults in exactly one field', () => {
    // Plan §2.1.2 said every case equals the defaults; the real file
    // has 6 deliberate single-field variants (see loader doc). 17/23
    // cases match the defaults exactly.
    const vectors = loadRuleVectors();
    const byId = new Map(vectors.cases.map((c) => [c.id, c.ruleset]));
    expect(
      vectors.cases.filter(
        (c) => rulesetDiffFromDefaults(c.ruleset).length === 0,
      ),
    ).toHaveLength(17);
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
    ).toThrow(/Expected 23/);
    const missingField = JSON.parse(JSON.stringify(good)) as typeof good;
    delete (missingField.cases[0].ruleset as unknown as Record<string, unknown>)
      .exactFinish;
    expect(() =>
      loadRuleVectors(write(missingField, 'missing-field.json')),
    ).toThrow(/invalid ruleset/);
    const wrongRuleset = JSON.parse(JSON.stringify(good)) as typeof good;
    wrongRuleset.cases[0].ruleset.releaseOnSix = false;
    wrongRuleset.cases[0].ruleset.releaseOnOne = false;
    expect(() =>
      loadRuleVectors(write(wrongRuleset, 'wrong-ruleset.json')),
    ).toThrow(/at least one release roll/);
    fs.rmSync(tmp, { recursive: true, force: true });
  });
});
