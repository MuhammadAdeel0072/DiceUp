import 'dart:convert';

import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/engine/ludo_game.dart';
import 'package:diceup/domain/engine/player.dart';
import 'package:diceup/domain/engine/player_colour.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../repositories/fakes/fakes.dart';

/// M1.6 [SnapshotSaver] tests: writes land in submission order, a
/// newer state is never overwritten by an older write, discard
/// drops queued saves, and a failed save never throws into the
/// caller or wedges later saves.
void main() {
  InMemoryStore store() => InMemoryStore();
  SnapshotSaver saver(InMemoryStore s) =>
      SnapshotSaver(InMemorySnapshotRepository(s));

  GameState stateWithMoveCount(int moveCount) {
    final game = LudoGame.newMatch(
      seats: const [
        SeatConfig(name: 'Player 1', colour: PlayerColour.red),
        SeatConfig(name: 'Player 2', colour: PlayerColour.green),
      ],
    );
    // GameState has no moveCount setter; rebuild the state through
    // copyWith so the saved JSON differs per call.
    return game.state.copyWith(moveCount: moveCount);
  }

  int savedMoveCount(InMemoryStore s) {
    final row = s.snapshots[kCurrentMatchKey];
    if (row == null) return -1;
    final json = jsonDecode(row.snapshotJson) as Map<String, Object?>;
    return json['moveCount'] as int;
  }

  test('save then flush stores the state', () async {
    final s = store();
    final underTest = saver(s);
    underTest.save(stateWithMoveCount(3));
    await underTest.flush;
    expect(await InMemorySnapshotRepository(s).hasSnapshot(kCurrentMatchKey),
        isTrue);
    expect(savedMoveCount(s), 3);
  });

  test('consecutive saves land in order: newer never overwritten by older',
      () async {
    final s = store();
    final inner = InMemorySnapshotRepository(s);
    // The first write is slow (30 ms); the second is instant. If
    // writes ran concurrently, the slow first write would land
    // after the second and the stored state would be stale.
    final slow = _DelayedSnapshotRepository(inner, firstDelay: 30);
    final underTest = SnapshotSaver(slow);
    underTest.save(stateWithMoveCount(1));
    underTest.save(stateWithMoveCount(2));
    await underTest.flush;
    expect(savedMoveCount(s), 2);
  });

  test('discard drops a queued save', () async {
    final s = store();
    final inner = InMemorySnapshotRepository(s);
    final slow = _DelayedSnapshotRepository(inner, firstDelay: 50);
    final underTest = SnapshotSaver(slow);
    underTest.save(stateWithMoveCount(1));
    await underTest.discard();
    await underTest.flush;
    expect(await inner.hasSnapshot(kCurrentMatchKey), isFalse);
  });

  test('discard deletes a stored snapshot', () async {
    final s = store();
    final underTest = saver(s);
    underTest.save(stateWithMoveCount(1));
    await underTest.flush;
    expect(savedMoveCount(s), 1);
    await underTest.discard();
    expect(
      await InMemorySnapshotRepository(s).hasSnapshot(kCurrentMatchKey),
      isFalse,
    );
  });

  test('invalidate drops queued saves without deleting the row',
      () async {
    final s = store();
    final underTest = saver(s);
    underTest.save(stateWithMoveCount(1));
    await underTest.flush;
    expect(savedMoveCount(s), 1);
    underTest.save(stateWithMoveCount(2));
    underTest.invalidate();
    await underTest.flush;
    expect(savedMoveCount(s), 1);
  });

  test('a failed save does not throw and does not wedge later saves',
      () async {
    final s = store();
    final underTest = saver(s);
    s.failNextCall();
    underTest.save(stateWithMoveCount(1));
    await underTest.flush;
    expect(savedMoveCount(s), -1);
    underTest.save(stateWithMoveCount(2));
    await underTest.flush;
    expect(savedMoveCount(s), 2);
  });

  test('a failed discard does not throw', () async {
    final s = store();
    final underTest = saver(s);
    underTest.save(stateWithMoveCount(1));
    await underTest.flush;
    s.failNextCall();
    await underTest.discard();
    // The delete failed and was logged; the row survives, and the
    // saver is still usable afterwards.
    expect(savedMoveCount(s), 1);
  });
}

/// A [SnapshotRepository] that delays its first [saveSnapshot] by
/// [firstDelay] milliseconds, then delegates. Proves the saver
/// serialises writes instead of letting a slow write overtake.
class _DelayedSnapshotRepository implements SnapshotRepository {
  _DelayedSnapshotRepository(this._inner, {required this.firstDelay});

  final SnapshotRepository _inner;
  final int firstDelay;
  var _delayed = false;

  @override
  Future<void> saveSnapshot(SavedSnapshot snapshot) async {
    if (!_delayed) {
      _delayed = true;
      await Future<void>.delayed(Duration(milliseconds: firstDelay));
    }
    return _inner.saveSnapshot(snapshot);
  }

  @override
  Future<void> deleteSnapshot(String matchKey) =>
      _inner.deleteSnapshot(matchKey);

  @override
  Future<bool> hasSnapshot(String matchKey) =>
      _inner.hasSnapshot(matchKey);

  @override
  Future<SavedSnapshot?> loadSnapshot(String matchKey) =>
      _inner.loadSnapshot(matchKey);
}
