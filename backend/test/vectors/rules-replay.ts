/**
 * TypeScript conformance replay (NFR-39, Stage 4).
 *
 * Replays every case in the single shared `rules.json` through the
 * TypeScript engine (`LudoGame.fromState` + `rollDice` /
 * `legalMoves` / `applyMove` with a `FixedDiceRoller`), mirroring
 * the Dart runner
 * (`diceup_app/test/vectors/rules_vectors_test.dart`) step for step.
 * A vector that fails fails the build: there are no silent skips
 * and no lenient matching.
 *
 * The harness throws a plain `Error` naming the case and step on the
 * first mismatch; the parity spec wraps each case in its own test.
 */
import {
  ArgumentError,
  FixedDiceRoller,
  GameState,
  LudoGame,
  Move,
  RulesetConfig,
  StateError,
} from '../../src/game';
import type { RuleVectorCase } from './rules-vectors.loader';

function check(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function assertJsonEqual(
  actual: unknown,
  expected: unknown,
  what: string,
): void {
  check(
    JSON.stringify(actual) === JSON.stringify(expected),
    `${what}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
  );
}

function assertThrows<T extends Error>(
  fn: () => void,
  expected: new (...args: never[]) => T,
  what: string,
): void {
  try {
    fn();
  } catch (e) {
    check(
      e instanceof expected,
      `${what}: expected ${expected.name}, got ${(e as Error)?.constructor?.name ?? e}`,
    );
    return;
  }
  throw new Error(`${what}: expected ${expected.name}, but nothing was thrown`);
}

/**
 * Replays one validated case through the TS engine. The dice
 * sequence restarts on a `snapshotRoundTrip` restore, exactly as in
 * the Dart runner, so that op must precede any roll step in a case.
 */
export function replayCase(c: RuleVectorCase): void {
  const id = c.id;
  const ruleset = RulesetConfig.fromJson(
    c.ruleset as unknown as Record<string, unknown>,
  );
  let game = LudoGame.fromState(GameState.fromJson(c.initial), {
    ruleset,
    diceRoller: new FixedDiceRoller(c.dice),
  });
  for (const step of c.steps) {
    switch (step.op) {
      case 'roll': {
        const value = game.rollDice();
        check(value === step.expectRoll, `${id}: rolled value`);
        assertJsonEqual(
          game.legalMoves().map((m) => m.tokenIndex),
          step.expectLegalMoves,
          `${id}: legal moves after rolling ${value}`,
        );
        check(
          game.state.phase === step.expectPhase,
          `${id}: phase after rolling ${value}`,
        );
        check(
          game.currentPlayerIndex === step.expectCurrentPlayer,
          `${id}: current player after rolling ${value}`,
        );
        if (step.expectLastRollWasThirdSix !== undefined) {
          check(
            game.state.lastRollWasThirdSix === step.expectLastRollWasThirdSix,
            `${id}: lastRollWasThirdSix after rolling ${value}`,
          );
        }
        if (step.expectLastRollHadNoLegalMove !== undefined) {
          check(
            game.state.lastRollHadNoLegalMove ===
              step.expectLastRollHadNoLegalMove,
            `${id}: lastRollHadNoLegalMove after rolling ${value}`,
          );
        }
        break;
      }
      case 'move': {
        const result = game.applyMove(
          new Move(game.currentPlayerIndex, step.token),
        );
        const expect = step.expect;
        check(result.fromSteps === expect.fromSteps, `${id}: fromSteps`);
        check(result.toSteps === expect.toSteps, `${id}: toSteps`);
        assertJsonEqual(
          result.captured.map((t) => [t.playerIndex, t.tokenIndex]),
          expect.captured,
          `${id}: captured tokens`,
        );
        check(
          result.enteredHomePath === expect.enteredHomePath,
          `${id}: enteredHomePath`,
        );
        check(result.reachedHome === expect.reachedHome, `${id}: reachedHome`);
        check(result.extraTurn === expect.extraTurn, `${id}: extraTurn`);
        check(result.winnerIndex === expect.winnerIndex, `${id}: winnerIndex`);
        if (expect.expectPhase !== undefined) {
          check(
            game.state.phase === expect.expectPhase,
            `${id}: phase after move`,
          );
        }
        if (expect.expectCurrentPlayer !== undefined) {
          check(
            game.currentPlayerIndex === expect.expectCurrentPlayer,
            `${id}: current player after move`,
          );
        }
        break;
      }
      case 'moveIllegal': {
        const before = game.state.toJson();
        assertThrows(
          () => game.applyMove(new Move(game.currentPlayerIndex, step.token)),
          ArgumentError,
          `${id}: illegal move must throw ArgumentError`,
        );
        assertJsonEqual(
          game.state.toJson(),
          before,
          `${id}: state must be unchanged after an illegal move`,
        );
        break;
      }
      case 'nextTurn': {
        game.nextTurn();
        check(
          game.state.phase === step.expectPhase,
          `${id}: phase after nextTurn`,
        );
        check(
          game.currentPlayerIndex === step.expectCurrentPlayer,
          `${id}: current player after nextTurn`,
        );
        break;
      }
      case 'rollStateError': {
        const before = game.state.toJson();
        assertThrows(
          () => game.rollDice(),
          StateError,
          `${id}: rolling while a move is pending must throw StateError`,
        );
        assertJsonEqual(
          game.state.toJson(),
          before,
          `${id}: state must be unchanged after a rejected roll`,
        );
        break;
      }
      case 'moveStateError': {
        const before = game.state.toJson();
        assertThrows(
          () => game.applyMove(new Move(game.currentPlayerIndex, step.token)),
          StateError,
          `${id}: moving before a roll must throw StateError`,
        );
        assertJsonEqual(
          game.state.toJson(),
          before,
          `${id}: state must be unchanged after a rejected move`,
        );
        break;
      }
      case 'moveWrongPlayer': {
        const before = game.state.toJson();
        assertThrows(
          () => game.applyMove(new Move(step.playerIndex, step.token)),
          ArgumentError,
          `${id}: a move by the wrong player must throw ArgumentError`,
        );
        assertJsonEqual(
          game.state.toJson(),
          before,
          `${id}: state must be unchanged after a wrong-player move`,
        );
        break;
      }
      case 'snapshotRoundTrip': {
        const before = game.state.toJson();
        game = LudoGame.restore(game.snapshot(), {
          ruleset,
          diceRoller: new FixedDiceRoller(c.dice),
        });
        assertJsonEqual(
          game.state.toJson(),
          before,
          `${id}: restored state must equal the snapshot`,
        );
        break;
      }
      default: {
        const _exhaustive: never = step;
        throw new Error(`${id}: unknown op ${JSON.stringify(_exhaustive)}`);
      }
    }
  }
  const expectFinal = c.expectFinal;
  check(
    game.currentPlayerIndex === expectFinal.currentPlayerIndex,
    `${id}: final current player`,
  );
  check(game.state.phase === expectFinal.phase, `${id}: final phase`);
  check(
    game.state.winnerIndex === expectFinal.winnerIndex,
    `${id}: final winner`,
  );
  check(game.state.lastRoll === expectFinal.lastRoll, `${id}: final lastRoll`);
  check(
    game.state.consecutiveSixes === expectFinal.consecutiveSixes,
    `${id}: final consecutiveSixes`,
  );
  check(
    game.state.lastRollWasThirdSix === expectFinal.lastRollWasThirdSix,
    `${id}: final lastRollWasThirdSix`,
  );
  check(
    game.state.lastRollHadNoLegalMove === expectFinal.lastRollHadNoLegalMove,
    `${id}: final lastRollHadNoLegalMove`,
  );
  assertJsonEqual(
    game.state.players.map((p) => p.tokens.map((t) => t.stepsTaken)),
    expectFinal.tokens,
    `${id}: final token positions`,
  );
}

/** Total replay steps across all cases (for the parity report). */
export function totalSteps(cases: readonly RuleVectorCase[]): number {
  return cases.reduce((sum, c) => sum + c.steps.length, 0);
}
