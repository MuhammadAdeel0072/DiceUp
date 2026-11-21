import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';

/// Ludo board rendering (SDD §6.2, §11.4; SRS CON-01, FR-23).
///
/// The board is a 15x15 grid drawn with [CustomPainter]. Geometry lives
/// here — and only here — so the engine never knows about pixels.
/// (The painter duplicates the engine's rule geometry — safe cells, start
/// cells, home-path layout — instead of deriving it from [Board] (M-08);
/// M3.5 derives it from [Board].)
///
/// Coordinate contract (agrees with the engine's [Board] in logical
/// track-index space — by duplication, not derivation):
/// * the 52-cell outer track is numbered clockwise from the red start
///   cell (track index 0). Start cells are indices 0 (red), 13 (green),
///   26 (yellow), 39 (blue). Safe cells are the 4 starts plus the 4 star
///   cells at indices 8, 21, 34, 47 (D-15 confirmed) — the painter draws
///   the stars from [safeTrackIndices], which defaults to the same set
///   but is a separate copy: no caller passes it, so a ruleset change
///   does NOT move the markers today (M3.5 derives them from [Board]).
/// * a token's [BoardToken.stepsTaken] is 0 in the yard, 1..51 on the
///   outer track (track index = (start + steps - 1) % 52), 52..55 on its
///   home path, and 56 means home (drawn in the centre) (D-20:
///   51 + 4 + 1 = 56).

/// Token data the board needs. The game screen adapts the engine's
/// [Token] into this — the painter never imports the engine.
class BoardToken {
  const BoardToken({
    required this.id,
    required this.seatIndex,
    required this.stepsTaken,
  });

  final String id;
  final int seatIndex;

  /// 0 = yard, 1..56 = progress along the token's path (56 = home).
  final int stepsTaken;

  // Value equality: [boardTokenCenter] locates a token among its peers
  // with List.indexOf, which needs this (an earlier version silently
  // returned -1 and mapped every yard token to the same slot).
  @override
  bool operator ==(Object other) =>
      other is BoardToken &&
      id == other.id &&
      seatIndex == other.seatIndex &&
      stepsTaken == other.stepsTaken;

  @override
  int get hashCode => Object.hash(id, seatIndex, stepsTaken);
}

/// 15x15-grid position of every track cell, clockwise from red start.
const List<math.Point<int>> _trackCells = [
  math.Point(6, 1), math.Point(6, 2), math.Point(6, 3), math.Point(6, 4), math.Point(6, 5),
  math.Point(5, 6), math.Point(4, 6), math.Point(3, 6), math.Point(2, 6), math.Point(1, 6),
  math.Point(0, 6), math.Point(0, 7), math.Point(0, 8), math.Point(1, 8), math.Point(2, 8),
  math.Point(3, 8), math.Point(4, 8), math.Point(5, 8), math.Point(6, 9), math.Point(6, 10),
  math.Point(6, 11), math.Point(6, 12), math.Point(6, 13), math.Point(6, 14), math.Point(7, 14),
  math.Point(8, 14), math.Point(8, 13), math.Point(8, 12), math.Point(8, 11), math.Point(8, 10),
  math.Point(8, 9), math.Point(9, 8), math.Point(10, 8), math.Point(11, 8), math.Point(12, 8),
  math.Point(13, 8), math.Point(14, 8), math.Point(14, 7), math.Point(14, 6), math.Point(13, 6),
  math.Point(12, 6), math.Point(11, 6), math.Point(10, 6), math.Point(9, 6), math.Point(8, 5),
  math.Point(8, 4), math.Point(8, 3), math.Point(8, 2), math.Point(8, 1), math.Point(8, 0),
  math.Point(7, 0), math.Point(6, 0),
];

/// Home-path cells per seat (red, green, yellow, blue), in travel order.
const List<List<math.Point<int>>> _homePaths = [
  [math.Point(7, 1), math.Point(7, 2), math.Point(7, 3), math.Point(7, 4), math.Point(7, 5)],
  [math.Point(1, 7), math.Point(2, 7), math.Point(3, 7), math.Point(4, 7), math.Point(5, 7)],
  [math.Point(7, 13), math.Point(7, 12), math.Point(7, 11), math.Point(7, 10), math.Point(7, 9)],
  [math.Point(13, 7), math.Point(12, 7), math.Point(11, 7), math.Point(10, 7), math.Point(9, 7)],
];

/// Yard token slots per seat (2x2 inside each yard).
const List<List<math.Point<double>>> _yardSlots = [
  [math.Point(1.5, 1.5), math.Point(1.5, 3.5), math.Point(3.5, 1.5), math.Point(3.5, 3.5)],
  [math.Point(10.5, 1.5), math.Point(10.5, 3.5), math.Point(12.5, 1.5), math.Point(12.5, 3.5)],
  [math.Point(10.5, 10.5), math.Point(10.5, 12.5), math.Point(12.5, 10.5), math.Point(12.5, 12.5)],
  [math.Point(1.5, 10.5), math.Point(1.5, 12.5), math.Point(3.5, 10.5), math.Point(3.5, 12.5)],
];

