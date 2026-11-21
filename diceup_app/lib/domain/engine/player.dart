import '../ai/ai_player.dart';
import 'json_validation.dart';
import 'player_colour.dart';
import 'token.dart';

/// Human or AI seat (SRS FR-14, BR-01).
enum PlayerType { human, ai }

/// One seat in a match. Immutable; [tokens] is an unmodifiable view.
///
/// A match has 2–4 players with distinct colours and at least one
/// human seat (BR-01, FR-14). Each player owns exactly 4 tokens.
class Player {
  Player({
    required this.index,
    required this.name,
    required this.colour,
    required this.type,
    List<Token>? tokens,
  }) : tokens = List.unmodifiable(
          tokens ??
              List.generate(
                4,
                (i) => Token(playerIndex: index, index: i, colour: colour),
              ),
        ) {
    if (tokens != null && tokens.length != 4) {
      throw ArgumentError('A player must own exactly 4 tokens.');
    }
  }

  /// Seat index (0..3); also the turn-order position.
  final int index;

  final String name;
  final PlayerColour colour;
  final PlayerType type;

  /// The player's four tokens, in token-index order.
  final List<Token> tokens;

  bool get isHuman => type == PlayerType.human;
  bool get isAi => type == PlayerType.ai;

  /// Number of tokens that have reached home.
  int get tokensHome => tokens.where((t) => t.isHome).length;

  /// Winning condition (BR-11): all four tokens home.
  bool get hasWon => tokens.every((t) => t.isHome);

  Player copyWith({List<Token>? tokens}) => Player(
        index: index,
        name: name,
        colour: colour,
        type: type,
        tokens: tokens ?? this.tokens,
      );

  Map<String, Object> toJson() => {
        'name': name,
        'colour': colour.label,
        'type': type.name,
        'tokens': tokens.map((t) => t.toJson()).toList(),
      };

  /// Strict deserialization (M1.1, D-22): every field must be present
  /// with the correct type. An unknown colour or type label throws
  /// [FormatException] — it is never silently substituted with another
  /// colour and an unknown type never flips an AI seat to human.
  /// [tokens] must be a list of exactly four maps, checked before any
  /// [Player] is constructed, so a bad count throws [FormatException]
  /// rather than [ArgumentError] from the constructor.
  ///
  /// Returns an [AiPlayer] when the serialized type is `ai`. A missing
  /// difficulty defaults to [AiDifficulty.easy] (the setup default);
  /// a present-but-unknown difficulty throws [FormatException].
  factory Player.fromJson(int index, Map<String, Object?> json) {
    final name = requireString(json['name'], 'name');
    final colour =
        requireEnum(json['colour'], 'colour', PlayerColour.values);
    final type = requireEnum(json['type'], 'type', PlayerType.values);
    final rawTokens = requireList(json['tokens'], 'tokens');
    if (rawTokens.length != 4) {
      throw FormatException(
        'Player $index must have exactly 4 tokens '
        '(got ${rawTokens.length}).',
      );
    }
    final tokens = List<Token>.generate(4, (i) {
      final raw = requireMap(rawTokens[i], 'tokens[$i]');
      return Token.fromJson(
        playerIndex: index,
        index: i,
        colour: colour,
        json: raw,
      );
    });
    if (type == PlayerType.ai) {
      return AiPlayer(
        index: index,
        name: name,
        colour: colour,
        difficulty: _aiDifficulty(json),
        tokens: tokens,
      );
    }
    return Player(
      index: index,
      name: name,
      colour: colour,
      type: type,
      tokens: tokens,
    );
  }

  /// Reads an AI difficulty from a serialized player: absent (or null)
  /// means [AiDifficulty.easy]; a present value must name a known
  /// difficulty, otherwise [FormatException].
  static AiDifficulty _aiDifficulty(Map<String, Object?> json) {
    final raw = json['difficulty'];
    if (raw == null) return AiDifficulty.easy;
    return requireEnum(raw, 'difficulty', AiDifficulty.values);
  }
}

/// Seat configuration supplied at match setup (SDD §6.3).
class SeatConfig {
  const SeatConfig({
    required this.name,
    required this.colour,
    this.type = PlayerType.human,
    this.difficulty,
  });

  final String name;
  final PlayerColour colour;
  final PlayerType type;

  /// AI difficulty for an AI seat (M1.6: carried into the live
  /// state so snapshots preserve the true difficulty instead of
  /// defaulting to easy on resume). Ignored for human seats. Null
  /// means the setup default ([AiDifficulty.easy]).
  final AiDifficulty? difficulty;
}

/// Thrown when match setup is invalid (SDD §6.3): wrong player count,
/// duplicate colours, or no human seat. No match is created.
class InvalidMatchConfig implements Exception {
  const InvalidMatchConfig(this.message);
  final String message;
  @override
  String toString() => 'InvalidMatchConfig: $message';
}
