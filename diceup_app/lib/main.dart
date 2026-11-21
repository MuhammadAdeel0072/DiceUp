import 'package:flutter/material.dart';

import 'core/design_system/diceup_theme.dart';
import 'data/local/app_startup.dart';
import 'presentation/app_dependencies_scope.dart';
import 'presentation/navigation/app_routes.dart';
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
/// Composition root (minimal, M1.6): theme + routes + the
/// dependencies built at startup. No game logic lives here, and no
/// Riverpod / M3.3 composition root is introduced yet (see
/// `lib/data/local/app_dependencies.dart`).
class DiceUpApp extends StatefulWidget {
  const DiceUpApp({super.key, this.startup, this.initializer});

  /// A completed startup result (production: awaited in [main]).
  /// When null, this widget runs the initializer itself and shows
  /// the loading splash until it completes — the path widget tests
  /// use, so they can inject an in-memory database or a failing
  /// factory without going through [main].
  final StartupResult? startup;

  /// Startup override for tests. Defaults to [initializeApp].
  final Future<StartupResult> Function()? initializer;

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
        theme: DiceUpTheme.light(),
        home: const SplashScreen(),
      );
    }
    return AppDependenciesScope(
      startup: startup,
      child: MaterialApp(
        title: 'DiceUp',
        debugShowCheckedModeBanner: false,
        theme: DiceUpTheme.light(),
        initialRoute: AppRoutes.splash,
        routes: AppRoutes.routesFor(startup: startup),
      ),
    );
  }
}
