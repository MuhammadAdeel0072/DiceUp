/**
 * Authoritative TypeScript Ludo engine (Phase 5, Stage 4).
 *
 * A faithful port of the Dart offline engine
 * (`diceup_app/lib/domain/engine/`), which wins wherever the docs
 * disagree (D-20): 51 track + 4 home-path + home = 56 steps, release
 * lands on step 1 spending the roll, winning is BR-11, and the turn
 * machine has exactly three phases (`awaitingRoll`, `awaitingMove`,
 * `finished`).
 *
 * The engine is independent of transport and persistence: rules,
 * state, actions, validation and transitions are separated here, and
 * Stages 5–6 own socket events, REST endpoints and match storage.
 * The public API Stage 5 calls: `newMatch`, `fromState` / `restore`,
 * `rollDice`, `legalMoves`, `applyMove`, `nextTurn`, `snapshot`.
 */
export * from './board';
export * from './dice-roller';
export * from './errors';
export * from './game-state';
export * from './json-validation';
export * from './ludo-game';
export * from './move';
export * from './player';
export * from './player-colour';
export * from './ruleset-config';
export * from './token';
