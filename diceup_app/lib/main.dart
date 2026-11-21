import 'package:flutter/material.dart';

import 'core/design_system/diceup_theme.dart';
import 'presentation/navigation/app_routes.dart';

void main() {
  runApp(const DiceUpApp());
}

/// DiceUp — multiplayer Ludo (offline-first).
///
/// Composition root only: theme + routes. No game logic lives here.
class DiceUpApp extends StatelessWidget {
  const DiceUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DiceUp',
      debugShowCheckedModeBanner: false,
      theme: DiceUpTheme.light(),
      initialRoute: AppRoutes.splash,
      routes: AppRoutes.routes,
    );
  }
}
