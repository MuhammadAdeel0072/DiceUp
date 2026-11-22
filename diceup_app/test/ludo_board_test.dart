import 'package:diceup/presentation/widgets/ludo_board.dart';
import 'package:flutter_test/flutter_test.dart';

/// M2.7 (CON-01, NFR-02): content-based [LudoBoardPainter.shouldRepaint]
/// and the new painter parameters ([LudoBoardPainter.pulse],
/// [LudoBoardPainter.hopTokenId]/[LudoBoardPainter.hopCenter]).
///
/// The shouldRepaint tests use fresh (non-const) lists and sets on
/// each call: the old implementation compared them by identity, so
/// equal-but-new content repainted — these tests fail against it
/// (same content → true) and pass with the content comparison.
void main() {
  List<BoardToken> tokens({int firstSteps = 0, int secondSteps = 0}) => [
    BoardToken(id: '0:0', seatIndex: 0, stepsTaken: firstSteps),
    BoardToken(id: '0:1', seatIndex: 0, stepsTaken: secondSteps),
  ];

  LudoBoardPainter painter({
    List<BoardToken>? tokenList,
    Set<String>? legalTokenIds,
    int currentSeat = 0,
    Set<int>? safeTrackIndices,
    double pulse = 0.0,
    String? hopTokenId,
    Offset? hopCenter,
  }) => LudoBoardPainter(
    tokens: tokenList ?? tokens(),
    legalTokenIds: legalTokenIds ?? {'0:0'},
    currentSeat: currentSeat,
    safeTrackIndices: safeTrackIndices ?? const {0, 8, 13, 21, 26, 34, 39, 47},
    pulse: pulse,
    hopTokenId: hopTokenId,
    hopCenter: hopCenter,
  );

  group('shouldRepaint (M2.7, content-based)', () {
    test('equal content in fresh lists and sets does not repaint', () {
      final oldDelegate = painter();
      final newDelegate = painter();
      expect(newDelegate.shouldRepaint(oldDelegate), isFalse);
    });

    test('a token that moved repaints', () {
      final oldDelegate = painter();
      final moved = painter(tokenList: tokens(firstSteps: 1));
      expect(moved.shouldRepaint(oldDelegate), isTrue);
    });

    test('a changed legal-move set repaints', () {
      final oldDelegate = painter();
      final changed = painter(legalTokenIds: {'0:1'});
      expect(changed.shouldRepaint(oldDelegate), isTrue);
    });

    test('a changed current seat repaints', () {
      final oldDelegate = painter();
      final changed = painter(currentSeat: 1);
      expect(changed.shouldRepaint(oldDelegate), isTrue);
    });

    test('a changed safe-cell set repaints', () {
      final oldDelegate = painter();
      final changed = painter(
        safeTrackIndices: const {0, 8, 13, 21, 26, 34, 39},
      );
      expect(changed.shouldRepaint(oldDelegate), isTrue);
    });

    test('a changed pulse repaints', () {
      final oldDelegate = painter();
      final changed = painter(pulse: 0.5);
      expect(changed.shouldRepaint(oldDelegate), isTrue);
    });

    test('a hop starting, moving or ending repaints', () {
      final idle = painter();
      final hopping = painter(
        hopTokenId: '0:0',
        hopCenter: const Offset(48, 208),
      );
      expect(hopping.shouldRepaint(idle), isTrue);
      final midHop = painter(
        hopTokenId: '0:0',
        hopCenter: const Offset(56, 136),
      );
      expect(midHop.shouldRepaint(hopping), isTrue);
      expect(idle.shouldRepaint(hopping), isTrue);
    });
  });

  group('painter parameters (M2.7)', () {
    test('pulse defaults to 0 and the hop defaults to none', () {
      final delegate = painter();
      expect(delegate.pulse, 0.0);
      expect(delegate.hopTokenId, isNull);
      expect(delegate.hopCenter, isNull);
    });
  });
}
