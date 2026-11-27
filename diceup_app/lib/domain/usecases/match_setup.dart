import '../ai/ai_player.dart';
import '../engine/player.dart';
import '../engine/player_colour.dart';
import '../engine/ruleset_config.dart';

/// Configuration for one offline match, in domain terms (M3.1).
///
/// Mirrors the presentation layer's `GameSetup` field for field —
/// player count, per-seat AI difficulties, per-seat names and
/// colours, and the frozen ruleset — but lives in the domain layer
/// so the use cases can consume it without importing Flutter:
/// `GameSetup` is declared in a file that imports
/// `package:flutter/material.dart`, and the domain layer must not
/// depend on the framework (SDD §4.2, §4.4).
///
/// The two types are intentionally kept in step (same defaults, same
/// resolution rules); M3.2 reconciles them — either by moving
/// `GameSetup` into the domain layer or by having the controller
/// translate `GameSetup` into this type at the boundary — and
/// removes the duplication. Until then, do not let them drift: a
/// rule that changes here must change there too.
class MatchSetup {
  const MatchSetup({
    required this.playerCount,
    required this.aiSeats,
    this.names = const <String>[],
    this.colours = const <PlayerColour>[],
    this.ruleset = const RulesetConfig(),
  });

  /// 2–4 players (FR-13). Validated by the engine at match start.
  final int playerCount;

  /// Seat index → AI difficulty for AI seats. Human seats are absent.
  /// At least one human seat is enforced at match start (FR-14).
  final Map<int, AiDifficulty> aiSeats;

  /// Per-seat display names (M2.2, D-28): trimmed, 1–12 characters,
  /// empty meaning "Player N". Duplicates are allowed — identity is
  /// seat + colour + shape, not name. May be shorter than
  /// [playerCount]; [nameFor] fills the gap.
  final List<String> names;

  /// Per-seat chosen colours (M2.2, H-08): distinct per seat, one of
  /// the four [PlayerColour] values. May be shorter than
  /// [playerCount]; [colourFor] fills the gap with the seat-order
  /// default.
  final List<PlayerColour> colours;

  /// The frozen ruleset this match plays under (M2.2, D-29).
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

  /// The engine seat configs for this setup: seat `i` is AI with its
  /// chosen difficulty when [aiSeats] names it, else human. An
  /// [aiSeats] key outside `0..playerCount-1` is ignored — exactly
  /// as the game screen's setup handling ignores it (it only looks
  /// up seats below the player count), never a silent extra seat.
  List<SeatConfig> get seats => List<SeatConfig>.generate(playerCount, (i) {
    final difficulty = aiSeats[i];
    return SeatConfig(
      name: nameFor(i),
      colour: colourFor(i),
      type: difficulty == null ? PlayerType.human : PlayerType.ai,
      difficulty: difficulty,
    );
  });
}
