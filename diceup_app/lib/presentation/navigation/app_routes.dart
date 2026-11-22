import 'dart:developer';

import 'package:flutter/material.dart';

import '../../data/local/app_startup.dart';
import '../../domain/ai/ai_player.dart';
import '../../domain/engine/game_state.dart';
import '../../domain/engine/player_colour.dart';
import '../../domain/engine/ruleset_config.dart';
import '../screens/game_screen.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/mode_selection_screen.dart';
import '../screens/offline_setup_screen.dart';
import '../screens/results_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/statistics_screen.dart';

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
  static const String results = '/results';
  static const String history = '/history';
  static const String statistics = '/statistics';
  static const String settings = '/settings';

  /// Route table for a completed startup (M1.6): the splash
  /// receives the ready [StartupResult] so it only shows the brand
  /// moment, and the game route reads its arguments itself (see
  /// [resumedStateOf] — a [GameState] argument resumes a match).
  /// The results route is deliberately absent here: it is built by
  /// [onGenerateRoute] (M3 premium, §2.7.2) so its entrance can
  /// fade/slide in over ~300 ms.
  static Map<String, WidgetBuilder> routesFor({StartupResult? startup}) {
    return {
      splash: (_) => SplashScreen(startup: startup),
      home: (_) => const HomeScreen(),
      modeSelection: (_) => const ModeSelectionScreen(),
      offlineSetup: (_) => const OfflineSetupScreen(),
      game: (_) => const GameScreen(),
      history: (_) => const HistoryScreen(),
      statistics: (_) => const StatisticsScreen(),
      settings: (_) => const SettingsScreen(),
    };
  }

  /// Route factory for the results route only (M3 premium, §2.7.2):
  /// the game → results navigation fades in and slides up slightly
  /// over ~300 ms (`Curves.easeOutCubic`), and the reverse (Play
  /// Again / Main Menu leaving results) is shorter (~200 ms).
  /// Returns null for every other route — those come from
  /// [routesFor]. The route's [RouteSettings] (including the
  /// [MatchResult] arguments) pass through untouched, so the screen
  /// still reads them via [matchResultOf].
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    if (settings.name != results) return null;
    return PageRouteBuilder<void>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => const ResultsScreen(),
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
      ),
    );
  }

  /// The offline game screen receives its [GameSetup] via route arguments.
  ///
  /// Deep-link guard (M2.5): the game route opened without a setup has
  /// no honest substitute — a match cannot start from nothing — so the
  /// default 2-player setup below is a crash-avoidance fallback only,
  /// never a silent substitution: the miss is logged (release builds
  /// included) and asserted in debug builds. Callers that open the
  /// game route must always pass a [GameSetup].
  static GameSetup gameSetupOf(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is GameSetup) return args;
    log(
      'DiceUp: game route opened without a GameSetup; using the '
      'default 2-player setup as a deep-link guard.',
      name: 'DiceUpAppRoutes',
    );
    assert(() {
      debugPrint(
        'DiceUp: game route opened without a GameSetup — the caller '
        'must pass one; the default 2-player setup is a guard only.',
      );
      return true;
    }());
    return const GameSetup(playerCount: 2, aiSeats: {1: AiDifficulty.easy});
  }

  /// The finished match the results screen shows (M2.5, FR-26), via
  /// route arguments. Null when the route was opened without one —
  /// the screen shows its empty state then, never an invented result.
  static MatchResult? matchResultOf(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    return args is MatchResult ? args : null;
  }

  /// The resumed match, when the game route was opened with a
  /// [GameState] argument (M1.6 resume flow from Home). Null for a
  /// fresh match started from setup.
  static GameState? resumedStateOf(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    return args is GameState ? args : null;
  }
}

/// Offline mode chosen on the mode-selection screen (SRS FR-12).
enum OfflineMode { vsAi, local }

/// AI difficulty comes from the domain layer ([AiDifficulty] in
/// `lib/domain/ai/`), not from the UI — the UI never invents its own
/// difficulty levels.

/// Configuration for one offline match, collected on the setup screen
/// (SRS FR-12…FR-14, FR-41) and handed to the game screen.
///
/// [names], [colours] and [ruleset] were added in M2.2 (H-08). They
/// default to empty / the stock ruleset so every pre-M2.2 call site
/// still compiles and plays exactly as before: an absent name reads
/// as "Player N" and an absent colour as the seat-order default (see
/// [nameFor] / [colourFor]). The setup screen always passes full
/// per-seat lists.
class GameSetup {
  const GameSetup({
    required this.playerCount,
    required this.aiSeats,
    this.names = const <String>[],
    this.colours = const <PlayerColour>[],
    this.ruleset = const RulesetConfig(),
  });

  /// 2–4 players (FR-13).
  final int playerCount;

  /// Seat index → AI difficulty for AI seats. Human seats are absent.
  /// At least one human seat is enforced by the setup screen (FR-14).
  final Map<int, AiDifficulty> aiSeats;

