import 'package:flutter/material.dart';

import 'package:diceup/l10n/app_localizations.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../domain/engine/player_colour.dart';
import '../../domain/repositories/local_match_repository.dart';
import '../../domain/repositories/local_statistics_repository.dart';
import '../../l10n/app_strings.dart';
import '../app_dependencies_scope.dart';

/// The honest caption for the per-player breakdown (M1.7, D-24).
///
/// The approved schema has no per-player lifetime table, so a
/// lifetime-exact per-player breakdown is impossible after the
/// 500-match prune: this breakdown is computed from the retained
/// history only, and the caption says so.
const String kPerPlayerWinsCaption =
    'Per-player wins from your latest 500 matches.';

/// Local statistics (SRS FR-32).
///
/// Reads the PERSISTED lifetime statistics ([LocalStatisticsRepository.
/// getStatistics]) — the cached row maintained incrementally by
/// `recordMatch` — and displays them directly. The totals are NEVER
/// derived in this screen from the retained history: after pruning,
/// the retained 500 cannot reconstruct lifetime totals (see the
/// b0f7ab0 correction). The per-player breakdown below is the one
/// exception, and it is computed from retained history only because
/// the schema keeps no per-player lifetime table (D-24) — it is
/// labelled as such (see [kPerPlayerWinsCaption]), players are
/// identified by stable seat identity (seat index + colour, not
/// display name — names may duplicate, D-28), and AI wins never
/// appear in it or in the human-wins total.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  LocalStatistics? _statistics;
  List<LocalMatch>? _matches;
  bool _loadFailed = false;
  bool _unavailable = false;
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadStarted) return;
    _loadStarted = true;
    _load();
  }

  Future<void> _load() async {
    final dependencies = AppDependenciesScope.maybeOf(context)?.dependencies;
    if (dependencies == null) {
      if (mounted) setState(() => _unavailable = true);
      return;
    }
    try {
      final statistics = await dependencies.statistics.getStatistics();
      final matches = await dependencies.matches.listMatches();
      if (mounted) {
        setState(() {
          _statistics = statistics;
          _matches = matches;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  void _retry() {
    setState(() {
      _statistics = null;
      _matches = null;
      _loadFailed = false;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(stringsOf(context).statisticsTitle)),
      body: _body(),
    );
  }

  Widget _body() {
    final l10n = stringsOf(context);
    if (_unavailable) {
      return EmptyState(
        icon: Icons.bar_chart_outlined,
        title: l10n.statisticsUnavailableTitle,
        hint: l10n.statisticsUnavailableHint,
      );
    }
    if (_loadFailed) {
      return ErrorView(message: l10n.statisticsLoadFailed, onRetry: _retry);
    }
    final statistics = _statistics;
    final matches = _matches;
    if (statistics == null || matches == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DiceUpSpacing.maxContentWidth,
          ),
          child: ListView(
            padding: DiceUpSpacing.screenPadding,
            children: [
              // Lifetime totals as a 2x2 stat grid (REDESIGN-PLAN.md
              // §3.7): large numerals, one tile per total. The totals
              // still come from the persisted lifetime row, never
              // from the retained history (see the class doc).
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: StatTile(
                      label: l10n.statisticsMatchesPlayed,
                      value: '${statistics.matchesPlayed}',
                      icon: Icons.casino_outlined,
                    ),
                  ),
                  const SizedBox(width: DiceUpSpacing.sm),
                  Expanded(
                    child: StatTile(
                      label: l10n.statisticsHumanWins,
                      value: '${statistics.matchesWon}',
                      icon: Icons.emoji_events_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DiceUpSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: StatTile(
                      label: l10n.statisticsMatchesVsAi,
                      value: '${statistics.matchesVsAi}',
                      icon: Icons.smart_toy_outlined,
                    ),
                  ),
                  const SizedBox(width: DiceUpSpacing.sm),
                  Expanded(
                    child: StatTile(
                      label: l10n.statisticsLocalMatches,
                      value: '${statistics.matchesLocal}',
                      icon: Icons.people_outline,
                    ),
                  ),
                ],
              ),
              if (statistics.matchesPlayed == 0) ...[
                const SizedBox(height: DiceUpSpacing.md),
                Text(
                  l10n.statisticsNoMatches,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ] else ...[
                const SizedBox(height: DiceUpSpacing.lg),
                SectionHeading(
                  title: l10n.statisticsWinsBySeat,
                  subtitle: l10n.statisticsPerPlayerCaption,
                ),
                const SizedBox(height: DiceUpSpacing.xs),
                DiceUpCard(
                  child: Column(children: _perPlayerRows(matches, l10n)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Human wins per seat from the RETAINED history only, keyed by
  /// stable seat identity (seat index + colour). AI wins are
  /// excluded: an AI victory is never a human win (D-24).
  List<Widget> _perPlayerRows(List<LocalMatch> matches, AppLocalizations l10n) {
    final wins = <_SeatIdentity, int>{};
    for (final match in matches) {
      final winner = match.winner;
      if (winner == null || winner.isAi) continue;
      final seat = _SeatIdentity(
        index: match.winnerIndex!,
        colour: winner.colour,
      );
      wins[seat] = (wins[seat] ?? 0) + 1;
    }
    if (wins.isEmpty) {
      return [Text(l10n.statisticsNoHumanWins)];
    }
    final seats = wins.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return [
      for (final seat in seats)
        _SeatRow(
          seat: seat,
          // gen-l10n orders the positional parameters alphabetically
          // (colour, seat), not in message order.
          label: l10n.statisticsSeatWins(
            _colourName(seat.colour, l10n),
            seat.index + 1,
          ),
          value: wins[seat]!,
        ),
    ];
  }

  static String _colourName(PlayerColour colour, AppLocalizations l10n) {
    final name = colourName(colour, l10n);
    return name[0].toUpperCase() + name.substring(1);
  }
}

/// One per-seat row of the wins-by-seat breakdown: the seat's shape
/// marker in its colour (never colour alone, D-27/NFR-08) next to
/// the label, with the win count at the end of the row.
class _SeatRow extends StatelessWidget {
  const _SeatRow({
    required this.seat,
    required this.label,
    required this.value,
  });

  final _SeatIdentity seat;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DiceUpSpacing.xs),
      child: Row(
        children: [
          PlayerShapeMarker(
            shape: PlayerShape.forSeat(seat.index),
            color: DiceUpColors.forColour(seat.colour),
            size: 16,
          ),
          const SizedBox(width: DiceUpSpacing.sm),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          Text(
            value.toString(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

/// A seat's stable identity: index + colour, never the display name.
class _SeatIdentity {
  const _SeatIdentity({required this.index, required this.colour});

  final int index;
  final PlayerColour colour;

  @override
  bool operator ==(Object other) =>
      other is _SeatIdentity && other.index == index && other.colour == colour;

  @override
  int get hashCode => Object.hash(index, colour);
}
