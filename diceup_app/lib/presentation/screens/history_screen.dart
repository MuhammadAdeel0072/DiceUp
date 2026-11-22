import 'package:flutter/material.dart';

import 'package:diceup/l10n/app_localizations.dart';

import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../domain/repositories/local_match_repository.dart';
import '../../l10n/app_strings.dart';
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
      appBar: AppBar(title: Text(stringsOf(context).homeMatchHistory)),
      body: _body(),
    );
  }

  Widget _body() {
    final l10n = stringsOf(context);
    if (_unavailable) {
      return EmptyState(
        icon: Icons.history,
        title: l10n.historyUnavailableTitle,
        hint: l10n.historyUnavailableHint,
      );
    }
    if (_loadFailed) {
      return EmptyState(
        icon: Icons.error_outline,
        title: l10n.historyLoadFailedTitle,
        hint: l10n.historyLoadFailedHint,
      );
    }
    final matches = _matches;
    if (matches == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (matches.isEmpty) {
      return EmptyState(
        icon: Icons.history,
        title: l10n.historyEmptyTitle,
        hint: l10n.historyEmptyHint,
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
                          ? l10n.historyMatchFinished(
                              _modeLabel(match.mode, l10n),
                            )
                          : l10n.historyMatchWon(
                              _modeLabel(match.mode, l10n),
                              winner,
                            ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: DiceUpSpacing.xxs),
                    Text(
                      l10n.historyMatchLine(
                        _formatDate(match.playedAt, l10n),
                        _formatDuration(match.durationSeconds, l10n),
                        match.playerCount == 1
                            ? l10n.playersCountOne
                            : l10n.playersCountOther(match.playerCount),
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DiceUpSpacing.sm),
              Text(
                l10n.historyLocalBadge,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDetail(LocalMatch match) async {
    final l10n = stringsOf(context);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_formatDate(match.playedAt, l10n)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(
              label: l10n.labelMode,
              value: _modeLabel(match.mode, l10n),
            ),
            _DetailRow(
              label: l10n.labelPlayers,
              value: match.players
                  .map((player) {
                    final name = player.isAi
                        ? l10n.playerWithAi(player.name)
                        : player.name;
                    return match.winnerName == player.name
                        ? '$name${l10n.winnerSuffix}'
                        : name;
                  })
                  .join('\n'),
            ),
            _DetailRow(
              label: l10n.labelWinner,
              value: match.winnerName ?? l10n.historyNoWinner,
            ),
            _DetailRow(
              label: l10n.labelDuration,
              value: _formatDuration(match.durationSeconds, l10n),
            ),
            _DetailRow(label: l10n.labelRuleset, value: match.rulesetVersion),
            const SizedBox(height: DiceUpSpacing.sm),
            Text(
              l10n.historyLocalNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  static String _modeLabel(LocalMatchMode mode, AppLocalizations l10n) =>
      switch (mode) {
        LocalMatchMode.vsAi => l10n.modeShortVsAi,
        LocalMatchMode.localMultiplayer => l10n.modeLocal,
      };

  /// Short date without the intl package: "21 Nov 2026, 12:00".
  static String _formatDate(DateTime date, AppLocalizations l10n) {
    final months = monthNames(l10n);
    final local = date.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, '
        '$hour:$minute';
  }

  static String _formatDuration(int? seconds, AppLocalizations l10n) {
    if (seconds == null) return l10n.historyUnknownLength;
    if (seconds < 60) return l10n.historyDurationSeconds(seconds);
    return l10n.historyDurationMinutesSeconds(seconds ~/ 60, seconds % 60);
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