  /// Per-seat display names (M2.2, D-28): trimmed on the setup
  /// screen, 1–12 characters, empty meaning "Player N". Duplicates
  /// are allowed — identity is seat + colour + shape, not name.
  /// May be shorter than [playerCount] (older call sites pass
  /// nothing); [nameFor] fills the gap.
  final List<String> names;

  /// Per-seat chosen colours (M2.2, H-08): distinct per seat, one of
  /// the four [PlayerColour] values. May be shorter than
  /// [playerCount]; [colourFor] fills the gap with the seat-order
  /// default.
  final List<PlayerColour> colours;

  /// The frozen ruleset this match plays under (M2.2, D-29): the
  /// curated user-facing subset (release-on-1, exact finish, extra
  /// turn on six/capture/home, third-six limit). "Continue to rank
  /// 2nd/3rd" is excluded — there are no mechanics for it (D-02).
  final RulesetConfig ruleset;

  /// Display name for [seat]: the chosen name, or "Player N" when
  /// none was chosen (empty string counts as none).
  String nameFor(int seat) {
    if (seat < names.length && names[seat].trim().isNotEmpty) {
      return names[seat].trim();
    }
    return 'Player ${seat + 1}';
  }

  /// Colour for [seat]: the chosen colour, or the seat-order
  /// default when none was chosen.
  PlayerColour colourFor(int seat) {
    if (seat < colours.length) return colours[seat];
    return PlayerColour.values[seat % PlayerColour.values.length];
  }
}

/// One participant in a finished match, as the results screen lists
/// them (M2.5, FR-26). Identity is seat + colour + shape, never name
/// alone (D-28) — the screen renders each player with their
/// [PlayerAvatar] (name + colour ring + per-seat shape).
class MatchResultPlayer {
  const MatchResultPlayer({
    required this.seat,
    required this.name,
    required this.colour,
    required this.isAi,
    this.tokensHome = 0,
  });

  /// Seat index (0–3); the shape follows the seat (D-27).
  final int seat;

  /// Display name ("Player N" when none was chosen, D-28).
  final String name;

  /// The player's *chosen* colour — the avatar ring follows this,
  /// not the seat-order colour (M2.4).
  final PlayerColour colour;

  /// True for an AI seat (shown as "(AI)" next to the name).
  final bool isAi;

  /// Tokens this player has brought home (0–4) at match end (M3
  /// premium, §2.6/Q8): display data derived from the final state
  /// by the game screen — no schema change. Defaults to 0 so
  /// older call sites (tests building a result by hand) keep
  /// compiling and render "Home 0/4" only when the screen shows it.
  final int tokensHome;
}

/// A finished offline match, as the results screen shows it (M2.5,
/// FR-26; D-02 condition 6).
///
/// A frozen value object, built once by the game screen when the
/// match's completion record is decided: [duration] and [finishedAt]
/// are fixed at that moment, so a rebuild of the results screen can
/// never stretch the duration. The winner, the participants and the
/// match info are all plain data — the screen derives nothing from a
/// live controller (the game screen's controller is disposed when the
/// results route replaces it), and completion is never re-recorded
/// from here (the controller's exactly-once guard owns that, M1.6).
///
/// Designed so finishing-order/ranking support can be added later
/// without redesign (D-02): a future `finishOrder` list of seat
/// indices slots in beside [winnerSeat] — there is no such field
/// today because continue-to-rank is DEFERRED (D-02) and the default
/// ruleset ends the match at the first finisher, so "finishing order
/// where applicable" (FR-26) is winner-only. No ranking, placement
/// or 2nd/3rd-place data is invented here.
class MatchResult {
  const MatchResult({
    required this.winnerSeat,
    required this.winnerName,
    required this.winnerColour,
    required this.players,
    required this.duration,
    required this.moveCount,
    required this.finishedAt,
    required this.setup,
    this.completionFailed = false,
  });

  /// Winning seat (0–3).
  final int winnerSeat;

  /// Winning player's display name.
  final String winnerName;

  /// Winning player's chosen colour.
  final PlayerColour winnerColour;

  /// All participants in seat order (winner included).
  final List<MatchResultPlayer> players;

  /// Match length, from the match's start to its finish.
  final Duration duration;

  /// Moves applied in the match.
  final int moveCount;

  /// Wall-clock time the match finished (the date the screen shows).
  final DateTime finishedAt;

  /// The exact settings the match played under — Play Again restarts
  /// from this, never from re-read route arguments (D-02).
  final GameSetup setup;

  /// True when the completed match could not be recorded (M1.6):
  /// the screen carries the failure notice instead of presenting the
  /// win as if recording had succeeded.
  final bool completionFailed;

  /// True when any seat is AI — the mode label.
  bool get isVsAi => players.any((player) => player.isAi);
}
