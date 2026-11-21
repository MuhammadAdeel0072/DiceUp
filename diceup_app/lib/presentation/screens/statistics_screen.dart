import 'package:flutter/material.dart';

import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../domain/engine/player_colour.dart';
import '../../domain/repositories/local_match_repository.dart';
import '../../domain/repositories/local_statistics_repository.dart';
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
    final dependencies =
        AppDependenciesScope.maybeOf(context)?.dependencies;
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
      appBar: AppBar(title: const Text('Statistics')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_unavailable) {
      return const EmptyState(
        icon: Icons.bar_chart_outlined,
        title: 'Statistics unavailable',
        hint: "Your saved data couldn't be loaded, so statistics "
            'cannot be shown right now.',
      );
    }
    if (_loadFailed) {
      return ErrorView(
        message: "Couldn't load statistics",
        onRetry: _retry,
      );
    }
    final statistics = _statistics;
    final matches = _matches;
    if (statistics == null || matches == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: DiceUpSpacing.screenPadding,
      children: [
        DiceUpCard(
          child: Column(
            children: [
              _StatRow(
                label: 'Matches played',
                value: statistics.matchesPlayed,
              ),
              _StatRow(
                label: 'Human wins',
                value: statistics.matchesWon,
              ),
              _StatRow(
                label: 'Matches vs AI',
                value: statistics.matchesVsAi,
              ),
              _StatRow(
                label: 'Local matches',
                value: statistics.matchesLocal,
              ),
            ],
          ),
        ),
        if (statistics.matchesPlayed == 0) ...[
          const SizedBox(height: DiceUpSpacing.md),
          Text(
            'No matches yet — finish an offline match and your '
            'totals will appear here.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ] else ...[
          const SizedBox(height: DiceUpSpacing.lg),
          Text(
            'Wins by seat',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: DiceUpSpacing.xs),
          Text(
            kPerPlayerWinsCaption,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: DiceUpSpacing.sm),
          ..._perPlayerRows(matches),
        ],
      ],
    );
  }

  /// Human wins per seat from the RETAINED history only, keyed by
  /// stable seat identity (seat index + colour). AI wins are
  /// excluded: an AI victory is never a human win (D-24).
  List<Widget> _perPlayerRows(List<LocalMatch> matches) {
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
      return [
        const Text('No human wins in your latest 500 matches yet.'),
      ];
    }
    final seats = wins.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return [
      for (final seat in seats)
        _StatRow(
          label: 'Seat ${seat.index + 1} · ${_colourName(seat.colour)}',
          value: wins[seat]!,
        ),
    ];
  }

  static String _colourName(PlayerColour colour) {
    final name = colour.label;
    return name[0].toUpperCase() + name.substring(1);
  }
}

/// One label/value row of the statistics card.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DiceUpSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text(
            '$value',
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
      other is _SeatIdentity &&
      other.index == index &&
      other.colour == colour;

  @override
  int get hashCode => Object.hash(index, colour);
}
