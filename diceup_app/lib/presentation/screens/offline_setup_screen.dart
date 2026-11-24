import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/accessibility/reduced_motion.dart';
import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../core/design_system/diceup_typography.dart';

import 'package:diceup/l10n/app_localizations.dart';

import '../../data/local/app_dependencies.dart';
import '../../domain/ai/ai_player.dart';
import '../../domain/engine/player_colour.dart';
import '../../domain/engine/ruleset_config.dart';
import '../../l10n/app_strings.dart';
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
  String _displayName(int seat, AppLocalizations l10n) {
    final typed = _nameControllers[seat].text.trim();
    return typed.isEmpty ? l10n.playerName(seat + 1) : typed;
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
  void _pickColour(int seat, PlayerColour colour, AppLocalizations l10n) {
    final taker = _colours.indexWhere((c) => c == colour);
    if (taker != -1 && taker != seat) {
      if (taker < _playerCount) {
        setState(
          () => _error = l10n.setupColourTaken(_displayName(taker, l10n)),
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

  void _startMatch(AppLocalizations l10n) {
    // Dismiss the keyboard: the match starts from the game screen,
    // and a lingering keyboard would cover its first paint (F10).
    FocusScope.of(context).unfocus();
    final names = List.generate(_playerCount, (i) => _displayName(i, l10n));
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
      error = l10n.setupDistinctColour;
    } else if (!_hasHumanSeat) {
      error = l10n.setupNeedHuman;
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
    final l10n = stringsOf(context);
    final modeTitle = _mode == OfflineMode.vsAi
        ? l10n.modeVsAi
        : l10n.modeLocal;
    if (_loadingPrefill) {
      return Scaffold(
        appBar: AppBar(title: Text(modeTitle)),
        body: LoadingIndicator(message: l10n.setupLoadingLast),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(modeTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: DiceUpSpacing.maxContentWidth,
            ),
            child: Padding(
              padding: DiceUpSpacing.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Players stays OUTSIDE the scrolling list: the
                  // control must always be in the tree, not only
                  // while it is on screen — a sliver drops a child
                  // that sends no keep-alive notification once it
                  // scrolls out of the cache extent, and the count
                  // is the one control the screen always needs.
                  SectionHeading(title: l10n.setupPlayers),
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
                  Expanded(
                    child: ListView(
                      // The list is short and bounded (at most four
                      // seat cards plus the ruleset card, ~2,600 dp
                      // worst case), so the whole form stays built:
                      // a below-fold control — the seat-1 AI
                      // difficulty dropdown, the ruleset switches —
                      // must exist as an element without scrolling
                      // first. With the default 250 dp cache extent
                      // the sliver drops a child just past the first
                      // paint — the seat-1 card starts a few dp past
                      // the initial cache window at 800x600 — so a
                      // finder for it came back empty until the list
                      // happened to scroll (the scripted results test
                      // failed exactly there: `ensureVisible` on the
                      // difficulty dropdown found no element).
                      // Building the whole bounded list costs a few
                      // dozen widgets. Note the cache alone does not
                      // make the controls findable: default finders
                      // skip sliver children outside the paint extent
                      // ("offstage"), so a lookup for a below-fold
                      // control also needs `skipOffstage: false`
                      // until it has been scrolled into view.
                      cacheExtent: 3000,
                      children: [
                        SectionHeading(title: l10n.setupSeats),
                        const SizedBox(height: DiceUpSpacing.xs),
                        for (int i = 0; i < _playerCount; i++) ...[
                          _buildSeatCard(i),
                          const SizedBox(height: DiceUpSpacing.sm),
                        ],
                        const SizedBox(height: DiceUpSpacing.sm),
                        SectionHeading(title: l10n.setupRules),
                        const SizedBox(height: DiceUpSpacing.xs),
                        _buildRulesetCard(),
                        const SizedBox(height: DiceUpSpacing.sm),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DiceUpSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 20,
                            color: DiceUpColors.error,
                          ),
                          const SizedBox(width: DiceUpSpacing.xs),
                          Expanded(
                            child: Text(
                              _error!,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: DiceUpColors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!_hasHumanSeat)
                    Padding(
                      padding: const EdgeInsets.only(bottom: DiceUpSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 20,
                            color: DiceUpColors.error,
                          ),
                          const SizedBox(width: DiceUpSpacing.xs),
                          Expanded(
                            child: Text(
                              l10n.setupNeedHuman,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: DiceUpColors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  PrimaryButton(
                    label: l10n.setupStartMatch,
                    onPressed: _hasHumanSeat ? () => _startMatch(l10n) : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One seat's card: avatar + name, name field, colour picker,
  /// human/AI choice and (for AI seats) difficulty.
  ///
  /// The header shows the seat's display name (live as the name is
  /// typed) with the "Player N" seat label underneath only while a
  /// custom name overrides it, plus a type chip (icon + Human/AI)
  /// so the seat type is readable without opening the segmented
  /// control. The name field scrolls itself into view when focused
  /// (F10): a focused field hidden behind the keyboard is scrolled
  /// to the middle of the visible list.
  Widget _buildSeatCard(int seat) {
    final isAi = _isAi[seat];
    final l10n = stringsOf(context);
    final displayName = _displayName(seat, l10n);
    final seatLabel = l10n.playerName(seat + 1);
    return DiceUpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlayerAvatar(
                name: displayName,
                seatIndex: seat,
                // The ring follows the seat's *chosen* colour (M2.2),
                // not the seat-order colour — after a swap they differ.
                colour: _colours[seat],
              ),
              const SizedBox(width: DiceUpSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (displayName != seatLabel)
                      Text(
                        seatLabel,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: DiceUpSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DiceUpSpacing.xs,
                  vertical: DiceUpSpacing.xxs,
                ),
                decoration: const BoxDecoration(
                  color: DiceUpColors.surfaceMuted,
                  borderRadius: DiceUpSpacing.radiusSmBorder,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAi ? Icons.smart_toy_outlined : Icons.person_outline,
                      size: 16,
                      color: DiceUpColors.textSecondary,
                    ),
                    const SizedBox(width: DiceUpSpacing.xxs),
                    Text(
                      isAi ? l10n.setupAi : l10n.setupHuman,
                      style: DiceUpTypography.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DiceUpSpacing.sm),
          Builder(
            builder: (fieldContext) => Focus(
              onFocusChange: (focused) {
                if (!focused) return;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  Scrollable.ensureVisible(
                    fieldContext,
                    alignment: 0.5,
                    duration: isReducedMotion(fieldContext)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                  );
                });
              },
              child: DiceUpTextField(
                key: ValueKey('seat-$seat-name'),
                label: l10n.setupNameLabel,
                controller: _nameControllers[seat],
                inputFormatters: [LengthLimitingTextInputFormatter(12)],
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(height: DiceUpSpacing.sm),
          Text(
            l10n.setupColourLabel,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: DiceUpSpacing.xs),
          Row(
            children: [
              for (final colour in PlayerColour.values)
                _buildColourSwatch(seat, colour),
            ],
          ),
          const SizedBox(height: DiceUpSpacing.xs),
          Text(
            l10n.setupColourSelected(colourName(_colours[seat], l10n)),
            style: DiceUpTypography.caption,
          ),
          const SizedBox(height: DiceUpSpacing.sm),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(l10n.setupHuman)),
              ButtonSegment(value: true, label: Text(l10n.setupAi)),
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
            // The difficulty belongs to the AI seat, not to the
            // form at large: it sits in a muted panel inside the
            // seat card so it reads as part of this seat's AI
            // configuration.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: DiceUpSpacing.sm,
                vertical: DiceUpSpacing.xxs,
              ),
              decoration: const BoxDecoration(
                color: DiceUpColors.surfaceMuted,
                borderRadius: DiceUpSpacing.radiusMdBorder,
              ),
              child: DropdownButtonFormField<AiDifficulty>(
                initialValue: _difficulty[seat],
                decoration: InputDecoration(
                  labelText: l10n.setupAiDifficultyLabel,
                ),
                items: AiDifficulty.values
                    .map(
                      (d) => DropdownMenuItem(
                        value: d,
                        child: Text(difficultyName(d, l10n)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _difficulty[seat] = value);
                  }
                },
              ),
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
    final l10n = stringsOf(context);
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
        ? l10n.setupColourSelected(colourName(colour, l10n))
        : isTaken
        ? l10n.setupColourTakenBy(
            colourName(colour, l10n),
            _displayName(taker, l10n),
          )
        : l10n.setupColourPlain(colourName(colour, l10n));
    return Semantics(
      button: true,
      selected: isSelected,
      label: swatchLabel,
      onTap: () => _pickColour(seat, colour, l10n),
      excludeSemantics: true,
      child: Tooltip(
        message: l10n.setupColourPlain(colourName(colour, l10n)),
        child: GestureDetector(
          key: ValueKey('seat-$seat-colour-${colour.name}'),
          onTap: () => _pickColour(seat, colour, l10n),
          child: Padding(
            padding: const EdgeInsets.only(right: DiceUpSpacing.sm),
            child: Opacity(
              opacity: isTaken ? 0.35 : 1.0,
              // Stronger selected state (F5): a teal outer ring
              // around the disc plus a thin white inner edge and
              // the check, so the selected colour reads at a glance
              // instead of only by a 2.5 px border. The disc stays
              // 48 dp (D-09). Premium v2: the disc is a lit dome
              // (the same treatment as the board tokens — light
              // top-left, colour, deep base) with a small drop
              // shadow, so the palette looks like the pieces the
              // player will actually place. Selection behaviour,
              // sizes and semantics are unchanged.
              child: Container(
                width: DiceUpSpacing.minTouchTarget,
                height: DiceUpSpacing.minTouchTarget,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: DiceUpColors.teal, width: 3)
                      : null,
                ),
                child: Padding(
                  padding: EdgeInsets.all(isSelected ? 2 : 0),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(-0.35, -0.35),
                        radius: 1.2,
                        colors: [
                          Color.lerp(
                            DiceUpColors.forColour(colour),
                            Colors.white,
                            0.22,
                          )!,
                          DiceUpColors.forColour(colour),
                          Color.lerp(
                            DiceUpColors.forColour(colour),
                            const Color(0xFF2A1608),
                            0.22,
                          )!,
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 3,
                          offset: Offset(0, 2),
                        ),
                      ],
                      border: isSelected
                          ? Border.all(color: Colors.white, width: 1.5)
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
        ),
      ),
    );
  }

  /// The ruleset section (M2.2, D-29): the curated user-facing subset
  /// with the stock defaults. "Continue to rank 2nd/3rd" is not
  /// offered — there are no mechanics for it (D-02).
  ///
  /// The six switches are grouped into two clusters with a divider
  /// between them (REDESIGN-PLAN.md §3.3/F5): release-and-finish
  /// rules first, then the extra-turn rules — so the card stops
  /// scanning as six identical toggles. The plain-language
  /// descriptions are kept verbatim. No "stock rules" reset button:
  /// there is no localised string for one, and the defaults are
  /// already what the switches show on first open.
  Widget _buildRulesetCard() {
    final l10n = stringsOf(context);
    return DiceUpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ruleSwitch(
            title: l10n.setupRuleReleaseOnOne,
            description: l10n.setupRuleReleaseOnOneDescription,
            value: _releaseOnOne,
            onChanged: (value) => setState(() => _releaseOnOne = value),
          ),
          _ruleSwitch(
            title: l10n.setupRuleExactFinish,
            description: l10n.setupRuleExactFinishDescription,
            value: _exactFinish,
            onChanged: (value) => setState(() => _exactFinish = value),
          ),
          _ruleSwitch(
            title: l10n.setupRuleThirdSix,
            description: l10n.setupRuleThirdSixDescription,
            value: _thirdSixLimit,
            onChanged: (value) => setState(() => _thirdSixLimit = value),
          ),
          const Divider(height: DiceUpSpacing.lg, color: DiceUpColors.border),
          _ruleSwitch(
            title: l10n.setupRuleExtraSix,
            description: l10n.setupRuleExtraSixDescription,
            value: _extraTurnOnSix,
            onChanged: (value) => setState(() => _extraTurnOnSix = value),
          ),
          _ruleSwitch(
            title: l10n.setupRuleExtraCapture,
            description: l10n.setupRuleExtraCaptureDescription,
            value: _extraTurnOnCapture,
            onChanged: (value) => setState(() => _extraTurnOnCapture = value),
          ),
          _ruleSwitch(
            title: l10n.setupRuleExtraHome,
            description: l10n.setupRuleExtraHomeDescription,
            value: _extraTurnOnHome,
            onChanged: (value) => setState(() => _extraTurnOnHome = value),
          ),
        ],
      ),
    );
  }

  /// One ruleset switch: title + plain-language description in the
  /// secondary style, edge-to-edge inside the card so the switch
  /// aligns with the card padding.
  Widget _ruleSwitch({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(description, style: Theme.of(context).textTheme.bodySmall),
      value: value,
      onChanged: onChanged,
    );
  }
}
