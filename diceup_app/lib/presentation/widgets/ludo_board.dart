import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../domain/engine/board.dart';
import '../../domain/engine/player_colour.dart';

/// Ludo board rendering (SDD §6.2, §11.4; SRS CON-01, FR-23).
///
/// The board is a 15x15 grid drawn with [CustomPainter]. Geometry lives
/// here — and only here — so the engine never knows about pixels.
/// The painter derives its logical geometry from the engine's [Board]
/// (M3.5, M-08): safe cells and start cells come from [Board], and
/// tokens are mapped by their chosen colour, not by `seatIndex * 13`
/// — so a colour swap (M2.2) moves the token's whole journey (yard,
/// start cell, home path). The pixel tables ([_trackCells],
/// [_homePaths], [_yardSlots]) stay in presentation as the pixel
/// mapping, guarded by the geometry tests in
/// `test/board_geometry_test.dart`.
///
/// Coordinate contract (agrees with the engine's [Board] in logical
/// track-index space — by derivation from [Board]):
/// * the 52-cell outer track is numbered clockwise from the red start
///   cell (track index 0). Start cells are indices 0 (red), 13 (green),
///   26 (yellow), 39 (blue). Safe cells are the 4 starts plus the 4 star
///   cells at indices 8, 21, 34, 47 (D-15 confirmed) — the painter draws
///   the stars from [safeTrackIndices], which defaults to
///   [Board.safeCells] (M3.5 derives them from [Board]).
/// * a token's [BoardToken.stepsTaken] is 0 in the yard, 1..51 on the
///   outer track (track index = (start + steps - 1) % 52), 52..55 on its
///   home path, and 56 means home (drawn in the centre) (D-20:
///   51 + 4 + 1 = 56).

/// Token data the board needs. The game screen adapts the engine's
/// [Token] into this. The painter imports only [Board] (pure geometry
/// constants); it never imports the engine's [Token] or game state.
class BoardToken {
  const BoardToken({
    required this.id,
    required this.seatIndex,
    required this.stepsTaken,
    this.colour,
  });

  final String id;
  final int seatIndex;

  /// 0 = yard, 1..56 = progress along the token's path (56 = home).
  final int stepsTaken;

  /// The token's chosen colour (M2.2). Null means "seat-order
  /// default" — older call sites omit it and render exactly as
  /// before. Deliberately excluded from equality: it is display
  /// data, and [boardTokenCenter] locates tokens by id/seat/steps.
  final PlayerColour? colour;

  /// The colour this token travels as: its chosen colour, or the
  /// seat-order default when none was chosen (M3.5). All board
  /// mapping keys off this, never off [seatIndex] — so a token whose
  /// seat picked green travels green's path even from seat 0.
  PlayerColour get effectiveColour =>
      colour ?? PlayerColour.values[seatIndex % PlayerColour.values.length];

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
  math.Point(6, 1),
  math.Point(6, 2),
  math.Point(6, 3),
  math.Point(6, 4),
  math.Point(6, 5),
  math.Point(5, 6),
  math.Point(4, 6),
  math.Point(3, 6),
  math.Point(2, 6),
  math.Point(1, 6),
  math.Point(0, 6),
  math.Point(0, 7),
  math.Point(0, 8),
  math.Point(1, 8),
  math.Point(2, 8),
  math.Point(3, 8),
  math.Point(4, 8),
  math.Point(5, 8),
  math.Point(6, 9),
  math.Point(6, 10),
  math.Point(6, 11),
  math.Point(6, 12),
  math.Point(6, 13),
  math.Point(6, 14),
  math.Point(7, 14),
  math.Point(8, 14),
  math.Point(8, 13),
  math.Point(8, 12),
  math.Point(8, 11),
  math.Point(8, 10),
  math.Point(8, 9),
  math.Point(9, 8),
  math.Point(10, 8),
  math.Point(11, 8),
  math.Point(12, 8),
  math.Point(13, 8),
  math.Point(14, 8),
  math.Point(14, 7),
  math.Point(14, 6),
  math.Point(13, 6),
  math.Point(12, 6),
  math.Point(11, 6),
  math.Point(10, 6),
  math.Point(9, 6),
  math.Point(8, 5),
  math.Point(8, 4),
  math.Point(8, 3),
  math.Point(8, 2),
  math.Point(8, 1),
  math.Point(8, 0),
  math.Point(7, 0),
  math.Point(6, 0),
];