/// Screen centre of a token inside a board of [size], using exactly the
/// same grouping math as [LudoBoardPainter] (yard slots, home cluster,
/// stacked tokens share a cell). The game screen uses this for tap
/// hit-testing; the painter never handles input itself.
Offset boardTokenCenter(
  BoardToken token,
  Size size,
  List<BoardToken> allTokens,
) {
  final cell = size.width / 15;
  final cellPos = boardCellForToken(token);
  if (token.stepsTaken == 0) {
    // Yard: slot index among this seat's yard tokens, in list order.
    final yardTokens = allTokens
        .where((t) => t.seatIndex == token.seatIndex && t.stepsTaken == 0)
        .toList();
    final slotIndex = yardTokens.indexOf(token);
    final slot = _yardSlots[token.seatIndex][slotIndex % 4];
    return Offset((slot.y + 0.5) * cell, (slot.x + 0.5) * cell);
  }
  if (token.stepsTaken == 56) {
    final homeTokens =
        allTokens.where((t) => t.stepsTaken == 56).toList();
    final i = homeTokens.indexOf(token);
    return Offset(
      size.width / 2 + (i - homeTokens.length / 2) * cell * 0.55,
      size.height / 2,
    );
  }
  final centre = Offset(
    (cellPos!.y + 0.5) * cell,
    (cellPos.x + 0.5) * cell,
  );
  final sharing = allTokens
      .where(
        (t) =>
            t.stepsTaken > 0 &&
            t.stepsTaken < 56 &&
            boardCellForToken(t) == cellPos,
      )
      .toList();
  if (sharing.length == 1) return centre;
  final i = sharing.indexOf(token);
  return centre + Offset((i - (sharing.length - 1) / 2) * cell * 0.4, 0);
}

/// Grid cell of a token, or null when the token is home (centre).
math.Point<double>? boardCellForToken(BoardToken token) {
  final start = token.seatIndex * 13;
  if (token.stepsTaken <= 0) return null; // yard — handled by _yardSlots
  if (token.stepsTaken <= 51) {
    final cell = _trackCells[(start + token.stepsTaken - 1) % 52];
    return math.Point(cell.x.toDouble(), cell.y.toDouble());
  }
  if (token.stepsTaken < 56) {
    final cell = _homePaths[token.seatIndex][token.stepsTaken - 52];
    return math.Point(cell.x.toDouble(), cell.y.toDouble());
  }
  return null; // home — centre
}

class LudoBoardPainter extends CustomPainter {
  LudoBoardPainter({
    required this.tokens,
    required this.legalTokenIds,
    required this.currentSeat,
    this.safeTrackIndices = const {0, 8, 13, 21, 26, 34, 39, 47},
  });

  final List<BoardToken> tokens;
  final Set<String> legalTokenIds;
  final int currentSeat;
  final Set<int> safeTrackIndices;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 15;
    final boardPaint = Paint()..style = PaintingStyle.fill;
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = DiceUpColors.border
      ..strokeWidth = 1;

    // Board background.
    boardPaint.color = Colors.white;
    canvas.drawRect(Offset.zero & size, boardPaint);

    // Yards.
    for (var seat = 0; seat < 4; seat++) {
      final yardRect = _yardRect(seat, cell);
      boardPaint.color = DiceUpColors.playerColor(seat);
      canvas.drawRect(yardRect, boardPaint);
      boardPaint.color = Colors.white;
      canvas.drawRect(yardRect.deflate(cell * 1.1), boardPaint);
    }

    // Track + home-path cells.
    for (var i = 0; i < 52; i++) {
      _drawCell(canvas, _trackCells[i], cell, gridPaint, boardPaint, i);
    }
    for (var seat = 0; seat < 4; seat++) {
      for (final cellPos in _homePaths[seat]) {
        boardPaint.color =
            DiceUpColors.playerColor(seat).withValues(alpha: 0.55);
        canvas.drawRect(_cellRect(cellPos, cell), boardPaint);
        canvas.drawRect(_cellRect(cellPos, cell), gridPaint);
      }
    }

    // Centre home: four triangles, one per seat.
    _drawCentre(canvas, size, cell);

