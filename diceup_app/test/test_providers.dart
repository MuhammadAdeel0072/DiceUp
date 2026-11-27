/// Test helpers for the M3.3 Riverpod composition root.
///
/// The single seam for widget tests is the provider override: wrap
/// the widget under test in [withTestProviders] and override
/// [diceRollerProvider] (fixed dice), [feedbackServiceProvider]
/// (recording fake) or [vibrationEnabledProvider] (pin the haptics
/// gate) — never a constructor parameter on the screen. A bare
/// [GameScreen] pump without a [ProviderScope] fails loudly
/// (no [startupResultProvider]), which is the point: the provider
/// graph is the only path to a controller.
///
/// For tests that also need [AppDependenciesScope] (settings,
/// history, statistics screens — not yet migrated to providers),
/// use the file-local `scopedApp` helpers and add the same
/// [ProviderScope] override there; this file only covers the
/// provider side.
library;

import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/local/app_startup.dart';
import 'package:diceup/data/local/snapshot_recovery.dart';
import 'package:diceup/domain/engine/dice_roller.dart';
import 'package:diceup/domain/repositories/settings_repository.dart';
import 'package:diceup/presentation/feedback/feedback_service.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A [StartupResult] for provider tests: [dependencies] (in-memory
/// fakes, or null for degraded play), the default settings unless
/// [settings] is given, and no snapshot to resume.
StartupResult testStartup(
  AppDependencies? dependencies, {
  Map<String, String>? settings,
}) => StartupResult(
  dependencies: dependencies,
  settings: settings ?? Map<String, String>.of(kDefaultSettings),
  snapshotOutcome: const NoSnapshot(),
  databaseRecovered: false,
);

/// A [ProviderScope] with the startup result provided and the
/// game-flow seams overridden. [dependencies] null means degraded
/// play (no repositories): the match stays playable, nothing is
/// persisted, and a finished match reports the recording failure.
ProviderScope withTestProviders({
  required Widget child,
  AppDependencies? dependencies,
  Map<String, String>? settings,
  DiceRoller? diceRoller,
  FeedbackService? feedbackService,
  bool? vibrationEnabled,
}) {
  return ProviderScope(
    overrides: [
      startupResultProvider.overrideWithValue(
        testStartup(dependencies, settings: settings),
      ),
      if (diceRoller != null) diceRollerProvider.overrideWithValue(diceRoller),
      if (feedbackService != null)
        feedbackServiceProvider.overrideWithValue(feedbackService),
      if (vibrationEnabled != null)
        vibrationEnabledProvider.overrideWithValue(vibrationEnabled),
    ],
    child: child,
  );
}
