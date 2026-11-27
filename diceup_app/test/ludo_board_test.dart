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
    double hopScale = 1.0,
    String? captureTokenId,
    Offset? captureCenter,
    double captureScale = 1.0,
    double captureOpacity = 1.0,
    String? lastMovedTokenId,
    double lastMovedOpacity = 0.0,
    String? shakeTokenId,
    Offset shakeOffset = Offset.zero,
  }) => LudoBoardPainter(
    tokens: tokenList ?? tokens(),
    legalTokenIds: legalTokenIds ?? {'0:0'},
    currentSeat: currentSeat,
    safeTrackIndices: safeTrackIndices ?? const {0, 8, 13, 21, 26, 34, 39, 47},
    pulse: pulse,
    hopTokenId: hopTokenId,
    hopCenter: hopCenter,
    hopScale: hopScale,
    captureTokenId: captureTokenId,
    captureCenter: captureCenter,
    captureScale: captureScale,
    captureOpacity: captureOpacity,
    lastMovedTokenId: lastMovedTokenId,
    lastMovedOpacity: lastMovedOpacity,
    shakeTokenId: shakeTokenId,
    shakeOffset: shakeOffset,
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

    test('a changed hop scale repaints (M3 step lift)', () {
      final idle = painter();
      final lifted = painter(hopScale: 1.12);
      expect(lifted.shouldRepaint(idle), isTrue);
      expect(idle.shouldRepaint(lifted), isTrue);
    });

    test('a capture starting, moving or ending repaints (M3)', () {
      final idle = painter();
      final capturing = painter(
        captureTokenId: '1:0',
        captureCenter: const Offset(272, 80),
        captureScale: 0.8,
        captureOpacity: 0.6,
      );
      expect(capturing.shouldRepaint(idle), isTrue);
      final midArc = painter(
        captureTokenId: '1:0',
        captureCenter: const Offset(200, 200),
        captureScale: 0.7,
        captureOpacity: 0.4,
      );
      expect(midArc.shouldRepaint(capturing), isTrue);
      expect(idle.shouldRepaint(capturing), isTrue);
    });

    test('a last-moved ring appearing or fading repaints (M3)', () {
      final idle = painter();
      final ringed = painter(lastMovedTokenId: '0:0', lastMovedOpacity: 1.0);
      expect(ringed.shouldRepaint(idle), isTrue);
      final fading = painter(lastMovedTokenId: '0:0', lastMovedOpacity: 0.5);
      expect(fading.shouldRepaint(ringed), isTrue);
      expect(idle.shouldRepaint(ringed), isTrue);
    });

    test('an illegal-tap shake repaints (M3)', () {
      final idle = painter();
      final shaking = painter(
        shakeTokenId: '0:0',
        shakeOffset: const Offset(1.5, 0),
      );
      expect(shaking.shouldRepaint(idle), isTrue);
      expect(idle.shouldRepaint(shaking), isTrue);
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