    // Tokens, grouped by cell so stacked tokens share visibly.
    final byCell = <String, List<BoardToken>>{};
    for (final token in tokens) {
      final cellPos = boardCellForToken(token);
      final key = cellPos == null
          ? (token.stepsTaken == 0 ? 'yard-${token.seatIndex}' : 'home')
          : '${cellPos.x},${cellPos.y}';
      (byCell[key] ??= []).add(token);
    }
    byCell.forEach((key, group) {
      if (key.startsWith('yard-')) {
        final seat = int.parse(key.split('-').last);
        for (var i = 0; i < group.length; i++) {
          final slot = _yardSlots[seat][i % 4];
          _drawToken(
            canvas,
            Offset((slot.y + 0.5) * cell, (slot.x + 0.5) * cell),
            cell,
            group[i],
          );
        }
      } else if (key == 'home') {
        // Home tokens cluster in the centre.
        for (var i = 0; i < group.length; i++) {
          _drawToken(
            canvas,
            Offset(size.width / 2 + (i - group.length / 2) * cell * 0.55,
                size.height / 2),
            cell,
            group[i],
          );
        }
      } else {
        final parts = key.split(',');
        final centre = Offset(
          (double.parse(parts[1]) + 0.5) * cell,
          (double.parse(parts[0]) + 0.5) * cell,
        );
        for (var i = 0; i < group.length; i++) {
          final offset = group.length == 1
              ? Offset.zero
              : Offset((i - (group.length - 1) / 2) * cell * 0.4, 0);
          _drawToken(canvas, centre + offset, cell, group[i]);
        }
      }
    });
  }

  Rect _yardRect(int seat, double cell) {
    return switch (seat) {
      0 => Rect.fromLTWH(0, 0, 6 * cell, 6 * cell),
      1 => Rect.fromLTWH(9 * cell, 0, 6 * cell, 6 * cell),
      2 => Rect.fromLTWH(9 * cell, 9 * cell, 6 * cell, 6 * cell),
      _ => Rect.fromLTWH(0, 9 * cell, 6 * cell, 6 * cell),
    };
  }

  Rect _cellRect(math.Point<int> cellPos, double cell) => Rect.fromLTWH(
        cellPos.y * cell,
        cellPos.x * cell,
        cell,
        cell,
      );

  void _drawCell(
    Canvas canvas,
    math.Point<int> cellPos,
    double cell,
    Paint gridPaint,
    Paint fillPaint,
    int trackIndex,
  ) {
    final rect = _cellRect(cellPos, cell);
    if (safeTrackIndices.contains(trackIndex)) {
      fillPaint.color = DiceUpColors.amberLight;
      canvas.drawRect(rect, fillPaint);
      // Star marker for safe cells (FR-23: safe cells visibly marked).
      _drawStar(
        canvas,
        rect.center,
        cell * 0.28,
        Paint()..color = DiceUpColors.amber,
      );
    } else {
      fillPaint.color = Colors.white;
      canvas.drawRect(rect, fillPaint);
    }
    canvas.drawRect(rect, gridPaint);
    // Start cells get their seat colour.
    if (trackIndex % 13 == 0) {
      fillPaint.color =
          DiceUpColors.playerColor(trackIndex ~/ 13).withValues(alpha: 0.35);
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, gridPaint);
    }
  }

  void _drawStar(Canvas canvas, Offset centre, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? radius : radius * 0.45;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = centre + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawCentre(Canvas canvas, Size size, double cell) {
    final centre = Offset(size.width / 2, size.height / 2);
    final half = 1.5 * cell;
    final corners = [
      centre + Offset(-half, -half),
      centre + Offset(half, -half),
      centre + Offset(half, half),
      centre + Offset(-half, half),
    ];
    for (var seat = 0; seat < 4; seat++) {
      final path = Path()
        ..moveTo(centre.dx, centre.dy)
        ..lineTo(corners[seat].dx, corners[seat].dy)
        ..lineTo(corners[(seat + 1) % 4].dx, corners[(seat + 1) % 4].dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = DiceUpColors.playerColor(seat),
      );
    }
  }

  void _drawToken(Canvas canvas, Offset centre, double cell, BoardToken token) {
    final color = DiceUpColors.playerColor(token.seatIndex);
    final radius = cell * 0.36;
    // Legal-move highlight: amber ring + slight lift (FR-17).
    if (legalTokenIds.contains(token.id)) {
      canvas.drawCircle(
        centre,
        radius + 3,
        Paint()
          ..color = DiceUpColors.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    // Token body. Shape differs per seat so players are distinguishable
    // by more than colour (NFR-08): circle, square, diamond, triangle.
    final fill = Paint()..color = color;
    final edge = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    switch (token.seatIndex % 4) {
      case 0:
        canvas.drawCircle(centre, radius, fill);
        canvas.drawCircle(centre, radius, edge);
      case 1:
        final rect = Rect.fromCircle(center: centre, radius: radius * 0.92);
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, edge);
      case 2:
        final diamond = Path()
          ..moveTo(centre.dx, centre.dy - radius)
          ..lineTo(centre.dx + radius, centre.dy)
          ..lineTo(centre.dx, centre.dy + radius)
          ..lineTo(centre.dx - radius, centre.dy)
          ..close();
        canvas.drawPath(diamond, fill);
        canvas.drawPath(diamond, edge);
      default:
        final triangle = Path()
          ..moveTo(centre.dx, centre.dy - radius)
          ..lineTo(centre.dx + radius, centre.dy + radius * 0.8)
          ..lineTo(centre.dx - radius, centre.dy + radius * 0.8)
          ..close();
        canvas.drawPath(triangle, fill);
        canvas.drawPath(triangle, edge);
    }
    // Current-player marker.
    if (token.seatIndex == currentSeat) {
      canvas.drawCircle(
        centre,
        radius * 0.45,
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant LudoBoardPainter oldDelegate) {
    return oldDelegate.tokens != tokens ||
        oldDelegate.legalTokenIds != legalTokenIds ||
        oldDelegate.currentSeat != currentSeat;
  }
}
