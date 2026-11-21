/// Application startup (M1.6): real load behind the splash.
///
/// `main()` awaits [initializeApp] before the first frame, so Home
/// is never shown as ready before initialisation completes:
/// open the database with recovery (M1.5), build the five
/// repositories, load the persisted settings, and load the
/// in-progress snapshot for resume. The splash screen then only
/// shows the brand moment — it no longer fakes the load with a
/// hard-coded delay.
///
/// Startup never throws and never blocks entry: if the database
/// cannot be opened even after recovery, the result carries no
/// dependencies and a [startupError], and the app still reaches
/// Home with an error notice (screens degrade to playable without
/// persistence). A failed settings or snapshot read likewise
/// degrades to defaults / no snapshot instead of failing startup —
/// a bad settings row must never keep the user out of the app.
library;

import 'dart:developer';

import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:sqflite/sqflite.dart';

import 'app_dependencies.dart';
import 'database_factory.dart';
import 'database_recovery.dart';
import 'snapshot_recovery.dart';

/// Shown once on Home when the local database could not be opened
/// even after recovery (M1.6). No technical detail: the diagnostics
/// go to the developer log only (see [initializeApp]).
const String kStartupDatabaseErrorMessage =
    "Your saved data couldn't be loaded. You can still play, but "
    'matches and settings will not be saved this time.';

/// The outcome of application startup.
///
/// Always returned, even when the database is unusable — check
/// [startupError] / [dependencies] instead of catching.
class StartupResult {
  const StartupResult({
    required this.dependencies,
    required this.settings,
    required this.snapshotOutcome,
    required this.databaseRecovered,
    this.startupError,
  });

  /// The repositories, or null when the database could not be
  /// opened even after recovery. Screens treat null as "playable
  /// without persistence".
  final AppDependencies? dependencies;

  /// Persisted settings with [kDefaultSettings] applied for unset
  /// keys; the defaults alone when settings could not be read.
  final Map<String, String> settings;

  /// The in-progress snapshot for resume: [ValidSnapshot] offers
  /// Resume, [CorruptSnapshotDiscarded] shows
  /// [kCorruptSnapshotMessage] once, [NoSnapshot] does nothing.
  final SnapshotLoadOutcome snapshotOutcome;

  /// True when this startup recovered from an unreadable database
  /// (M1.5): show [kDatabaseRecoveryMessage] once.
  final bool databaseRecovered;

  /// Non-null when the database could not be opened even after
  /// recovery. The value is the failure, for tests and logging
  /// only — the user-facing text is [kStartupDatabaseErrorMessage],
  /// never this string.
  final String? startupError;
}

/// Runs the startup load and always returns a [StartupResult].
///
/// [factory]/[path] are the database location (production passes
/// neither; tests pass `databaseFactoryFfi` plus an in-memory or
/// temp-file path so no platform directory resolution is needed).
Future<StartupResult> initializeApp({
  DatabaseFactory? factory,
  String? path,
}) async {
  final fallbackSettings = Map<String, String>.of(kDefaultSettings);
  late final DatabaseOpenResult open;
  try {
    open = await openDiceUpDatabaseWithRecovery(
      factory: factory,
      path: path,
    );
  } catch (error) {
    log(
      'DiceUp startup: database could not be opened even after '
      'recovery ($error); continuing without persistence.',
      name: 'DiceUpStartup',
    );
    return StartupResult(
      dependencies: null,
      settings: fallbackSettings,
      snapshotOutcome: const NoSnapshot(),
      databaseRecovered: false,
      startupError: error.toString(),
    );
  }
  final dependencies = AppDependencies.fromDatabase(open.handle);
  Map<String, String> settings;
  try {
    final stored = await dependencies.settings.getAllSettings();
    settings = {...kDefaultSettings, ...stored};
  } catch (error) {
    log(
      'DiceUp startup: settings could not be read ($error); '
      'using defaults.',
      name: 'DiceUpStartup',
    );
    settings = fallbackSettings;
  }
  SnapshotLoadOutcome snapshotOutcome;
  try {
    snapshotOutcome =
        await loadSnapshotForResume(dependencies.snapshots);
  } catch (error) {
    log(
      'DiceUp startup: snapshot could not be read ($error); '
      'offering no resume.',
      name: 'DiceUpStartup',
    );
    snapshotOutcome = const NoSnapshot();
  }
  return StartupResult(
    dependencies: dependencies,
    settings: settings,
    snapshotOutcome: snapshotOutcome,
    databaseRecovered: open.recovered,
    startupError: null,
  );
}
