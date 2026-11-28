/**
 * Board geometry: track, start cells, home paths and safe cells
 * (mirrors Dart `board.dart`).
 *
 * NOTE (D-20, decided 2026-11-21): the decided split is 51 track +
 * 4 home-path cells + home = 56 — the SDD §6.2 / SRS §7.1 wording
 * ("four home paths of 5 coloured cells each") is an approved
 * deviation; the engine wins.
 *
 * Concrete positions (assumption A-03 concretised — the SRS states
 * "the four colour start cells and four star cells (default
 * positions)" without naming indices, so the conventional layout is
 * used and recorded here):
 * * start cells are 13 apart: red 0, green 13, yellow 26, blue 39;
 * * star cells sit 8 steps after each start: 8, 21, 34, 47.
 * Safe cells are the 4 start cells + the 4 star cells = 8 in total.
 */
import { ArgumentError } from './errors';
import type { PlayerColour } from './player-colour';

export type CellKind = 'yard' | 'track' | 'homePath' | 'home';

/** A logical board position. The engine never deals in pixels. */
export class Cell {
  static yard(): Cell {
    return new Cell('yard', -1);
  }

  static track(index: number): Cell {
    return new Cell('track', index);
  }

  static homePath(index: number): Cell {
    return new Cell('homePath', index);
  }

  static home(): Cell {
    return new Cell('home', -1);
  }

  private constructor(
    readonly kind: CellKind,
    /**
     * Track index (0..51) for `track`, home-path index (0..3) for
     * `homePath`, -1 otherwise.
     */
    readonly index: number,
  ) {}

  get isYard(): boolean {
    return this.kind === 'yard';
  }

  get isHome(): boolean {
    return this.kind === 'home';
  }

  equals(other: Cell): boolean {
    return this.kind === other.kind && this.index === other.index;
  }

  toString(): string {
    return `Cell(${this.kind}, ${this.index})`;
  }
}

export class Board {
  /** Number of cells on the shared outer track (SRS §7.1). */
  static readonly trackSize = 52;

  /** Steps from the start cell to home (SRS §7.1). */
  static readonly stepsToHome = 56;

  /**
   * Coloured cells on a home path, excluding the home cell itself.
   * (D-20: 4 — 51 + 4 + 1 = 56.)
   */
  static readonly homePathLength = 4;

  /**
   * Last step still on the outer track; steps 52..55 are the home
   * path and step 56 is home.
   */
  static readonly lastTrackStep = 51;

  /** Start-cell track index for each colour. */
  static readonly startCells: Readonly<Record<PlayerColour, number>> = {
    red: 0,
    green: 13,
    yellow: 26,
    blue: 39,
  };

  /** Star cells: the safe cells that are not start cells. */
  static readonly starCells: ReadonlySet<number> = new Set([8, 21, 34, 47]);

  /** All 8 safe cells (BR-09). */
  static readonly safeCells: ReadonlySet<number> = new Set([
    0, 8, 13, 21, 26, 34, 39, 47,
  ]);

  /** Track index of `colour`'s start cell (BR-04 release target). */
  startCell(colour: PlayerColour): number {
    return Board.startCells[colour];
  }

  /** Whether a track index is a safe cell (BR-09). */
  isSafeTrackCell(trackIndex: number): boolean {
    return Board.safeCells.has(trackIndex);
  }

  /**
   * Whether a {@link Cell} can never be captured on. Home-path and
   * home cells belong to one owner only, so they are safe by
   * construction.
   */
  isSafe(cell: Cell): boolean {
    if (cell.kind === 'track') return this.isSafeTrackCell(cell.index);
    return cell.kind === 'homePath' || cell.kind === 'home';
  }

  /**
   * Logical cell for a token that has taken `stepsTaken` steps
   * (0 = yard, 1 = start cell, 56 = home).
   */
  cellAt(colour: PlayerColour, stepsTaken: number): Cell {
    if (stepsTaken <= 0) return Cell.yard();
    if (stepsTaken > Board.stepsToHome) {
      throw new ArgumentError(`stepsTaken must be 0..${Board.stepsToHome}.`);
    }
    if (stepsTaken === Board.stepsToHome) return Cell.home();
    if (stepsTaken > Board.lastTrackStep) {
      // Home path: steps 52..55 map to home-path indices 0..3; step 56
      // is home (D-20: 51 + 4 + 1 = 56).
      return Cell.homePath(stepsTaken - Board.lastTrackStep - 1);
    }
    const trackIndex =
      (this.startCell(colour) + stepsTaken - 1) % Board.trackSize;
    return Cell.track(trackIndex);
  }
}