/// Public read-only view of the painter's track table (M3.5): the
/// geometry tests pin the table's properties (52 unique cells, closed
/// loop) through this, so the painter's pixel mapping stays testable
/// without exposing the private table itself.
List<math.Point<int>> get trackCells => _trackCells;

/// Home-path cells drawn for [colour], in travel order (M3.5).
/// Keyed by colour, not seat: a token that picked green travels
/// green's path whatever seat it sits on.
List<math.Point<int>> homePathCells(PlayerColour colour) => _homePaths[colour]!;

/// The cell just past the end of [colour]'s home path, between the
/// last home-path cell and the centre home (M3.5). The former 5th
/// home-path cell (D-20), redrawn as part of home — it is not a
/// token cell and [boardCellForToken] never returns it.
math.Point<int> homeApproachCell(PlayerColour colour) =>
    _homeApproachCells[colour]!;

/// Home-path cells per colour, in travel order (M3.5, D-20).
/// Exactly [Board.homePathLength] (4) per colour: the 5th cell the
/// painter used to draw is gone — it was never occupied by the engine
/// (steps 52..55 are indices 0..3, step 56 is home). That cell is
/// redrawn as part of home instead (see [_homeApproachCells]).
const Map<PlayerColour, List<math.Point<int>>> _homePaths = {
  PlayerColour.red: [
    math.Point(7, 1),
    math.Point(7, 2),
    math.Point(7, 3),
    math.Point(7, 4),
  ],
  PlayerColour.green: [
    math.Point(1, 7),
    math.Point(2, 7),
    math.Point(3, 7),
    math.Point(4, 7),
  ],
  PlayerColour.yellow: [
    math.Point(7, 13),
    math.Point(7, 12),
    math.Point(7, 11),
    math.Point(7, 10),
  ],
  PlayerColour.blue: [
    math.Point(13, 7),
    math.Point(12, 7),
    math.Point(11, 7),
    math.Point(10, 7),
  ],
};

/// The former 5th home-path cell per colour (M3.5, D-20): the cell
/// between the last home-path cell and the centre home. It is drawn
/// in the seat's full colour as part of home — the home column flows
/// into the centre instead of ending one cell short — and it is NOT
/// a token cell: no token can ever occupy it.
const Map<PlayerColour, math.Point<int>> _homeApproachCells = {
  PlayerColour.red: math.Point(7, 5),
  PlayerColour.green: math.Point(5, 7),
  PlayerColour.yellow: math.Point(7, 9),
  PlayerColour.blue: math.Point(9, 7),
};

/// Track index → colour for the four start cells, derived from
/// [Board.startCells] (M3.5) so a start-cell change moves the tint
/// with it — no second copy of the mapping lives here.
final Map<int, PlayerColour> _colourByStartCell = {
  for (final entry in Board.startCells.entries) entry.value: entry.key,
};

/// Yard token slots per colour position (2x2 inside each yard),
/// indexed by [PlayerColour.index] (M3.5): the quadrants are fixed
/// colour positions — red top-left, green top-right, yellow
/// bottom-right, blue bottom-left — so a token yards with its
/// colour, not its seat. This coincides with seat order only for
/// the default colour assignment.
const List<List<math.Point<double>>> _yardSlots = [
  [
    math.Point(1.5, 1.5),
    math.Point(1.5, 3.5),
    math.Point(3.5, 1.5),
    math.Point(3.5, 3.5),
  ],
  [
    math.Point(10.5, 1.5),
    math.Point(10.5, 3.5),
    math.Point(12.5, 1.5),
    math.Point(12.5, 3.5),
  ],
  [
    math.Point(10.5, 10.5),
    math.Point(10.5, 12.5),
    math.Point(12.5, 10.5),
    math.Point(12.5, 12.5),
  ],
  [
    math.Point(1.5, 10.5),
    math.Point(1.5, 12.5),
    math.Point(3.5, 10.5),
    math.Point(3.5, 12.5),
  ],
];

