/// Corrupt-snapshot handling (M1.5, D-22; SDD §9.1
/// `saved_match_snapshots`, FR-29).
///
/// A corrupt snapshot is a SEPARATE case from whole-database
/// corruption and is handled separately: the database itself is
/// healthy and readable, only one stored snapshot row is bad. A
/// snapshot row whose JSON fails strict validation must be rejected,
/// the invalid row deleted, and a user-facing notice surfaced — a
/// malformed match is never restored, and the rest of the database
/// (history, statistics, settings, seats) is untouched.
///
/// This file is the snapshot read path the startup flow (M1.6)
/// uses: [loadSnapshotForResume] loads the in-progress snapshot and
/// distinguishes its three outcomes with [SnapshotLoadOutcome], so
/// M1.6 can show the notice exactly when a corrupt snapshot was
/// discarded, offer Resume only for a valid snapshot, and do nothing
/// when no snapshot is stored. The startup UI itself is M1.6's job;
/// this file only detects, deletes and reports.
///
/// The snapshot JSON is validated with strict `GameState` parsing
/// (M1.1, D-22): malformed JSON, a non-object document, or any
/// field that fails [GameState.fromJson] (wrong `formatVersion`, a
/// ruleset mismatch, an out-of-range field, a missing `startedAt`)
/// all count as corrupt. Only [FormatException] triggers deletion:
/// any other error (for example a database read failure) propagates
/// untouched — a failed read after a successful open is a database
/// error, not a corrupt snapshot, and must never delete the row.
///
/// The notice text is defined once here ([kCorruptSnapshotMessage])
/// so M1.6 shows exactly this text; it is NOT the database-recovery
/// message (`kDatabaseRecoveryMessage` in `database_recovery.dart`).
library;

import 'dart:convert';
import 'dart:developer';

import 'package:diceup/domain/engine/game_state.dart';
import 'package:diceup/domain/repositories/snapshot_repository.dart';

/// The exact user-facing notice shown once when a stored snapshot
/// was corrupt and was discarded.
///
/// Defined once here so the startup flow (M1.6) shows exactly this
/// text. It carries no technical detail — the diagnostics for the
/// discarded snapshot go to the developer log only (see
/// [loadSnapshotForResume]).
const String kCorruptSnapshotMessage =
    "Your saved match couldn't be read, so it was discarded. "
    'You can start a new match.';

/// The outcome of loading the in-progress snapshot for resume.
///
/// The three cases are distinct types so the startup flow (M1.6)
/// cannot confuse "no snapshot stored" with "a corrupt snapshot
/// was deleted": only [CorruptSnapshotDiscarded] shows
/// [kCorruptSnapshotMessage], and only [ValidSnapshot] offers
/// Resume.
sealed class SnapshotLoadOutcome {
  const SnapshotLoadOutcome();
}

/// No snapshot is stored under the key.
class NoSnapshot extends SnapshotLoadOutcome {
  const NoSnapshot();
}

/// A stored snapshot that passed strict validation. The snapshot
/// is returned verbatim, exactly as stored.
class ValidSnapshot extends SnapshotLoadOutcome {
  const ValidSnapshot(this.snapshot);

  final SavedSnapshot snapshot;
}

/// A stored snapshot failed strict validation, so the row was
/// deleted. The app stays playable; the match cannot be resumed.
class CorruptSnapshotDiscarded extends SnapshotLoadOutcome {
  const CorruptSnapshotDiscarded();
}

/// Loads the in-progress snapshot stored under [matchKey] for
/// resume, validating it strictly.
///
/// Returns [NoSnapshot] when nothing is stored, [ValidSnapshot]
/// with the stored snapshot (verbatim) when it passes strict
/// `GameState` validation, and [CorruptSnapshotDiscarded] when the
/// stored JSON was corrupt — in which case the invalid row is
/// deleted before returning, so the corrupt snapshot can never be
/// offered for resume again.
///
/// [parse] is the strict validator, defaulting to
/// [GameState.fromJson]; it exists so callers and tests can supply
/// the same validation explicitly. Only a [FormatException] from
/// the JSON decode or from [parse] triggers deletion; any other
/// error propagates and the row is left in place.
///
/// The discarded snapshot's JSON is never logged: it can contain
/// player names, which are user data.
Future<SnapshotLoadOutcome> loadSnapshotForResume(
  SnapshotRepository repository, {
  String matchKey = kCurrentMatchKey,
  GameState Function(Map<String, Object?> json)? parse,
}) async {
  final stored = await repository.loadSnapshot(matchKey);
  if (stored == null) return const NoSnapshot();
  final parseState = parse ?? GameState.fromJson;
  try {
    final decoded = jsonDecode(stored.snapshotJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Snapshot JSON must be a JSON object.');
    }
    parseState(decoded);
    return ValidSnapshot(stored);
  } on FormatException catch (error) {
    log(
      'Discarding corrupt snapshot under "$matchKey": $error',
      name: 'DiceUpSnapshotRecovery',
    );
    // Delete first, then report: if the delete itself throws (a
    // database error, not a corrupt snapshot) the error propagates
    // and the caller must not claim the snapshot was discarded.
    await repository.deleteSnapshot(matchKey);
    return const CorruptSnapshotDiscarded();
  }
}
