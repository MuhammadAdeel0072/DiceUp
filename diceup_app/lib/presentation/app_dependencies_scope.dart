import 'package:flutter/widgets.dart';

import '../data/local/app_dependencies.dart';
import '../data/local/app_startup.dart';

/// Carries the startup result down the widget tree (M1.6).
///
/// [DiceUpApp] builds this once, above [MaterialApp], so every
/// screen can read the dependencies and the one-shot startup
/// outcome (recovery / corrupt-snapshot notices, resume offer)
/// without constructor threading through the static route table.
/// Widget tests substitute fakes by wrapping one widget in this
/// scope directly.
class AppDependenciesScope extends InheritedWidget {
  const AppDependenciesScope({
    super.key,
    required this.startup,
    required super.child,
  });

  /// The startup result. [StartupResult.dependencies] is null when
  /// the database could not be opened — screens must degrade, not
  /// crash, in that case.
  final StartupResult startup;

  /// The repositories, or null when the database is unavailable.
  AppDependencies? get dependencies => startup.dependencies;

  static AppDependenciesScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppDependenciesScope>();
    if (scope == null) {
      throw StateError(
        'No AppDependenciesScope found above this widget — '
        'screens must run inside DiceUpApp.',
      );
    }
    return scope;
  }

  static AppDependenciesScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppDependenciesScope>();

  @override
  bool updateShouldNotify(AppDependenciesScope oldWidget) =>
      startup != oldWidget.startup;
}