/// Screen centre of a token inside a board of [size], using exactly the
/// same grouping math as [LudoBoardPainter] (yard slots, home cluster,
/// stacked tokens share a cell). The game screen uses this for tap
/// hit-testing; the painter never handles input itself.
/// Yard slots group by the token's colour (M3.5), not its seat.
Offset boardTokenCenter(
  BoardToken token,
  Size size,
  List<BoardToken> allTokens, [
  Board board = const Board(),
]) {
  final cell = size.width / 15;
  final cellPos = boardCellForToken(token, board);
  if (token.stepsTaken == 0) {
    // Yard: slot index among this colour's yard tokens, in list order.
    final yardTokens = allTokens
        .where(
          (t) =>
              t.effectiveColour == token.effectiveColour && t.stepsTaken == 0,
        )
        .toList();
    final slotIndex = yardTokens.indexOf(token);
    final slot = _yardSlots[token.effectiveColour.index][slotIndex % 4];
    return Offset((slot.y + 0.5) * cell, (slot.x + 0.5) * cell);
  }
  if (token.stepsTaken == 56) {
    final homeTokens = allTokens.where((t) => t.stepsTaken == 56).toList();
    final i = homeTokens.indexOf(token);
    return Offset(
      size.width / 2 + (i - homeTokens.length / 2) * cell * 0.55,
      size.height / 2,
    );
  }
  final centre = Offset((cellPos!.y + 0.5) * cell, (cellPos.x + 0.5) * cell);
  final sharing = allTokens
      .where(
        (t) =>
            t.stepsTaken > 0 &&
            t.stepsTaken < 56 &&
            boardCellForToken(t, board) == cellPos,
      )
      .toList();
  if (sharing.length == 1) return centre;
  final i = sharing.indexOf(token);
  return centre + stackOffset(i, sharing.length, cell);
}

/// Offset of one token among [count] sharing a cell (M3 premium,
/// research §2.2.5 — flutter_ludo fan-out). Two tokens keep the
/// existing horizontal fan; 3+ fan into a tiny 2x2 cluster inside
/// the cell, so no token is pushed outside it. Beyond 4 tokens the
/// slots repeat (overlap rather than leave the cell) — 5+ tokens on
/// one cell needs a capture to have failed, which the engine
/// forbids on non-safe cells, and safe cells cap at 4 same-colour
/// tokens plus visitors in practice.
Offset stackOffset(int index, int count, double cell) {
  if (count <= 1) return Offset.zero;
  if (count == 2) return Offset((index - 0.5) * cell * 0.4, 0);
  final dx = (index % 2 == 0 ? -1 : 1) * cell * 0.22;
  final dy = (index < 2 ? -1 : 1) * cell * 0.22;
  return Offset(dx, dy);
}

/// Grid cell of a token, or null when the token is in the yard or home.
/// Maps by the token's colour (M3.5), mirroring the engine's
/// [Board.cellAt] exactly: track index = (start + steps - 1) % 52,
/// home-path index = steps - 52 for steps 52..55, home at 56.
math.Point<double>? boardCellForToken(
  BoardToken token, [
  Board board = const Board(),
]) {
  final colour = token.effectiveColour;
  if (token.stepsTaken <= 0) return null; // yard — handled by _yardSlots
  if (token.stepsTaken <= Board.lastTrackStep) {
    final cell =
        _trackCells[(board.startCell(colour) + token.stepsTaken - 1) %
            Board.trackSize];
    return math.Point(cell.x.toDouble(), cell.y.toDouble());
  }
  if (token.stepsTaken <= Board.lastTrackStep + Board.homePathLength) {
    final cell = _homePaths[colour]![token.stepsTaken - 52];
    return math.Point(cell.x.toDouble(), cell.y.toDouble());
  }
  return null; // home — centre
}

