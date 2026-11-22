import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../data/local/app_dependencies.dart';
import '../../domain/ai/ai_player.dart';
import '../../domain/engine/player_colour.dart';
import '../../domain/engine/ruleset_config.dart';
import '../app_dependencies_scope.dart';
import '../navigation/app_routes.dart';

/// Offline game setup (SRS UI-02, FR-12…FR-14, FR-41).
///
/// Collects player count (2–4), seat types (human/AI) and AI difficulty,
/// then starts the match. Rules enforced here, before the engine sees the
/// config: 2–4 players, distinct colours (automatic by seat), at least
/// one human seat (FR-14, BR-01). In "Play vs AI" mode seat 0 is human
/// and the rest are AI; in local mode every seat starts human and any
/// seat except the first may be switched to AI.
///
/// M2.2 (H-08, D-07, D-28, D-29) adds per-seat colour pickers and name
/// fields plus a ruleset section (curated subset: release-on-1, exact
/// finish, extra turn on six/capture/home, third-six limit — "Continue
/// to rank 2nd/3rd" is excluded, it has no mechanics, D-02). Names are
/// 1–12 characters, trimmed, empty meaning "Player N"; duplicates are
/// allowed because identity is seat + colour + shape, not name (D-28).
/// Validation failures surface as a visible error on this screen — the
/// engine never receives an invalid config, so it never has to throw
/// at the user.
///
/// Last-used prefill (SDD §5.1.14: the settings service "stores
/// last-used match options"; M1.6 splash loads "last-used defaults";
/// audit FR-41: "Persist last-used difficulty when DB lands"): when
/// dependencies are available the form is prefilled from the stored
/// `last_mode` / `last_player_count` / `last_difficulties` and the
/// chosen values are saved back on match start. The stored mode is
/// never allowed to override the mode the user just chose on the
/// mode-selection screen — the stored options only apply when they
/// belong to a match of that same mode. While the stored values load,
/// a loading state is shown instead of the form, so wrong defaults
/// are never flashed. Without dependencies (bare widget tests,
/// degraded startup) the form opens on the mode defaults immediately.
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

  /// Per-seat chosen colours (M2.2): seat-order defaults until the
  /// user picks. Always distinct — the picker refuses taken colours.
  late List<PlayerColour> _colours;

  /// Per-seat name fields (M2.2, D-28). Empty means "Player N"
  /// ([_displayName]); input is capped at 12 characters while typing.
  final List<TextEditingController> _nameControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );

  /// Curated ruleset subset (M2.2, D-29). Release-on-6 is not shown:
  /// it stays on — the stock ruleset releases on 6 (BR-04) and the
  /// toggle set never leaves the config without a release roll.
  bool _releaseOnOne = false;
  bool _exactFinish = true;
  bool _extraTurnOnSix = true;
  bool _extraTurnOnCapture = true;
  bool _extraTurnOnHome = true;

  /// Third-six limit on/off. On means [RulesetConfig]'s default
  /// (3 consecutive sixes, then the roll is not played); off means
  /// no limit (`maxConsecutiveSixes: 0`).
  bool _thirdSixLimit = true;

  /// The current validation / picker error, shown above Start.
  String? _error;

  /// The app dependencies, or null when the database is unavailable
  /// (degraded startup) or the screen runs outside [DiceUpApp]
  /// (bare widget tests): no prefill, no persistence, the form still
  /// works on the mode defaults.
  AppDependencies? _deps;

  /// True while the last-used options are loading (M2.2 prefill).
  /// The form is replaced by a loading state until the load lands,
  /// so the user never sees (or edits) the defaults first.
  bool _loadingPrefill = false;

  /// One-time initialisation guard (M2.1, L-01).
  ///
  /// [didChangeDependencies] is the only place the route arguments are
  /// readable — [ModalRoute.of] needs an inherited-widget lookup, which
  /// is unavailable in [initState] — but it re-runs whenever a
  /// dependency changes (rotation, keyboard, theme). Without this guard
  /// every such change silently reset the seat types and difficulties
  /// to the mode defaults, wiping the user's selections. The guard
  /// makes initialisation run exactly once, on the first call.
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    _mode = args is OfflineMode ? args : OfflineMode.vsAi;
    _isAi = List.generate(4, (i) => _mode == OfflineMode.vsAi && i > 0);
    _difficulty = List.filled(4, AiDifficulty.easy);
    _colours = List.generate(4, (i) => PlayerColour.values[i]);
    _deps = AppDependenciesScope.maybeOf(context)?.dependencies;
    if (_deps != null) {
      _loadingPrefill = true;
      unawaited(_loadLastUsed());
    }
  }

  @override
  void dispose() {
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _hasHumanSeat => _isAi.take(_playerCount).contains(false);

  /// Display name for [seat]: the trimmed field text, or "Player N"
  /// when the field is empty (D-28).
  String _displayName(int seat) {
    final typed = _nameControllers[seat].text.trim();
    return typed.isEmpty ? 'Player ${seat + 1}' : typed;
  }

  /// The ruleset the switches describe (M2.2, D-29).
  RulesetConfig _buildRuleset() => RulesetConfig(
    releaseOnOne: _releaseOnOne,
    extraTurnOnSix: _extraTurnOnSix,
    extraTurnOnCapture: _extraTurnOnCapture,
    extraTurnOnHome: _extraTurnOnHome,
    maxConsecutiveSixes: _thirdSixLimit ? 3 : 0,
    exactFinish: _exactFinish,
  );

  void _setPlayerCount(int count) {
    setState(() {
      _playerCount = count;
      // Keep at least one human: if the visible seats are all AI, the
      // first seat becomes human.
      if (!_hasHumanSeat) _isAi[0] = false;
    });
  }

  /// A colour tap (M2.2). A colour taken by another seat *in the
  /// match* cannot be picked: the tap is rejected with a visible
  /// error naming the seat that holds it, and the selection does not
  /// change. A colour held only by a seat outside the player count
  /// is swapped instead — the hidden seat takes this seat's old
  /// colour, so the four colours stay a permutation and the visible
  /// seats stay distinct no matter how the count changes. A free
  /// colour is picked immediately. The swatch is never silently
  /// inert — the user is always told why a tap did nothing.
  void _pickColour(int seat, PlayerColour colour) {
    final taker = _colours.indexWhere((c) => c == colour);
    if (taker != -1 && taker != seat) {
      if (taker < _playerCount) {
        setState(
          () => _error =
              'That colour is already taken by ${_displayName(taker)}.',
        );
        return;
      }
      setState(() {
        _colours[taker] = _colours[seat];
        _colours[seat] = colour;
        _error = null;
      });
      return;
    }
    setState(() {
      _colours[seat] = colour;
      _error = null;
    });
  }

  void _startMatch() {
    final names = List.generate(_playerCount, _displayName);
    final colours = List<PlayerColour>.generate(
      _playerCount,
      (i) => _colours[i],
    );
    final ruleset = _buildRuleset();
    final aiSeats = <int, AiDifficulty>{
      for (int i = 0; i < _playerCount; i++)
        if (_isAi[i]) i: _difficulty[i],
    };
    // Validate here, with a user-visible error — never hand the
    // engine an invalid config and let it throw (H-08). The picker
    // already prevents duplicate colours and the button is disabled
    // without a human seat, so these are defence-in-depth; the
    // ruleset check guards the config itself.
    String? error;
    if (colours.toSet().length != colours.length) {
      error = 'Each player needs a distinct colour.';
    } else if (!_hasHumanSeat) {
      error = 'At least one seat must be human.';
    } else {
      try {
        ruleset.validate();
      } on InvalidRulesetConfig catch (e) {
        error = e.message;
      }
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _error = null);
    // Remember this setup for next time (fire-and-forget: a storage
    // failure must never block starting the match).
    unawaited(_persistLastUsed());
    Navigator.of(context).pushNamed(
      AppRoutes.game,
      arguments: GameSetup(
        playerCount: _playerCount,
        aiSeats: aiSeats,
        names: names,
        colours: colours,
        ruleset: ruleset,
      ),
    );
  }

  // -- Last-used options (M2.2 prefill) ------------------------------------
  //
  // Serialisation format (no format existed before M2.2 — this is the
  // one the setup screen writes and reads, consistently):
  // * `last_mode`: 'vs_ai' or 'local_multiplayer' (the snake-case
  //   values the settings tests already use for 'vs_ai').
  // * `last_player_count`: '2', '3' or '4'.
  // * `last_difficulties`: a JSON array with one entry per seat
  //   (length 4, seat-indexed), each entry either a difficulty name
  //   ('easy' | 'medium' | 'hard', [AiDifficulty.name]) for an AI
  //   seat or `null` for a human seat — e.g.
  //   `["easy",null,"hard",null]` means seat 0 AI-easy, seat 1 human,
  //   seat 2 AI-hard, seat 3 human. A human seat's entry is `null`
  //   even when a difficulty was last used for that seat: the
  //   difficulty is only meaningful while the seat is AI, and the
  //   save merges it back (see [_persistLastUsed]) so flipping a seat
  //   to AI later restores its last-used difficulty.
  // A stored value that does not parse (bad JSON, wrong length, an
  // unknown difficulty name, a player count outside 2–4) is ignored
  // wholesale — the form falls back to the mode defaults, never to a
  // half-applied setup, and never throws.

  /// Loads the last-used options and prefills the form (M2.2).
  ///
  /// Only applies when the stored mode matches the mode the user
  /// chose on the mode-selection screen: the stored options belong
  /// to a match of that mode, and the mode itself is never
  /// overridden here. Any failure (no stored values, corrupt values,
  /// storage error) leaves the mode defaults in place.
  Future<void> _loadLastUsed() async {
    final repo = _deps?.settings;
    if (repo == null) {
      if (mounted) setState(() => _loadingPrefill = false);
      return;
    }
    try {
      final modeRaw = await repo.getSetting('last_mode');
      final countRaw = await repo.getSetting('last_player_count');
      final difficultiesRaw = await repo.getSetting('last_difficulties');
      if (!mounted) return;
      final storedMode = _modeFromStored(modeRaw);
      if (storedMode == _mode) {
        final count = int.tryParse(countRaw ?? '');
        final difficulties = _parseDifficulties(difficultiesRaw);
        setState(() {
          if (count != null && count >= 2 && count <= 4) {
            _playerCount = count;
            if (!_hasHumanSeat) _isAi[0] = false;
          }
          if (difficulties != null) {
            _difficulty = [
              for (final d in difficulties) d ?? AiDifficulty.easy,
            ];
          }
        });
      }
    } catch (_) {
      // Prefill is a convenience: a failed load keeps the defaults.
    }
    if (mounted) setState(() => _loadingPrefill = false);
  }

  /// Persists this match's options for the next setup (M2.2).
  ///
  /// Fire-and-forget and never throwing: a storage failure must
  /// never block starting the match. Difficulties merge with the
  /// previously stored array — a seat that is human in this match
  /// keeps its stored difficulty (if any) instead of being wiped to
  /// null, so flipping it to AI later restores what it last used.
  Future<void> _persistLastUsed() async {
    final deps = _deps;
    if (deps == null) return;
    try {
      final stored = _parseDifficulties(
        await deps.settings.getSetting('last_difficulties'),
      );
      final difficulties = <String?>[
        for (int i = 0; i < 4; i++)
          if (_isAi[i] && i < _playerCount)
            _difficulty[i].name
          else if (stored != null)
            stored[i]?.name
          else
            null,
      ];
      await deps.settings.setSetting(
        'last_mode',
        _mode == OfflineMode.vsAi ? 'vs_ai' : 'local_multiplayer',
      );
      await deps.settings.setSetting('last_player_count', '$_playerCount');
      await deps.settings.setSetting(
        'last_difficulties',
        jsonEncode(difficulties),
      );
    } catch (_) {
      // Last-used is a convenience; a failed save is silent.
    }
  }

  /// The stored `last_mode` value, or null when it is absent or
  /// unknown (then no prefill applies).
  OfflineMode? _modeFromStored(String? raw) => switch (raw) {
    'vs_ai' => OfflineMode.vsAi,
    'local_multiplayer' => OfflineMode.local,
    _ => null,
  };

  /// Parses a stored `last_difficulties` value (see the format note
  /// above). Returns null when the value is absent or malformed.
  /// A null entry stays null (a human seat); the caller maps it to
  /// the dormant [AiDifficulty.easy] default when applying it.
  List<AiDifficulty?>? _parseDifficulties(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.length != 4) return null;
      final result = <AiDifficulty?>[];
      for (final entry in decoded) {
        if (entry == null) {
          result.add(null);
        } else if (entry is String) {
          result.add(AiDifficulty.values.byName(entry));
        } else {
          return null;
        }
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final modeTitle = _mode == OfflineMode.vsAi
        ? 'Play vs AI'
        : 'Local multiplayer';
    if (_loadingPrefill) {
      return Scaffold(
        appBar: AppBar(title: Text(modeTitle)),
        body: const LoadingIndicator(message: 'Loading your last setup…'),
      );
    }
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
              onSelectionChanged: (selected) => _setPlayerCount(selected.first),
            ),
            const SizedBox(height: DiceUpSpacing.lg),
            Text('Seats', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: DiceUpSpacing.xs),
            Expanded(
              child: ListView.builder(
                itemCount: _playerCount + 1,
                itemBuilder: (context, index) {
                  if (index == _playerCount) return _buildRulesetCard();
                  return _buildSeatCard(index);
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: DiceUpSpacing.sm),
                child: Text(
                  _error!,
                  style: const TextStyle(color: DiceUpColors.error),
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

  /// One seat's card: name field, colour picker, human/AI switch and
  /// (for AI seats) difficulty.
  Widget _buildSeatCard(int seat) {
    final isAi = _isAi[seat];
    return DiceUpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlayerAvatar(
                name: _displayName(seat),
                seatIndex: seat,
                // The ring follows the seat's *chosen* colour (M2.2),
                // not the seat-order colour — after a swap they differ.
                colour: _colours[seat],
              ),
              const SizedBox(width: DiceUpSpacing.md),
              Expanded(
                child: Text(
                  'Player ${seat + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: DiceUpSpacing.sm),
          DiceUpTextField(
            key: ValueKey('seat-$seat-name'),
            label: 'Name',
            controller: _nameControllers[seat],
            inputFormatters: [LengthLimitingTextInputFormatter(12)],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: DiceUpSpacing.sm),
          Text('Colour', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: DiceUpSpacing.xs),
          Row(
            children: [
              for (final colour in PlayerColour.values)
                _buildColourSwatch(seat, colour),
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
              decoration: const InputDecoration(labelText: 'AI difficulty'),
              items: AiDifficulty.values
                  .map(
                    (d) => DropdownMenuItem(
                      value: d,
                      child: Text(
                        d.name[0].toUpperCase() + d.name.substring(1),
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
  }

  /// One colour swatch (M2.2). The seat's current colour carries a
  /// check; a colour taken by another seat is dimmed and cannot be
  /// picked (tapping it explains why — see [_pickColour]).
  Widget _buildColourSwatch(int seat, PlayerColour colour) {
    final isSelected = _colours[seat] == colour;
    final taker = _colours.indexWhere((c) => c == colour);
    // Only a seat in the match makes a colour "taken" — a colour
    // held by a seat outside the player count is swapped, not
    // rejected (see [_pickColour]), so it is not dimmed here.
    final isTaken = taker != -1 && taker != seat && taker < _playerCount;
    // Semantics (M2.9, NFR-08): the swatch is a labelled button —
    // the colour *name*, never the colour alone — with its state:
    // selected, or taken by the seat that holds it. The check icon
    // is decorative inside that node. The tooltip (visual
    // long-press hint) is unchanged.
    final swatchLabel = isSelected
        ? 'Colour ${colour.name}, selected'
        : isTaken
        ? 'Colour ${colour.name}, taken by ${_displayName(taker)}'
        : 'Colour ${colour.name}';
    return Semantics(
      button: true,
      selected: isSelected,
      label: swatchLabel,
      onTap: () => _pickColour(seat, colour),
      excludeSemantics: true,
      child: Tooltip(
        message: 'Colour ${colour.name}',
        child: GestureDetector(
          key: ValueKey('seat-$seat-colour-${colour.name}'),
          onTap: () => _pickColour(seat, colour),
          child: Padding(
            padding: const EdgeInsets.only(right: DiceUpSpacing.sm),
            child: Opacity(
              opacity: isTaken ? 0.35 : 1.0,
              child: Container(
                width: DiceUpSpacing.minTouchTarget,
                height: DiceUpSpacing.minTouchTarget,
                decoration: BoxDecoration(
                  color: DiceUpColors.forColour(colour),
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: DiceUpColors.textPrimary, width: 2.5)
                      : null,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 20, color: Colors.white)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The ruleset section (M2.2, D-29): the curated user-facing subset
  /// with the stock defaults. "Continue to rank 2nd/3rd" is not
  /// offered — there are no mechanics for it (D-02).
  Widget _buildRulesetCard() {
    return DiceUpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rules', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            title: const Text('Release on 1'),
            subtitle: const Text('A roll of 1 also releases a token.'),
            value: _releaseOnOne,
            onChanged: (value) => setState(() => _releaseOnOne = value),
          ),
          SwitchListTile(
            title: const Text('Exact finish'),
            subtitle: const Text('A token needs an exact roll to reach home.'),
            value: _exactFinish,
            onChanged: (value) => setState(() => _exactFinish = value),
          ),
          SwitchListTile(
            title: const Text('Extra turn on six'),
            subtitle: const Text('Rolling a 6 earns another roll.'),
            value: _extraTurnOnSix,
            onChanged: (value) => setState(() => _extraTurnOnSix = value),
          ),
          SwitchListTile(
            title: const Text('Extra turn on capture'),
            subtitle: const Text('Capturing a token earns another roll.'),
            value: _extraTurnOnCapture,
            onChanged: (value) => setState(() => _extraTurnOnCapture = value),
          ),
          SwitchListTile(
            title: const Text('Extra turn on home'),
            subtitle: const Text('Bringing a token home earns another roll.'),
            value: _extraTurnOnHome,
            onChanged: (value) => setState(() => _extraTurnOnHome = value),
          ),
          SwitchListTile(
            title: const Text('Third-six limit'),
            subtitle: const Text('Three sixes in a row forfeits the roll.'),
            value: _thirdSixLimit,
            onChanged: (value) => setState(() => _thirdSixLimit = value),
          ),
        ],
      ),
    );
  }
}
