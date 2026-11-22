import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../navigation/app_routes.dart';

/// Shown on the results screen when the completed match could not be
/// recorded (M1.6). The match is still shown — the win happened — but
/// never presented as if recording had succeeded. Moved here from
/// `game_screen.dart` in M2.5, when the win dialog (its only reader)
/// was replaced by this screen.
const String kMatchRecordFailedMessage =
    "This match finished, but it couldn't be saved to your history.";

/// Dedicated results screen (M2.5, FR-26; D-02, D-30).
///
/// Shown exactly once per finished match, as a *route* — the M1.6 win
/// dialog is gone. The game screen navigates here with
/// `pushNamedAndRemoveUntil` keeping only Home below, so the stack is
/// Home → Results: the system back button lands on Home, and there is
/// no finished game screen underneath to pop back to. The two actions
/// are both single, stack-shape-aware navigations — never a counted
/// pair of pops (the old double-pop: dialog, then game screen):
///
/// * **Play Again** — a fresh match with the exact settings of the
///   finished match ([MatchResult.setup]: same players, names,
///   colours, difficulties, ruleset), via the game route. The new
///   match starts immediately; the stack becomes Home → Game.
/// * **Main Menu** — Home, exactly once (D-30): a single `pop()` to
///   the Home route below Results (see [_goHome] for why a fresh
///   Home is pushed only when nothing is below).
///
/// What is shown is exactly what FR-26 / SDD §11.1 require: the
/// winner (name + avatar with colour ring + shape + initial — never
/// colour alone, M2.4/D-27), the duration (`mm:ss`), the move count,
/// the mode, the players and the date. "Finishing order where
/// applicable" is winner-only under the default ruleset: the match
/// ends at the first finisher (BR-11) and continue-to-rank is
/// DEFERRED (D-02), so no 2nd/3rd order is shown or invented. No
/// lifetime statistics live here (M1.7 owns those) and no ranking or
/// placement features exist.
///
/// The screen takes its data as a frozen [MatchResult] (constructor
/// parameter in tests, route arguments in production — see
/// [AppRoutes.matchResultOf]). It never reads the game controller:
/// the controller is disposed when the results route replaces the
/// game route, and the screen must never re-record the completion
/// (exactly-once, M1.6). A route opened without a result shows an
/// honest empty state with a Main Menu button, never an invented
/// result.
class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key, this.result});

  /// The finished match to show. When null, the route arguments
  /// supply it (see [AppRoutes.matchResultOf]).
  final MatchResult? result;

  @override
  Widget build(BuildContext context) {
    final result = this.result ?? AppRoutes.matchResultOf(context);
    if (result == null) {
      assert(() {
        debugPrint(
          'DiceUp: results route opened without a MatchResult; '
          'showing the empty state.',
        );
        return true;
      }());
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: SafeArea(
          child: Padding(
            padding: DiceUpSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'No match result to show.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: DiceUpSpacing.lg),
                SecondaryButton(
                  label: 'Main Menu',
                  onPressed: () => _goHome(context),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Results')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: DiceUpSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${result.winnerName} wins!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: DiceUpSpacing.md),
              Center(
                child: PlayerAvatar(
                  name: result.winnerName,
                  seatIndex: result.winnerSeat,
                  colour: result.winnerColour,
                  radius: 36,
                ),
              ),
              const SizedBox(height: DiceUpSpacing.lg),
              DiceUpCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _InfoRow(label: 'Mode', value: result.modeLabel),
                    _InfoRow(
                      label: 'Players',
                      value: '${result.players.length} players',
                    ),
                    _InfoRow(
                      label: 'Duration',
                      value: _formatDuration(result.duration),
                    ),
                    _InfoRow(label: 'Moves', value: '${result.moveCount}'),
                    _InfoRow(
                      label: 'Finished',
                      value: _formatDate(result.finishedAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DiceUpSpacing.md),
              DiceUpCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final player in result.players) ...[
                      _PlayerRow(
                        player: player,
                        isWinner: player.seat == result.winnerSeat,
                      ),
                      if (player != result.players.last)
                        const SizedBox(height: DiceUpSpacing.sm),
                    ],
                  ],
                ),
              ),
              if (result.completionFailed) ...[
                const SizedBox(height: DiceUpSpacing.md),
                DiceUpCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded),
                      const SizedBox(width: DiceUpSpacing.sm),
                      Expanded(child: Text(kMatchRecordFailedMessage)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: DiceUpSpacing.lg),
              PrimaryButton(
                label: 'Play Again',
                onPressed: () => _playAgain(context, result.setup),
              ),
              const SizedBox(height: DiceUpSpacing.sm),
              SecondaryButton(
                label: 'Main Menu',
                onPressed: () => _goHome(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Play Again (D-02): a fresh match with the exact settings of the
  /// finished match. Removes everything above Home and opens the
  /// game route with those settings, so the stack becomes
  /// Home → Game and back from the new match lands on Home.
  void _playAgain(BuildContext context, GameSetup setup) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.game,
      ModalRoute.withName(AppRoutes.home),
      arguments: setup,
    );
  }

  /// Main Menu (D-30): Home, exactly once. When a Home route is
  /// below Results — the normal shape, because the game screen
  /// navigates here with `pushNamedAndRemoveUntil` keeping Home —
  /// a single `pop()` returns to that existing Home. That matters
  /// beyond the pop count: Home offers the resume dialog exactly
  /// once per Home lifetime from the frozen startup snapshot
  /// outcome, so returning to the existing Home never re-offers
  /// resume for the match that just finished (its snapshot was
  /// deleted at completion). Pushing a fresh Home instead would
  /// re-offer that stale snapshot, and resuming it would record
  /// the finished match a second time. Only when nothing is below
  /// Results (a deep link straight to the game route) is a fresh
  /// Home pushed instead, so Main Menu can never strand the user
  /// on an empty stack.
  void _goHome(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushNamedAndRemoveUntil(AppRoutes.home, (_) => false);
    }
  }

  /// Total-minutes `mm:ss` ("01:35", "65:00"): the duration the
  /// remediation plan's M2.5 criterion requires, and > 00:00 for any
  /// real match.
  static String _formatDuration(Duration duration) {
    final totalSeconds = duration.isNegative ? 0 : duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  /// Short date without the intl package ("21 Nov 2026, 12:00") —
  /// the same format the history screen uses.
  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = date.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, '
        '$hour:$minute';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DiceUpSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: DiceUpColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.isWinner});

  final MatchResultPlayer player;
  final bool isWinner;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PlayerAvatar(
          name: player.name,
          seatIndex: player.seat,
          colour: player.colour,
          radius: 16,
        ),
        const SizedBox(width: DiceUpSpacing.sm),
        Expanded(
          child: Text(
            '${player.name}${player.isAi ? ' (AI)' : ''}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (isWinner)
          Text(
            'Winner',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: DiceUpColors.teal),
          ),
      ],
    );
  }
}
