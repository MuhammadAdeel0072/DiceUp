import 'package:flutter/material.dart';

import '../../domain/ai/ai_player.dart';
import '../screens/game_screen.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/mode_selection_screen.dart';
import '../screens/offline_setup_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/splash_screen.dart';

/// DiceUp navigation (Phase 2).
///
/// Built-in named routes. The SDD (§4.2) proposes go_router; the Phase 2
/// decision — recorded in docs/IMPLEMENTATION-PLAN.md — is to start with
/// built-in routing and adopt go_router when deep links (room invitations)
/// land in Phase 5, because nothing in Phases 2–3 needs it. The route
/// names are stable, so the switch is mechanical.
abstract final class AppRoutes {
  static const String splash = '/';
  static const String home = '/home';
  static const String modeSelection = '/mode';
  static const String offlineSetup = '/offline-setup';
  static const String game = '/game';
  static const String history = '/history';
  static const String settings = '/settings';

  static Map<String, WidgetBuilder> routes = {
    splash: (_) => const SplashScreen(),
    home: (_) => const HomeScreen(),
    modeSelection: (_) => const ModeSelectionScreen(),
    offlineSetup: (_) => const OfflineSetupScreen(),
    game: (_) => const GameScreen(),
    history: (_) => const HistoryScreen(),
    settings: (_) => const SettingsScreen(),
  };

  /// The offline game screen receives its [GameSetup] via route arguments.
  static GameSetup gameSetupOf(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is GameSetup) return args;
    return const GameSetup(playerCount: 2, aiSeats: {1: AiDifficulty.easy});
  }
}

/// Offline mode chosen on the mode-selection screen (SRS FR-12).
enum OfflineMode { vsAi, local }

/// AI difficulty comes from the domain layer ([AiDifficulty] in
/// `lib/domain/ai/`), not from the UI — the UI never invents its own
/// difficulty levels.

/// Configuration for one offline match, collected on the setup screen
/// (SRS FR-12…FR-14, FR-41) and handed to the game screen.
class GameSetup {
  const GameSetup({required this.playerCount, required this.aiSeats});

  /// 2–4 players (FR-13).
  final int playerCount;

  /// Seat index → AI difficulty for AI seats. Human seats are absent.
  /// At least one human seat is enforced by the setup screen (FR-14).
  final Map<int, AiDifficulty> aiSeats;
}
