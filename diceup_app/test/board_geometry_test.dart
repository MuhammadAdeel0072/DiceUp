import 'dart:math' as math;

import 'package:diceup/domain/engine/board.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter_test/flutter_test.dart';

/// M3.5 (M-08, D-20): board-geometry property / equivalence tests.
///
/// Written BEFORE the painter fix, against the current painter:
/// the dead-cell test and the colour-mapping tests FAIL until the
/// D-20 fix lands (5 drawn home-path cells per seat, of which index 4
/// is never occupied; the painter maps by `seatIndex * 13`, not by
/// colour). They are recorded as known failures the fix resolves —
/// never skipped, never weakened.
///
/// Properties pinned (remediation plan §6, "Geometry (M3.5)"):
/// * 52 unique track cells, closed loop;
/// * home-path entries adjacent to the track;
/// * painter mapping == engine mapping for all steps 0..56 × all 4 seats;
/// * `safeTrackIndices == Board.safeCells`;
/// * every drawn home-path cell reachable.
void main() {
  const board = Board();

  bool adjacent(math.Point<int> a, math.Point<int> b) =>
      math.max((a.x - b.x).abs(), (a.y - b.y).abs()) == 1;

  /// The painter's cell for a token of [colour] at [stepsTaken].
  /// [seatIndex] defaults to the colour's seat-order position; passing
  /// a different seat exercises the colour-vs-seat mapping.
  math.Point<double>? painterCell(
    PlayerColour colour,
    int stepsTaken, {
    int? seatIndex,
    PlayerColour? explicitColour,
  }) => boardCellForToken(
    BoardToken(
      id: '${seatIndex ?? colour.index}:$stepsTaken',
      seatIndex: seatIndex ?? colour.index,
      stepsTaken: stepsTaken,
      colour: explicitColour ?? colour,
    ),
  );

  /// The engine's cell for the same token, expressed in painter
  /// (grid-point) coordinates, or null for yard / home.
  math.Point<double>? engineCell(PlayerColour colour, int stepsTaken) {
    final cell = board.cellAt(colour, stepsTaken);
    return switch (cell.kind) {
      CellKind.track => _asDouble(trackCells[cell.index]),
      CellKind.homePath => _asDouble(homePathCells(colour)[cell.index]),
      CellKind.yard || CellKind.home => null,
    };
  }

  group('track table (M3.5)', () {
    test('has 52 unique cells inside the 15x15 grid', () {
      expect(trackCells, hasLength(52));
      expect(trackCells.toSet(), hasLength(52));
      for (final cell in trackCells) {
        expect(cell.x, inInclusiveRange(0, 14));
        expect(cell.y, inInclusiveRange(0, 14));
      }
    });

    test('is a closed loop: consecutive cells adjacent, last to first', () {
      for (var i = 0; i < trackCells.length; i++) {
        final next = trackCells[(i + 1) % trackCells.length];
        expect(
          adjacent(trackCells[i], next),
          isTrue,
          reason: 'track $i ${trackCells[i]} -> $next is not adjacent',
        );
      }
    });

    test('start cells are the track cells at Board.startCells', () {
      for (final colour in PlayerColour.values) {
        final start = Board.startCells[colour]!;
        expect(trackCells[start], painterCell(colour, 1));
      }
    });
  });

  group('home paths (M3.5, D-20: 51 track + 4 home-path + home = 56)', () {
    test('each colour has exactly Board.homePathLength home-path cells', () {
      expect(Board.homePathLength, 4);
      for (final colour in PlayerColour.values) {
        expect(
          homePathCells(colour),
          hasLength(4),
          reason: '$colour home path must have 4 drawn cells, not 5',
        );
      }
    });

    test('home-path cells are distinct per colour and off the track', () {
      final track = trackCells.toSet();
      final seen = <math.Point<int>>{};
      for (final colour in PlayerColour.values) {
        for (final cell in homePathCells(colour)) {
          expect(
            track.contains(cell),
            isFalse,
            reason: '$cell is a track cell',
          );
          expect(seen.add(cell), isTrue, reason: '$cell drawn twice');
        }
      }
    });

    test('home-path entries are adjacent to their start cell', () {
      for (final colour in PlayerColour.values) {
        final start = trackCells[Board.startCells[colour]!];
        expect(
          adjacent(homePathCells(colour).first, start),
          isTrue,
          reason: '$colour home-path entry is not next to its start cell',
        );
      }
    });

    test('consecutive home-path cells are adjacent', () {
      for (final colour in PlayerColour.values) {
        final path = homePathCells(colour);
        for (var i = 0; i + 1 < path.length; i++) {
          expect(adjacent(path[i], path[i + 1]), isTrue);
        }
      }
    });

    test('the last home-path cell leads into home via the approach cell', () {
      for (final colour in PlayerColour.values) {
        final path = homePathCells(colour);
        final approach = homeApproachCell(colour);
        expect(adjacent(path.last, approach), isTrue);
        // The approach cell touches the 3x3 centre home.
        expect(
          approach.x >= 5 && approach.x <= 9,
          isTrue,
          reason: '$colour approach cell $approach is not next to the centre',
        );
        expect(approach.y >= 5 && approach.y <= 9, isTrue);
      }
    });

    test('every drawn home-path cell is reachable (no dead cells)', () {
      for (final colour in PlayerColour.values) {
        final path = homePathCells(colour);
        for (var i = 0; i < path.length; i++) {
          // Home-path index i is steps 52 + i.
          expect(
            painterCell(colour, 52 + i),
            _asDouble(path[i]),
            reason: '$colour home-path cell $i ${path[i]} is never occupied',
          );
        }
      }
    });
  });

  group('painter == engine equivalence (M3.5)', () {
    test(
      'token positions match the engine for every step 0..56 x every seat',
      () {
        for (final colour in PlayerColour.values) {
          for (var steps = 0; steps <= 56; steps++) {
            expect(
              painterCell(colour, steps),
              engineCell(colour, steps),
              reason: '$colour at step $steps: painter != engine',
            );
          }
        }
      },
    );

    test('token positions follow the chosen colour, not the seat', () {
      // FR-14 latent break: a token on seat 0 that picked green must
      // travel green's path (start 13), not red's (start 0).
      for (final colour in PlayerColour.values) {
        for (var steps = 0; steps <= 56; steps++) {
          expect(
            painterCell(colour, steps, seatIndex: 0, explicitColour: colour),
            engineCell(colour, steps),
            reason:
                'seat 0 with colour $colour at step $steps: painter != engine',
          );
        }
      }
    });

    test('yard and home tokens map to no track cell', () {
      for (final colour in PlayerColour.values) {
        expect(painterCell(colour, 0), isNull);
        expect(painterCell(colour, 56), isNull);
      }
    });
  });

  group('safe cells (M3.5, D-15)', () {
    test('safeTrackIndices default equals Board.safeCells', () {
      expect(Board.safeCells, {0, 8, 13, 21, 26, 34, 39, 47});
      final painter = LudoBoardPainter(
        tokens: [],
        legalTokenIds: {},
        currentSeat: 0,
      );
      expect(painter.safeTrackIndices, Board.safeCells);
    });
  });
}

math.Point<double> _asDouble(math.Point<int> cell) =>
    math.Point(cell.x.toDouble(), cell.y.toDouble());