class LudoBoardPainter extends CustomPainter {
  LudoBoardPainter({
    required this.tokens,
    required this.legalTokenIds,
    required this.currentSeat,
    this.board = const Board(),
    this.safeTrackIndices = Board.safeCells,
    // Legal-move pulse (M2.7, CON-01): 0..1, driven by the game
    // screen's 1,200 ms pulse controller — one cycle per legal-move
    // appearance — the legal ring's radius grows and its alpha fades
    // as [pulse] rises. Defaults to 0, which renders exactly the
    // static ring M2.3 drew, so existing call sites and tests keep
    // working.
    this.pulse = 0.0,
    // Token-hop override (M2.7, re-driven per cell in M3): while a
    // step sequence is in flight the screen animates one token's
    // *rendered* centre between two adjacent cells and passes it
    // here, one segment per step. The engine state is already final
    // — this only moves the drawing, never the game. Both null
    // means "draw every token at its computed centre". [hopScale]
    // is the per-step lift (1.0 at rest, ~1.12 mid-step).
    this.hopTokenId,
    this.hopCenter,
    this.hopScale = 1.0,
    // Capture-return override (M3 premium, research §2.3): while a
    // capture animation is in flight the captured token is drawn
    // at [captureCenter] — an arc from its cell to its yard slot —
    // at [captureScale] and [captureOpacity] (lift → shrink/fade →
    // arc → pop-in). The engine state is already final (the token
    // is in the yard); this only animates the return.
    this.captureTokenId,
    this.captureCenter,
    this.captureScale = 1.0,
    this.captureOpacity = 1.0,
    // Last-moved highlight (M3 premium, research §2.2.6): after a
    // move settles, a thin teal ring is drawn under the moved
    // token at [lastMovedOpacity] (1.0 → 0.0 over ~1.5 s), so
    // "where did it just go" is answerable after a fast AI move.
    // Null id (or 0.0 opacity) draws no ring.
    this.lastMovedTokenId,
    this.lastMovedOpacity = 0.0,
    // Illegal-tap shake (M3 premium, research §2.5.4): a tapped
    // token that cannot move shakes by [shakeOffset] (±1.5 dp,
    // two oscillations over ~150 ms). Null id draws no shake.
    this.shakeTokenId,
    this.shakeOffset = Offset.zero,
  });

  final List<BoardToken> tokens;
  final Set<String> legalTokenIds;
  final int currentSeat;

  /// The engine board this painter derives its logical geometry from
  /// (M3.5, M-08): start cells, safe cells and the home-path length.
  final Board board;
  final Set<int> safeTrackIndices;
  final double pulse;
  final String? hopTokenId;
  final Offset? hopCenter;
  final double hopScale;
  final String? captureTokenId;
  final Offset? captureCenter;
  final double captureScale;
  final double captureOpacity;
  final String? lastMovedTokenId;
  final double lastMovedOpacity;
  final String? shakeTokenId;
  final Offset shakeOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 15;
    final boardPaint = Paint()..style = PaintingStyle.fill;
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = DiceUpColors.border
      ..strokeWidth = 1;

