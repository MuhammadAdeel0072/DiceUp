import 'player_colour.dart';

/// Where a token can be on the board.
///
/// SDD §6.2 / SRS §7.1 (assumption A-03): a shared outer track of
/// 52 cells, four home paths of 5 coloured cells each, and a home cell.
/// A token's journey from its start cell to home is 56 steps.
enum CellKind {
  /// Waiting to enter the board.
  yard,

  /// On the shared outer track; [Cell.index] is the track index 0..51.
  track,

  /// On the owner's home path; [Cell.index] is 0..4.
  homePath,

  /// Home: the journey is complete.
  home,
}

/// A logical board position. The engine never deals in pixels: the
/// CustomPainter asks the [Board] for logical positions (SDD §6.2).
class Cell {
  const Cell.yard()
      : kind = CellKind.yard,
        index = -1;

  const Cell.track(this.index) : kind = CellKind.track;

  const Cell.homePath(this.index) : kind = CellKind.homePath;

  const Cell.home()
      : kind = CellKind.home,
        index = -1;

  final CellKind kind;

  /// Track index (0..51) for [CellKind.track], home-path index (0..4)
  /// for [CellKind.homePath], -1 otherwise.
  final int index;

  bool get isYard => kind == CellKind.yard;
  bool get isHome => kind == CellKind.home;

  @override
  bool operator ==(Object other) =>
      other is Cell && kind == other.kind && index == other.index;

  @override
  int get hashCode => Object.hash(kind, index);

  @override
  String toString() => 'Cell($kind, $index)';
}

/// Board geometry: track, start cells, home paths and safe cells.
///
/// Concrete positions (assumption A-03 concretised — the SRS states
/// "the four colour start cells and four star cells (default
/// positions)" without naming indices, so the conventional layout is
/// used and recorded here):
/// * start cells are 13 apart: red 0, green 13, yellow 26, blue 39;
/// * star cells sit 8 steps after each start: 8, 21, 34, 47.
/// Safe cells are the 4 start cells + the 4 star cells = 8 in total.
class Board {
  const Board();

  /// Number of cells on the shared outer track (SRS §7.1).
  static const int trackSize = 52;

  /// Steps from the start cell to home (SRS §7.1).
  static const int stepsToHome = 56;

  /// Coloured cells on a home path, excluding the home cell itself.
  static const int homePathLength = 5;

  /// Last step still on the outer track; steps 52..55 are the home
  /// path and step 56 is home.
  static const int lastTrackStep = 51;

  /// Start-cell track index for each colour.
  static const Map<PlayerColour, int> startCells = {
    PlayerColour.red: 0,
    PlayerColour.green: 13,
    PlayerColour.yellow: 26,
    PlayerColour.blue: 39,
  };

  /// Star cells: the safe cells that are not start cells.
  static const Set<int> starCells = {8, 21, 34, 47};

  /// All 8 safe cells (BR-09).
  static const Set<int> safeCells = {0, 8, 13, 21, 26, 34, 39, 47};

  /// Track index of [colour]'s start cell (BR-04 release target).
  int startCell(PlayerColour colour) => startCells[colour]!;

  /// Whether a track index is a safe cell (BR-09).
  bool isSafeTrackCell(int trackIndex) => safeCells.contains(trackIndex);

  /// Whether a [Cell] can never be captured on. Home-path and home
  /// cells belong to one owner only, so they are safe by construction.
  bool isSafe(Cell cell) {
    if (cell.kind == CellKind.track) return isSafeTrackCell(cell.index);
    return cell.kind == CellKind.homePath || cell.kind == CellKind.home;
  }

  /// Logical cell for a token that has taken [stepsTaken] steps
  /// (0 = yard, 1 = start cell, 56 = home).
  Cell cellAt(PlayerColour colour, int stepsTaken) {
    if (stepsTaken <= 0) return const Cell.yard();
    if (stepsTaken > stepsToHome) {
      throw ArgumentError('stepsTaken must be 0..$stepsToHome.');
    }
    if (stepsTaken == stepsToHome) return const Cell.home();
    if (stepsTaken > lastTrackStep) {
      // Home path: steps 52..56 map to home-path indices 0..4, then home.
      return Cell.homePath(stepsTaken - lastTrackStep - 1);
    }
    final trackIndex =
        (startCell(colour) + stepsTaken - 1) % trackSize;
    return Cell.track(trackIndex);
  }
}
