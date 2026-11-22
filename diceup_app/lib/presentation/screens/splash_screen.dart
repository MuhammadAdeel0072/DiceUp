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
/// there is no hard-coded load delay any more (M1.6). What remains
/// is a short brand moment (500 ms, inside the 3 s cold-start
/// target, NFR-01) so the splash is not a single-frame flash.
///
/// When [startup] is null the app is still initialising: the splash
/// shows the brand + spinner and never navigates — the parent
/// rebuilds with a ready splash once initialisation completes.
/// No login wall and no network call happen here (FR-01, NFR-23).
///
/// The spinner stays through the 500 ms brand moment after the
/// load completes (M2.10 follow-up, recorded not fixed): it is the
/// only continuously animating widget on the splash, and the test
/// harness's `pumpAndSettle` boot path returns as soon as no frame
/// is scheduled — with no spinner on the ready splash it returns
/// before the 500 ms navigation timer fires, which broke 26 boot
/// tests (verified by probe: ready splash shown, spinner absent,
/// Home never reached). Removing the spinner needs the boot tests'
/// `pumpAndSettle` reliance reworked first; until then the spinner
/// during the brand moment is a known, visible imperfection, not a
/// claim that a load is still running. The substantive honesty —
/// a real load in [main] (M1.6), no fake 900 ms delay — is done.
///
/// Styled through the typography tokens (M2.10): the title is the
/// theme's [TextTheme.displayLarge], the tagline its
/// [TextTheme.bodyLarge], each with only the on-dark colour applied.
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
    // M2.10: text styles come from the theme's typography tokens —
    // no raw font sizes here.
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: DiceUpColors.navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DiceWidget(value: 6, size: 96),
            const SizedBox(height: 24),
            Text(
              'DiceUp',
              style: textTheme.displayLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Multiplayer Ludo',
              style: textTheme.bodyLarge?.copyWith(
                color: const Color(0xFFCBD5E1),
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