    // Board background: warm ivory (Stage 2 redesign, F2) — the
    // board reads as an object on the navy table field, not a
    // white square on grey. Premium v2: the ivory falls away very
    // slightly toward the bottom-right (a lamp-lit surface), so the
    // board has depth before a single token is drawn. The gradient
    // stays inside the ivory token family (surface → ivoryAlt), so
    // every documented cell/star contrast in diceup_colors.dart
    // keeps holding.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DiceUpColors.surface, DiceUpColors.ivoryAlt],
        ).createShader(Offset.zero & size),
    );

    // Yards. Premium v2: the colour frame gains a shaded inner face
    // (deep band along the bottom/right, like a lit tray), the ivory
    // inner panel is rounded, and each yard slot gets a pedestal
    // socket — a waiting token sits in a seat instead of on a blank
    // slab, and an empty socket reads as an invitation. Occupied
    // sockets disappear under their token (the token radius is a
    // hair larger than the socket ring).
    for (var seat = 0; seat < 4; seat++) {
      final yardRect = _yardRect(seat, cell);
      final frameColour = DiceUpColors.playerColor(seat);
      boardPaint.color = frameColour;
      canvas.drawRect(yardRect, boardPaint);
      // Shaded inner face: one deep line along the bottom and right
      // edges of the frame, a step darker than the frame colour.
      final deepEdge = _deepen(frameColour, 0.18);
      final inset = yardRect.deflate(cell * 0.18);
      final edgePaint = Paint()
        ..color = deepEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.36;
      canvas.drawLine(
        Offset(inset.left + cell * 0.18, inset.bottom),
        Offset(inset.right, inset.bottom),
        edgePaint,
      );
      canvas.drawLine(
        Offset(inset.right, inset.top + cell * 0.18),
        Offset(inset.right, inset.bottom),
        edgePaint,
      );
      // Rounded ivory inner panel.
      final inner = yardRect.deflate(cell * 1.1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(inner, Radius.circular(cell * 0.6)),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [DiceUpColors.surface, DiceUpColors.ivoryAlt],
          ).createShader(inner),
      );
      // Pedestal sockets, one per yard slot (slot coordinates are
      // grid doubles — see [_yardSlots]; the same centres the tokens
      // render at, so a token covers its socket exactly).
      for (final slot in _yardSlots[seat]) {
        final socketCentre = Offset(
          (slot.y + 0.5) * cell,
          (slot.x + 0.5) * cell,
        );
        canvas.drawCircle(
          socketCentre,
          cell * 0.42,
          Paint()..color = DiceUpColors.ivoryAlt,
        );
        canvas.drawCircle(
          socketCentre,
          cell * 0.42,
          Paint()
            ..color = DiceUpColors.border
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
    // Current-seat yard glow (Stage 2 turn system, F3): a teal
    // outline around the current player's yard only, drawn from
    // [currentSeat] — the board-anchored turn signal, in the
    // action colour regardless of seat, so the signal is "this
    // seat's turn", not "this colour is special". The quadrant is
    // the current player's COLOUR quadrant, not their seat
    // quadrant: yards are colour-keyed positions (M3.5), so after
    // a colour swap the seat-order quadrant is the wrong yard —
    // e.g. seat 0 playing blue yards bottom-left, and a glow
    // around the top-left (red) yard would mark the wrong player.
    var currentColourIndex = currentSeat;
    for (final token in tokens) {
      if (token.seatIndex == currentSeat) {
        currentColourIndex = token.effectiveColour.index;
        break;
      }
    }
    canvas.drawRect(
      _yardRect(currentColourIndex, cell).deflate(1),
      Paint()
        ..color = DiceUpColors.teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Track + home-path cells.
    for (var i = 0; i < 52; i++) {
      _drawCell(canvas, _trackCells[i], cell, gridPaint, boardPaint, i);
    }
    for (final colour in PlayerColour.values) {
      for (final cellPos in _homePaths[colour]!) {
        // Home paths in FULL colour (Stage 2, F2): the audit found
        // them at 0.55 alpha — the most meaningful cells were the
        // palest. Full colour makes them the strongest, not the
        // palest, on the board.
        boardPaint.color = DiceUpColors.forColour(colour);
        canvas.drawRect(_cellRect(cellPos, cell), boardPaint);
        canvas.drawRect(_cellRect(cellPos, cell), gridPaint);
      }
      // The former 5th home-path cell (D-20): part of home, in the
      // seat's full colour — never a token cell.
      boardPaint.color = DiceUpColors.forColour(colour);
      canvas.drawRect(_cellRect(_homeApproachCells[colour]!, cell), boardPaint);
    }

    // Centre home: four triangles, one per seat.
    _drawCentre(canvas, size, cell);

    // Tokens, grouped by cell so stacked tokens share visibly.
    final byCell = <String, List<BoardToken>>{};
    for (final token in tokens) {
      final cellPos = boardCellForToken(token, board);
      final key = cellPos == null
          ? (token.stepsTaken == 0
                ? 'yard-${token.effectiveColour.index}'
                : 'home')
          : '${cellPos.x},${cellPos.y}';
      (byCell[key] ??= []).add(token);
    }
    byCell.forEach((key, group) {
      if (key.startsWith('yard-')) {
        final colourIndex = int.parse(key.split('-').last);
        for (var i = 0; i < group.length; i++) {
          final slot = _yardSlots[colourIndex][i % 4];
          _drawToken(
            canvas,
            _centreFor(
              group[i],
              Offset((slot.y + 0.5) * cell, (slot.x + 0.5) * cell),
            ),
            cell,
            group[i],
            scale: _scaleFor(group[i]),
            opacity: _opacityFor(group[i]),
          );
        }
      } else if (key == 'home') {
        // Home tokens cluster in the centre.
        for (var i = 0; i < group.length; i++) {
          _drawToken(
            canvas,
            _centreFor(
              group[i],
              Offset(
                size.width / 2 + (i - group.length / 2) * cell * 0.55,
                size.height / 2,
              ),
            ),
            cell,
            group[i],
            scale: _scaleFor(group[i]),
            opacity: _opacityFor(group[i]),
          );
        }
      } else {
        final parts = key.split(',');
        final centre = Offset(
          (double.parse(parts[1]) + 0.5) * cell,
          (double.parse(parts[0]) + 0.5) * cell,
        );
        for (var i = 0; i < group.length; i++) {
          final offset = stackOffset(i, group.length, cell);
          _drawToken(
            canvas,
            _centreFor(group[i], centre + offset),
            cell,
            group[i],
            scale: _scaleFor(group[i]),
            opacity: _opacityFor(group[i]),
          );
        }
      }
    });
  }

  /// The centre a token is drawn at: the step override when this is
  /// the moving token and a step is in flight, the capture override
  /// when this is the captured token, the shake offset when this is
  /// the illegally tapped token, else the computed centre. The
  /// overrides are rendering-only — the token's engine position
  /// (and the hit-test geometry in [boardTokenCenter]) already sit
  /// at the destination cell.
  Offset _centreFor(BoardToken token, Offset computed) {
    final hop = hopCenter;
    if (hop != null && token.id == hopTokenId) return hop;
    final capture = captureCenter;
    if (capture != null && token.id == captureTokenId) return capture;
    if (token.id == shakeTokenId) return computed + shakeOffset;
    return computed;
  }

  /// The draw scale for a token: the per-step lift for the moving
  /// token, the shrink/pop for the captured token, a slight lift
  /// (~1.06) for a legal token at rest — so a legal token reads as
  /// a piece that can be picked up even after the one-shot pulse
  /// has finished — and 1.0 otherwise.
  double _scaleFor(BoardToken token) {
    if (token.id == hopTokenId && hopCenter != null) return hopScale;
    if (token.id == captureTokenId && captureCenter != null) {
      return captureScale;
    }
    if (legalTokenIds.contains(token.id)) return 1.06;
    return 1.0;
  }

  /// The draw opacity for a token: the fade for the captured token,
  /// 1.0 otherwise.
  double _opacityFor(BoardToken token) {
    if (token.id == captureTokenId && captureCenter != null) {
      return captureOpacity;
    }
    return 1.0;
  }

  Rect _yardRect(int seat, double cell) {
    return switch (seat) {
      0 => Rect.fromLTWH(0, 0, 6 * cell, 6 * cell),
      1 => Rect.fromLTWH(9 * cell, 0, 6 * cell, 6 * cell),
      2 => Rect.fromLTWH(9 * cell, 9 * cell, 6 * cell, 6 * cell),
      _ => Rect.fromLTWH(0, 9 * cell, 6 * cell, 6 * cell),
    };
  }

  Rect _cellRect(math.Point<int> cellPos, double cell) =>
      Rect.fromLTWH(cellPos.y * cell, cellPos.x * cell, cell, cell);

  void _drawCell(
    Canvas canvas,
    math.Point<int> cellPos,
    double cell,
    Paint gridPaint,
    Paint fillPaint,
    int trackIndex,
  ) {
    final rect = _cellRect(cellPos, cell);
    // Start cells get their seat colour at FULL strength (Stage 2,
    // F2 — the audit found them at 0.35 alpha), looked up from
    // [Board] (M3.5) — never `trackIndex ~/ 13`. A start cell is
    // also a safe cell, so it keeps its star: a white star with a
    // navy outline, readable on every player colour including
    // yellow (white on yellow is 2.38:1; the navy outline is what
    // separates the star from the yellow fill).
    final startColour = _colourByStartCell[trackIndex];
    if (startColour != null) {
      fillPaint.color = DiceUpColors.forColour(startColour);
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, gridPaint);
      _drawStar(
        canvas,
        rect.center,
        cell * 0.28,
        Paint()..color = Colors.white,
        outline: Paint()
          ..color = DiceUpColors.navy
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      return;
    }
    if (safeTrackIndices.contains(trackIndex)) {
      // Safe cells (Stage 2, F2): the audit's amber star on
      // amberLight measured 2.86:1. The fill is now the ivory
      // board surface and the star is amber on it (3.19:1 — above
      // the 3:1 floor for a non-text marker), reinforced by an
      // amber ring around the cell, so the safe marker no longer
      // depends on a pale fill. The fill stays [DiceUpColors.
      // surface] (not the v2 alternate ivory) so the documented
      // 3.19:1 figure keeps holding verbatim.
      fillPaint.color = DiceUpColors.surface;
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(
        rect.deflate(0.75),
        Paint()
          ..color = DiceUpColors.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      _drawStar(
        canvas,
        rect.center,
        cell * 0.28,
        Paint()..color = DiceUpColors.amber,
      );
    } else {
      // Premium v2: regular cells alternate between the two ivory
      // tokens (surface / ivoryAlt), giving the track a quiet
      // checker rhythm. Start cells and safe cells keep their
      // documented fills and markers above.
      fillPaint.color = trackIndex.isEven
          ? DiceUpColors.surface
          : DiceUpColors.ivoryAlt;
      canvas.drawRect(rect, fillPaint);
    }
    canvas.drawRect(rect, gridPaint);
  }

  void _drawStar(
    Canvas canvas,
    Offset centre,
    double radius,
    Paint paint, {
    Paint? outline,
  }) {
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
    if (outline != null) canvas.drawPath(path, outline);
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
      canvas.drawPath(path, Paint()..color = DiceUpColors.playerColor(seat));
      // A thin ivory seam between the triangles, so the four
      // home colours read as four pieces meeting in the centre
      // rather than one flat block.
      canvas.drawPath(
        path,
        Paint()
          ..color = DiceUpColors.surface
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    // Premium v2: a hairline of deep navy around the whole 3x3
    // home square, so the centre reads as one finished piece set
    // into the board (and the four triangles gain an edge against
    // the ivory track cells around them).
    canvas.drawRect(
      Rect.fromCenter(
        center: centre,
        width: half * 2,
        height: half * 2,
      ),
      Paint()
        ..color = DiceUpColors.navy.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  void _drawToken(
    Canvas canvas,
    Offset centre,
    double cell,
    BoardToken token, {
    double scale = 1.0,
    double opacity = 1.0,
  }) {
    // The token dot takes the player's *chosen* colour (M2.2); the
    // board geometry itself (yards, start cells, home paths) is
    // keyed by colour too (M3.5) — the quadrants are fixed colour
    // positions, and a token's yard, start cell and home path all
    // follow its colour.
    final color = token.colour == null
        ? DiceUpColors.playerColor(token.seatIndex)
        : DiceUpColors.forColour(token.colour!);
    final radius = cell * 0.36 * scale;
    // Legal-move highlight: amber ring + slight lift (FR-17). The
    // ring pulses with [pulse] (M2.7): its radius grows and its
    // alpha fades as the pulse rises; at pulse 0 it is the static
    // ring as before.
    if (legalTokenIds.contains(token.id)) {
      canvas.drawCircle(
        centre,
        radius + 3 + pulse * 2.5,
        Paint()
          ..color = DiceUpColors.amber.withValues(alpha: 1.0 - pulse * 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
    // Last-moved highlight (M3 premium, §2.2.6): a thin teal ring
    // under the moved token, fading with [lastMovedOpacity]. It is
    // drawn for the token the screen names, never for a token that
    // is currently stepping or being captured (those carry their
    // own overrides).
    if (token.id == lastMovedTokenId &&
        lastMovedOpacity > 0.0 &&
        token.id != hopTokenId &&
        token.id != captureTokenId) {
      canvas.drawCircle(
        centre,
        radius + 3,
        Paint()
          ..color = DiceUpColors.teal.withValues(alpha: lastMovedOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    // Token body. Shape differs per seat so players are distinguishable
    // by more than colour (NFR-08): circle, square, diamond, triangle.
    // Depth: a soft offset shadow under the piece and a small top-left
    // highlight, so tokens read as game pieces sitting on the board
    // rather than flat dots (Stage 2, F2). Premium v2 upgrades the
    // body itself to a lit dome — see the paint notes below. The
    // shadow and highlight follow the token's scale and opacity, so
    // a hopping or captured token keeps its depth through the
    // animation.
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.22 * opacity);
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.38 * opacity);
    final shadowCentre = centre + Offset(0, radius * 0.18);
    // Premium v2 body: a lit dome — the token's colour falling from
    // a light top-left to a deep base, with a deep under-rim between
    // the fill and the white edge. The shape (seat circle/square/
    // diamond/triangle), the radius formula and the legal/current
    // rings are unchanged — the piece simply reads as a polished
    // game stone instead of a flat dot. The shadow, gradient and
    // rim all follow [scale] and [opacity], so a hopping or captured
    // token keeps its depth through the animation.
    final fill = Paint()
      ..shader = RadialGradient(
        center: const Offset(0.32, 0.28),
        radius: 1.1,
        colors: [
          _lighten(color, 0.22).withValues(alpha: opacity),
          color.withValues(alpha: opacity),
          _deepen(color, 0.22).withValues(alpha: opacity),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    final deepRim = Paint()
      ..color = _deepen(color, 0.32).withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.16;
    final edge = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // Builds the token's shape path for the given centre/radius,
    // so the shadow, fill, edge and highlight all share one shape.
    Path shapePath(Offset at, double r) {
      switch (token.seatIndex % 4) {
        case 1:
          return Path()..addRect(Rect.fromCircle(center: at, radius: r * 0.92));
        case 2:
          return Path()
            ..moveTo(at.dx, at.dy - r)
            ..lineTo(at.dx + r, at.dy)
            ..lineTo(at.dx, at.dy + r)
            ..lineTo(at.dx - r, at.dy)
            ..close();
        case 3:
          return Path()
            ..moveTo(at.dx, at.dy - r)
            ..lineTo(at.dx + r, at.dy + r * 0.8)
            ..lineTo(at.dx - r, at.dy + r * 0.8)
            ..close();
        default:
          return Path()..addOval(Rect.fromCircle(center: at, radius: r));
      }
    }

    canvas.drawPath(shapePath(shadowCentre, radius * 0.95), shadow);
    canvas.drawPath(shapePath(centre, radius), fill);
    canvas.drawPath(shapePath(centre, radius * 0.985), deepRim);
    canvas.drawPath(shapePath(centre, radius), edge);
    canvas.drawCircle(
      centre + Offset(-radius * 0.32, -radius * 0.32),
      radius * 0.26,
      highlight,
    );
    // Current-player marker (Stage 2 turn system, F3): the old
    // small white dot inside the token is gone. A token of the
    // current player now carries a teal ring — the same action
    // colour as the yard glow, the banner accent and the chip
    // turn badge — so the turn signal is one system in three
    // places, and the marker is a ring + shape cue (the token's
    // own shape), never colour alone.
    if (token.seatIndex == currentSeat) {
      canvas.drawCircle(
        centre,
        radius + 1.5,
        Paint()
          ..color = DiceUpColors.teal.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  /// Content-based repaint (M2.7, NFR-02): the board repaints only
  /// when what it draws actually changed. The old version compared
  /// the token list and the legal-move set by identity, so a new
  /// list (which the screen builds on every rebuild) always
  /// repainted. [BoardToken] implements value equality (its
  /// `colour` is deliberately excluded — see its doc — so a
  /// colour-only change does not repaint; no mid-match colour
  /// change exists, colours are chosen at setup), and sets compare
  /// by contents.
  @override
  bool shouldRepaint(covariant LudoBoardPainter oldDelegate) {
    return oldDelegate.currentSeat != currentSeat ||
        oldDelegate.board != board ||
        oldDelegate.pulse != pulse ||
        oldDelegate.hopTokenId != hopTokenId ||
        oldDelegate.hopCenter != hopCenter ||
        oldDelegate.hopScale != hopScale ||
        oldDelegate.captureTokenId != captureTokenId ||
        oldDelegate.captureCenter != captureCenter ||
        oldDelegate.captureScale != captureScale ||
        oldDelegate.captureOpacity != captureOpacity ||
        oldDelegate.lastMovedTokenId != lastMovedTokenId ||
        oldDelegate.lastMovedOpacity != lastMovedOpacity ||
        oldDelegate.shakeTokenId != shakeTokenId ||
        oldDelegate.shakeOffset != shakeOffset ||
        !listEquals(oldDelegate.tokens, tokens) ||
        !setEquals(oldDelegate.legalTokenIds, legalTokenIds) ||
        !setEquals(oldDelegate.safeTrackIndices, safeTrackIndices);
  }
}

/// Lightens [colour] toward white by [amount] (0..1) — the gloss end
/// of the painter's lit pieces. Helper for [LudoBoardPainter] only.
Color _lighten(Color colour, double amount) =>
    Color.lerp(colour, Colors.white, amount)!;

/// Deepens [colour] toward a warm near-black by [amount] (0..1) —
/// the shaded end of the painter's lit pieces. Lerping toward a warm
/// dark brown (not pure black) keeps yellows and greens saturated
/// instead of muddy.
Color _deepen(Color colour, double amount) =>
    Color.lerp(colour, const Color(0xFF2A1608), amount)!;
