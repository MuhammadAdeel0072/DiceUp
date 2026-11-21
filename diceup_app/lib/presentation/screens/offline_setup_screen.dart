import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../domain/ai/ai_player.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../navigation/app_routes.dart';

/// Offline game setup (SRS UI-02, FR-12…FR-14, FR-41).
///
/// Collects player count (2–4), seat types (human/AI) and AI difficulty,
/// then starts the match. Rules enforced here, before the engine sees the
/// config: 2–4 players, distinct colours (automatic by seat), at least
/// one human seat (FR-14, BR-01). In "Play vs AI" mode seat 0 is human
/// and the rest are AI; in local mode every seat starts human and any
/// seat except the first may be switched to AI.
class OfflineSetupScreen extends StatefulWidget {
  const OfflineSetupScreen({super.key});

  @override
  State<OfflineSetupScreen> createState() => _OfflineSetupScreenState();
}

class _OfflineSetupScreenState extends State<OfflineSetupScreen> {
  int _playerCount = 2;
  late List<bool> _isAi;
  late List<AiDifficulty> _difficulty;
  late OfflineMode _mode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    _mode = args is OfflineMode ? args : OfflineMode.vsAi;
    _isAi = List.generate(4, (i) => _mode == OfflineMode.vsAi && i > 0);
    _difficulty = List.filled(4, AiDifficulty.easy);
  }

  bool get _hasHumanSeat => _isAi.take(_playerCount).contains(false);

  void _setPlayerCount(int count) {
    setState(() {
      _playerCount = count;
      // Keep at least one human: if the visible seats are all AI, the
      // first seat becomes human.
      if (!_hasHumanSeat) _isAi[0] = false;
    });
  }

  void _startMatch() {
    final aiSeats = <int, AiDifficulty>{
      for (int i = 0; i < _playerCount; i++)
        if (_isAi[i]) i: _difficulty[i],
    };
    Navigator.of(context).pushNamed(
      AppRoutes.game,
      arguments: GameSetup(playerCount: _playerCount, aiSeats: aiSeats),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modeTitle =
        _mode == OfflineMode.vsAi ? 'Play vs AI' : 'Local multiplayer';
    return Scaffold(
      appBar: AppBar(title: Text(modeTitle)),
      body: Padding(
        padding: DiceUpSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Players', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: DiceUpSpacing.xs),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 3, label: Text('3')),
                ButtonSegment(value: 4, label: Text('4')),
              ],
              selected: {_playerCount},
              onSelectionChanged: (selected) =>
                  _setPlayerCount(selected.first),
            ),
            const SizedBox(height: DiceUpSpacing.lg),
            Text('Seats', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: DiceUpSpacing.xs),
            Expanded(
              child: ListView.builder(
                itemCount: _playerCount,
                itemBuilder: (context, seat) {
                  final isAi = _isAi[seat];
                  return DiceUpCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            PlayerAvatar(
                              name: 'Player ${seat + 1}',
                              seatIndex: seat,
                            ),
                            const SizedBox(width: DiceUpSpacing.md),
                            Expanded(
                              child: Text(
                                'Player ${seat + 1}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: DiceUpColors.playerColor(seat),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: DiceUpSpacing.sm),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('Human')),
                            ButtonSegment(value: true, label: Text('AI')),
                          ],
                          selected: {isAi},
                          onSelectionChanged: (selected) {
                            setState(() {
                              _isAi[seat] = selected.first;
                              if (!_hasHumanSeat) _isAi[0] = false;
                            });
                          },
                        ),
                        if (isAi) ...[
                          const SizedBox(height: DiceUpSpacing.sm),
                          DropdownButtonFormField<AiDifficulty>(
                            initialValue: _difficulty[seat],
                            decoration: const InputDecoration(
                              labelText: 'AI difficulty',
                            ),
                            items: AiDifficulty.values
                                .map(
                                  (d) => DropdownMenuItem(
                                    value: d,
                                    child: Text(
                                      d.name[0].toUpperCase() +
                                          d.name.substring(1),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _difficulty[seat] = value);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            if (!_hasHumanSeat)
              const Padding(
                padding: EdgeInsets.only(bottom: DiceUpSpacing.sm),
                child: Text(
                  'At least one seat must be human.',
                  style: TextStyle(color: DiceUpColors.error),
                ),
              ),
            PrimaryButton(
              label: 'Start match',
              onPressed: _hasHumanSeat ? _startMatch : null,
            ),
          ],
        ),
      ),
    );
  }
}
