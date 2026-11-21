import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';
import '../navigation/app_routes.dart';
import '../widgets/dice_widget.dart';

/// Splash screen (SRS UI-01).
///
/// Shows the DiceUp mark while local settings load, then goes to Home.
/// No login wall and no network call happen here (FR-01, NFR-23).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Local settings load in Phase 3 (SQLite). Until then this is a
    // short brand moment; the delay is capped so the menu is interactive
    // well inside the 3 s cold-start target (NFR-01).
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(AppRoutes.home);
      }
    });
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
