import { loadRuleVectors } from './rules-vectors.loader';
import { replayCase, totalSteps } from './rules-replay';

/**
 * Dart/TS parity run (NFR-39, Stage 4).
 *
 * Runs the SAME `rules.json` against the TypeScript engine that the
 * Dart runner runs against the Dart engine. Every case must pass in
 * both languages; a case passing in one language only is a parity
 * failure, not a partial pass.
 */
describe('rule-vector parity — Dart/TS on the same rules.json', () => {
  const vectors = loadRuleVectors();

  it('rules.json contains at least 14 cases', () => {
    expect(vectors.cases.length).toBeGreaterThanOrEqual(14);
  });

  it('rules.json covers every rule family (D-16)', () => {
    const covered = new Set(vectors.cases.flatMap((c) => c.rules));
    for (const rule of [
      'BR-04',
      'BR-05',
      'BR-06',
      'BR-07',
      'BR-08',
      'BR-09',
      'BR-10',
      'BR-11',
      'BR-12',
      'BR-13',
    ]) {
      expect(covered.has(rule)).toBe(true);
    }
  });

  it('reports exact coverage: 39 cases, 76 replay steps', () => {
    expect(vectors.cases).toHaveLength(39);
    expect(totalSteps(vectors.cases)).toBe(76);
    const byOp = new Map<string, number>();
    for (const c of vectors.cases) {
      for (const step of c.steps) {
        byOp.set(step.op, (byOp.get(step.op) ?? 0) + 1);
      }
    }
    expect(Object.fromEntries(byOp)).toEqual({
      roll: 41,
      move: 29,
      moveIllegal: 1,
      nextTurn: 1,
      rollStateError: 1,
      moveStateError: 1,
      moveWrongPlayer: 1,
      snapshotRoundTrip: 1,
    });
  });

  describe('rule vectors (docs/ruleset.md)', () => {
    for (const c of vectors.cases) {
      it(c.id, () => {
        expect(() => replayCase(c)).not.toThrow();
      });
    }
  });
});
