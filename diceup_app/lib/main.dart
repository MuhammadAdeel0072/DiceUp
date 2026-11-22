import 'package:diceup/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/design_system/diceup_theme.dart';
import 'data/local/app_startup.dart';
import 'domain/engine/dice_roller.dart';
import 'presentation/app_dependencies_scope.dart';
import 'presentation/feedback/feedback_service.dart';
import 'presentation/navigation/app_routes.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/screens/splash_screen.dart';

/// App entry point (M1.6): the real load happens here, before the
/// first frame, so Home is never shown as ready before
/// initialisation completes. [initializeApp] never throws — a
/// database that cannot be opened even after recovery yields a
/// degraded [StartupResult] and the app still reaches Home.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startup = await initializeApp();
  runApp(DiceUpApp(startup: startup));
}

/// DiceUp — multiplayer Ludo (offline-first).
///
/// Composition root (M3.3, H-07; D-06): the [ProviderScope] below
/// is the single wiring point — it exposes the awaited startup
/// result as [startupResultProvider], from which the repository,
/// use-case and controller providers derive (see
/// `lib/presentation/providers/app_providers.dart`). No game logic
/// lives here, and no screen constructs a repository, a use case
/// or a controller. [AppDependenciesScope] remains for the screens
/// not yet migrated to providers (settings, history, statistics,
/// home, setup — one screen at a time; see the M3.3 plan section).
///
/// Single-scope rule: this is the ONLY [ProviderScope] in the
/// app tree. Never wrap [DiceUpApp] in another scope: Riverpod
/// owns a non-overridden provider in the outermost scope, so its
/// transitive watches resolve there and cannot see this scope's
/// [startupResultProvider] override — the controller graph would
/// read the un-overridden provider and fail. Tests inject fakes
/// through the named test seams below ([testDiceRoller],
/// [testFeedbackService], [testVibrationEnabled]) instead; tests
/// of a bare screen use `test/test_providers.dart`, which builds
/// its own single scope.
class DiceUpApp extends StatefulWidget {
  const DiceUpApp({
    super.key,
    this.startup,
    this.initializer,
    this.testDiceRoller,
    this.testFeedbackService,
    this.testVibrationEnabled,
  });

  /// A completed startup result (production: awaited in [main]).
  /// When null, this widget runs the initializer itself and shows
  /// the loading splash until it completes — the path widget tests
  /// use, so they can inject an in-memory database or a failing
  /// factory without going through [main].
  final StartupResult? startup;

  /// Startup override for tests. Defaults to [initializeApp].
  final Future<StartupResult> Function()? initializer;

  /// Test seams for the app-level scope (fixed dice, fake
  /// feedback, vibration flag), applied as provider overrides
  /// alongside the startup override. Production passes none.
  /// This is how tests inject fakes into the app-level scope —
  /// wrapping [DiceUpApp] in another [ProviderScope] is forbidden
  /// (see the single-scope rule above).
  final DiceRoller? testDiceRoller;
  final FeedbackService? testFeedbackService;
  final bool? testVibrationEnabled;

  @override
  State<DiceUpApp> createState() => _DiceUpAppState();
}

class _DiceUpAppState extends State<DiceUpApp> {
  StartupResult? _startup;

  @override
  void initState() {
    super.initState();
    _startup = widget.startup;
    if (_startup == null) _initialise();
  }

  Future<void> _initialise() async {
    final startup = await (widget.initializer ?? initializeApp)();
    if (mounted) setState(() => _startup = startup);
  }

  @override
  Widget build(BuildContext context) {
    final startup = _startup;
    if (startup == null) {
      // Still initialising: brand + spinner only. The splash never
      // navigates from here — this widget rebuilds with the ready
      // result, and the ready splash navigates to Home.
      return MaterialApp(
        title: 'DiceUp',
        debugShowCheckedModeBanner: false,
        // M3.10 (NFR-38): localised strings (English-only baseline).
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: DiceUpTheme.light(),
        home: const SplashScreen(),
      );
    }
    return ProviderScope(
      overrides: [
        startupResultProvider.overrideWithValue(startup),
        if (widget.testDiceRoller != null)
          diceRollerProvider.overrideWithValue(widget.testDiceRoller!),
        if (widget.testFeedbackService != null)
          feedbackServiceProvider.overrideWithValue(
            widget.testFeedbackService!,
          ),
        if (widget.testVibrationEnabled != null)
          vibrationEnabledProvider.overrideWithValue(
            widget.testVibrationEnabled!,
          ),
      ],
      child: AppDependenciesScope(
        startup: startup,
        child: MaterialApp(
          title: 'DiceUp',
          debugShowCheckedModeBanner: false,
          // M3.10 (NFR-38): localised strings (English-only baseline).
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: DiceUpTheme.light(),
          initialRoute: AppRoutes.splash,
          routes: AppRoutes.routesFor(startup: startup),
          // M3 premium (§2.7.2): the results route's fade/slide
          // entrance lives in AppRoutes.onGenerateRoute (the
          // results entry is deliberately absent from routesFor).
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
  }
}
