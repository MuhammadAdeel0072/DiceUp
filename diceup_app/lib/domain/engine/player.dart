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

  factory Player.fromJson(int index, Map<String, Object?> json) {
    final colour = PlayerColour.values.firstWhere(
      (c) => c.label == json['colour'],
      orElse: () => PlayerColour.values[index % PlayerColour.values.length],
    );
    final type = PlayerType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => PlayerType.human,
    );
    final tokenJson = (json['tokens'] as List?) ?? [];
    final tokens = List<Token>.generate(4, (i) {
      final raw = i < tokenJson.length
          ? tokenJson[i] as Map<String, Object?>
          : <String, Object?>{};
      return Token.fromJson(
        playerIndex: index,
        index: i,
        colour: colour,
        json: raw,
      );
    });
    return Player(
      index: index,
      name: json['name'] as String? ?? 'Player ${index + 1}',
      colour: colour,
      type: type,
      tokens: tokens,
    );
  }
}

/// Seat configuration supplied at match setup (SDD §6.3).
class SeatConfig {
  const SeatConfig({
    required this.name,
    required this.colour,
    this.type = PlayerType.human,
  });

  final String name;
  final PlayerColour colour;
  final PlayerType type;
}

/// Thrown when match setup is invalid (SDD §6.3): wrong player count,
/// duplicate colours, or no human seat. No match is created.
class InvalidMatchConfig implements Exception {
  const InvalidMatchConfig(this.message);
  final String message;
  @override
  String toString() => 'InvalidMatchConfig: $message';
}
