import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../data/local/app_startup.dart';
import '../navigation/app_routes.dart';
import '../widgets/dice_widget.dart';

/// Splash screen (SRS UI-01).
///
/// Shows the DiceUp mark while the app starts, then goes to Home.
/// The real load happens before this screen is shown ready — in
/// [main] (production) or in [DiceUpApp] (tests / fallback) — so
/// there is no hard-coded load delay any more. What remains is a
/// short brand moment (500 ms, inside the 3 s cold-start target,
/// NFR-01) so the splash is not a single-frame flash.
///
/// When [startup] is null the app is still initialising: the splash
/// shows the brand + spinner and never navigates — the parent
/// rebuilds with a ready splash once initialisation completes.
/// No login wall and no network call happen here (FR-01, NFR-23).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.startup});

  /// The completed startup result, or null while initialising.
  final StartupResult? startup;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.startup != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(AppRoutes.home);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DiceUpColors.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DiceWidget(value: 6, size: 96),
            const SizedBox(height: 24),
            const Text(
              'DiceUp',
              style: TextStyle(
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Multiplayer Ludo',
              style: TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: DiceUpColors.amber),
          ],
        ),
      ),
    );
  }
}
