import 'package:flutter/material.dart';

import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../domain/repositories/local_match_repository.dart';
import '../app_dependencies_scope.dart';

/// Local match history (SRS UI-09, FR-31).
///
/// Lists stored offline matches reverse-chronologically
/// ([LocalMatchRepository.listMatches]) with the existing
/// [EmptyState] when there are none, and a detail view on tap
/// (date, mode, players, winner, duration). Entries are labelled
/// "Local" (BR-18: offline results never affect rankings). No
/// sample or fake matches are ever shown. This is M1 wiring, not
/// an M2 redesign.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
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
      final matches = await dependencies.matches.listMatches();
      if (mounted) setState(() => _matches = matches);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match History')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_unavailable) {
      return const EmptyState(
        icon: Icons.history,
        title: 'History unavailable',
        hint:
            "Your saved data couldn't be loaded, so past matches "
            'cannot be shown right now.',
      );
    }
    if (_loadFailed) {
      return const EmptyState(
        icon: Icons.error_outline,
        title: "Couldn't load match history",
        hint: 'Try again later.',
      );
    }
    final matches = _matches;
    if (matches == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (matches.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: 'No matches yet',
        hint: 'Finished offline matches will appear here, newest first.',
      );
    }
    return ListView.separated(
      padding: DiceUpSpacing.screenPadding,
      itemCount: matches.length,
      separatorBuilder: (_, _) => const SizedBox(height: DiceUpSpacing.sm),
      itemBuilder: (context, index) {
        final match = matches[index];
        final winner = match.winnerName;
        return DiceUpCard(
          onTap: () => _showDetail(match),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      winner == null
                          ? '${_modeLabel(match.mode)} · Finished'
                          : '${_modeLabel(match.mode)} · $winner won',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: DiceUpSpacing.xxs),
                    Text(
                      '${_formatDate(match.playedAt)} · '
                      '${_formatDuration(match.durationSeconds)} · '
                      '${match.playerCount} players',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DiceUpSpacing.sm),
              Text('Local', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDetail(LocalMatch match) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_formatDate(match.playedAt)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(label: 'Mode', value: _modeLabel(match.mode)),
            _DetailRow(
              label: 'Players',
              value: match.players
                  .map(
                    (player) =>
                        '${player.name}${player.isAi ? ' (AI)' : ''}'
                        '${match.winnerName == player.name ? ' — winner' : ''}',
                  )
                  .join('\n'),
            ),
            _DetailRow(
              label: 'Winner',
              value: match.winnerName ?? 'No winner recorded',
            ),
            _DetailRow(
              label: 'Duration',
              value: _formatDuration(match.durationSeconds),
            ),
            _DetailRow(label: 'Ruleset', value: match.rulesetVersion),
            const SizedBox(height: DiceUpSpacing.sm),
            Text(
              'Local match — offline results never affect rankings.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static String _modeLabel(LocalMatchMode mode) => switch (mode) {
    LocalMatchMode.vsAi => 'vs AI',
    LocalMatchMode.localMultiplayer => 'Local multiplayer',
  };

  /// Short date without the intl package: "21 Nov 2026, 12:00".
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

  static String _formatDuration(int? seconds) {
    if (seconds == null) return 'Unknown length';
    if (seconds < 60) return '$seconds s';
    return '${seconds ~/ 60}m ${seconds % 60}s';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

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
            width: 72,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
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
