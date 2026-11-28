import 'package:diceup/data/online/game_socket_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// OrderedEventBuffer (FR-51, SDD §12.6): the client applies
/// broadcasts in sequence order and ignores any event whose `seq`
/// is not exactly last+1, requesting a snapshot on a gap.
void main() {
  test('applies events in order', () {
    final gaps = <int>[];
    final applied = <int>[];
    final buffer = OrderedEventBuffer(onGap: gaps.add);
    buffer.apply(1, () => applied.add(1));
    buffer.apply(2, () => applied.add(2));
    buffer.apply(3, () => applied.add(3));
    expect(applied, [1, 2, 3]);
    expect(buffer.lastSeq, 3);
    expect(gaps, isEmpty);
  });

  test('ignores stale and duplicate seqs', () {
    final gaps = <int>[];
    final applied = <int>[];
    final buffer = OrderedEventBuffer(onGap: gaps.add);
    buffer.apply(1, () => applied.add(1));
    buffer.apply(2, () => applied.add(2));
    buffer.apply(2, () => applied.add(99));
    buffer.apply(1, () => applied.add(99));
    expect(applied, [1, 2]);
    expect(gaps, isEmpty);
  });

  test('on a gap, requests a snapshot and does NOT apply', () {
    final gaps = <int>[];
    final applied = <int>[];
    final buffer = OrderedEventBuffer(onGap: gaps.add);
    buffer.apply(1, () => applied.add(1));
    buffer.apply(3, () => applied.add(3));
    expect(applied, [1]);
    expect(gaps, [1]);
    expect(buffer.lastSeq, 1);
    // The missing event arrives late via the snapshot path: applying
    // seq 2 now works, then 3 applies (no longer a gap).
    buffer.apply(2, () => applied.add(2));
    buffer.apply(3, () => applied.add(3));
    expect(applied, [1, 2, 3]);
    expect(gaps, [1]);
  });

  test('socketUrlFor strips the /v1 prefix and appends /game', () {
    expect(
      GameSocketClient.socketUrlFor('http://127.0.0.1:3000/v1'),
      'http://127.0.0.1:3000/game',
    );
    expect(
      GameSocketClient.socketUrlFor('http://10.0.2.2:3000/v1'),
      'http://10.0.2.2:3000/game',
    );
  });
}
