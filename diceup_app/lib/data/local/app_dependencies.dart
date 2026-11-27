/// Application dependencies (M1.6).
///
/// The app has no Riverpod and no DI container (D-06 names Riverpod,
/// but the M3.3 composition root is a later milestone). M1 wires
/// itself with the minimal DI consistent with what exists: one
/// plain-Dart holder, constructed once at startup, handed to the
/// screens that need it through [AppDependenciesScope] (an
/// [InheritedWidget]). Constructor threading was rejected because
/// the route table builds screens from a static map — every screen
/// would need a new parameter and every route a closure capturing
/// the holder — while an InheritedWidget lets each screen read
/// exactly what it needs, and lets widget tests substitute fakes by
/// wrapping one widget.
///
/// The holder is nullable at the scope level: when the database
/// could not be opened even after recovery (see [StartupResult]),
/// there are no repositories and the screens degrade gracefully
/// (playable, nothing persisted) instead of crashing.
library;

import 'dart:convert';
import 'dart:developer';

import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/repositories/local_match_repository.dart';
import 'package:diceup/domain/repositories/local_player_repository.dart';
import 'package:diceup/domain/repositories/local_statistics_repository.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';
import 'package:diceup/domain/snapshot_writer.dart';

import 'diceup_database.dart';
import 'sqlite_local_match_repository.dart';
import 'sqlite_local_player_repository.dart';
import 'sqlite_local_statistics_repository.dart';
import 'sqlite_settings_repository.dart';
import 'sqlite_snapshot_repository.dart';

/// The five repositories plus the snapshot writer, built once at
/// startup and shared by every screen.
class AppDependencies {
  AppDependencies({
    required this.matches,
    required this.statistics,
    required this.settings,
    required this.players,
    required this.snapshots,
    this.database,
    Map<String, String>? loadedSettings,
  }) : snapshotSaver = SnapshotSaver(snapshots),
       loadedSettings = Map.unmodifiable(
         loadedSettings ?? const <String, String>{},
       );

  /// Builds the dependencies on the open SQLite database: the five
  /// M1.4 repositories over the same handle.
  factory AppDependencies.fromDatabase(DiceUpDatabase database) {
    final db = database.database;
    return AppDependencies(
      matches: SqliteLocalMatchRepository(db),
      statistics: SqliteLocalStatisticsRepository(db),
      settings: SqliteSettingsRepository(db),
      players: SqliteLocalPlayerRepository(db),
      snapshots: SqliteSnapshotRepository(db),
      database: database,
    );
  }

  /// The open database handle, or null when the dependencies were
  /// built without one (tests that substitute fakes).
  final DiceUpDatabase? database;

  final LocalMatchRepository matches;
  final LocalStatisticsRepository statistics;
  final SettingsRepository settings;
  final LocalPlayerRepository players;
  final SnapshotRepository snapshots;

  /// Serialised snapshot writer for the in-progress match (FR-29).
  /// Owned here so the game screen and the startup flow share one
  /// ordering guarantee and one discard path.
  final SnapshotSaver snapshotSaver;

  /// Settings loaded at startup ([StartupResult.settings]): the
  /// stored values with [kDefaultSettings] applied for unset keys.
  /// M1.7 reads these to display real values; M1.6 only loads them.
  final Map<String, String> loadedSettings;
}

/// Serialised, fire-and-forget snapshot writer (M1.6, FR-29).
///
/// Saves are chained onto one tail future, so writes land in
/// submission order and a newer state can never be overwritten by
/// an older write that was still in flight. Nothing is ever
/// dropped — except by [discard]/[invalidate], which is the point:
/// once a match is discarded or finished, a queued save of its old
/// state must not resurrect it.
///
/// A save never throws into the caller and never awaits on the UI
/// thread: failures are logged (error type only — the log never
/// carries snapshot JSON, which can contain player names) and the
/// queue keeps working, so one failed write cannot wedge later
/// ones. Callers that need to observe completion (tests, clean
/// exit) await [flush].
///
/// Implements the domain layer's [SnapshotWriter] (M3.2) so the
/// [OfflineGameController] can use this queue without importing the
/// data layer.
class SnapshotSaver implements SnapshotWriter {
  SnapshotSaver(this._repository);

  final SnapshotRepository _repository;

  Future<void> _tail = Future<void>.value();

  /// Monotonically increasing generation. Every queued save
  /// captures the generation at submission time and re-checks it
  /// when its turn comes; [discard]/[invalidate] bump the
  /// generation, so saves submitted before the bump are dropped
  /// instead of landing after the delete.
  int _generation = 0;

  /// Queues a save of [state] (serialised with [GameState.toJson],
  /// M1.1 format) under the single in-progress key. Returns
  /// immediately; use [flush] to wait for it.
  @override
  void save(GameState state) {
    final generation = _generation;
    final snapshot = SavedSnapshot(
      matchKey: kCurrentMatchKey,
      snapshotJson: jsonEncode(state.toJson()),
      savedAt: DateTime.now(),
    );
    _tail = _tail.then((_) async {
      if (generation != _generation) return;
      try {
        await _repository.saveSnapshot(snapshot);
      } catch (error) {
        log(
          'DiceUp snapshot save failed ($error); the match stays '
          'playable and the next save is retried.',
          name: 'DiceUpSnapshotSaver',
        );
      }
    });
  }

  /// Drops every save queued so far (they are skipped when their
  /// turn comes) without touching the stored row. Used when a match
  /// completes: [LocalMatchRepository.recordMatch] deletes the
  /// snapshot in its own transaction, and no stale write may land
  /// after that delete.
  @override
  void invalidate() {
    _generation++;
  }

  /// Discards the in-progress match: drops every queued save, waits
  /// for any write already in flight, then deletes the stored row.
  /// The delete is chained onto the tail (and awaited), so it is
  /// part of the serialised queue: a later [flush] waits for it,
  /// and a save submitted after the bump chains behind the delete
  /// and skips itself on the bumped generation. The delete is last,
  /// so a write that was already executing cannot land after it; a
  /// write that had not started yet sees the bumped generation and
  /// skips itself. Never throws: a failed delete is logged and the
  /// caller (clean exit) still leaves — exiting must never trap the
  /// user behind storage.
  @override
  Future<void> discard() async {
    _generation++;
    final pending = _tail;
    _tail = pending.then((_) async {
      try {
        await _repository.deleteSnapshot(kCurrentMatchKey);
      } catch (error) {
        log(
          'DiceUp snapshot discard failed ($error); the stale row '
          'may be offered for resume on the next launch.',
          name: 'DiceUpSnapshotSaver',
        );
      }
    });
    await _tail;
  }

  /// Completes when every save queued so far has landed (or been
  /// dropped / failed-and-logged). Test hook, and the clean-exit
  /// path's drain (via [discard]).
  Future<void> get flush => _tail;
}
