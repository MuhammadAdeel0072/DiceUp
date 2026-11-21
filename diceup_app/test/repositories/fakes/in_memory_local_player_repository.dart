import 'package:diceup/domain/repositories/local_player_repository.dart';

import 'in_memory_store.dart';

/// In-memory [LocalPlayerRepository] for tests.
///
/// Stores seats by id in the shared [InMemoryStore]. A seat with a
/// null id is inserted under a fresh id; a seat with an id is stored
/// under that id (insert or replace). `lastUsedAt` is stored exactly
/// as given — the fake never stamps the clock.
class InMemoryLocalPlayerRepository implements LocalPlayerRepository {
  InMemoryLocalPlayerRepository(this._store);

  final InMemoryStore _store;

  @override
  Future<LocalPlayerSeat> upsertSeat(LocalPlayerSeat seat) async {
    _store.throwIfFailing();
    final stored = seat.id == null
        ? seat.copyWith(id: _store.takeNextSeatId())
        : seat;
    _store.seats[stored.id!] = stored;
    return stored;
  }

  @override
  Future<List<LocalPlayerSeat>> listRecentSeats() async {
    _store.throwIfFailing();
    final list = _store.seats.values.toList();
    list.sort((a, b) {
      final aUsed = a.lastUsedAt;
      final bUsed = b.lastUsedAt;
      if (aUsed == null && bUsed == null) return b.id!.compareTo(a.id!);
      if (aUsed == null) return 1;
      if (bUsed == null) return -1;
      final byUsed = bUsed.compareTo(aUsed);
      if (byUsed != 0) return byUsed;
      return b.id!.compareTo(a.id!);
    });
    return list;
  }
}
