import '../ai/ai_player.dart';
import '../engine/player_colour.dart';

/// A local/guest seat identity (SDD §9.1 `local_players`, FR-14).
///
/// A convenience record for reusing a seat's name/colour/difficulty —
/// not an account. Immutable.
class LocalPlayerSeat {
  LocalPlayerSeat({
    this.id,
    required this.displayName,
    required this.colour,
    required this.isAi,
    this.difficulty,
    this.lastUsedAt,
  }) {
    if (id != null && id! < 1) {
      throw ArgumentError('A seat id must be at least 1.');
    }
    if (displayName.trim().isEmpty) {
      throw ArgumentError('A seat must have a non-empty display name.');
    }
    if (!isAi && difficulty != null) {
      throw ArgumentError('A human seat has no difficulty.');
    }
  }

  /// Row id; null before the seat is stored (assigned on insert,
  /// like AUTOINCREMENT).
  final int? id;

  /// Local nickname for the seat (e.g. 'Player 2').
  final String displayName;

  final PlayerColour colour;

  /// True for an AI seat, false for a human seat.
  final bool isAi;

  /// AI difficulty; null for human seats. A null difficulty on an AI
  /// seat means "unspecified" and is treated as easy where it is used
  /// (matching `Player.fromJson`, which defaults a missing difficulty
  /// to easy).
  final AiDifficulty? difficulty;

  /// When the seat was last used, or null when never recorded as used.
  final DateTime? lastUsedAt;

  LocalPlayerSeat copyWith({
    int? id,
    String? displayName,
    PlayerColour? colour,
    bool? isAi,
    AiDifficulty? difficulty,
    DateTime? lastUsedAt,
  }) => LocalPlayerSeat(
    id: id ?? this.id,
    displayName: displayName ?? this.displayName,
    colour: colour ?? this.colour,
    isAi: isAi ?? this.isAi,
    difficulty: difficulty ?? this.difficulty,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is LocalPlayerSeat &&
      other.id == id &&
      other.displayName == displayName &&
      other.colour == colour &&
      other.isAi == isAi &&
      other.difficulty == difficulty &&
      other.lastUsedAt == lastUsedAt;

  @override
  int get hashCode =>
      Object.hash(id, displayName, colour, isAi, difficulty, lastUsedAt);
}

/// Local/guest seat identities (SDD §4.3, §9.1 `local_players`).
///
/// All methods are async: the SQLite implementation (M1.4) is async,
/// so the contract is async from the start.
abstract class LocalPlayerRepository {
  /// Inserts [seat] when its id is null (a fresh id is assigned, like
  /// AUTOINCREMENT) or updates the stored seat with the same id when
  /// its id is present (inserting under that id when no such row
  /// exists). The stored seat is NOT stamped with the clock: the
  /// [LocalPlayerSeat.lastUsedAt] given by the caller is stored as
  /// given. Returns the stored seat.
  Future<LocalPlayerSeat> upsertSeat(LocalPlayerSeat seat);

  /// All stored seats, most-recently-used first: `lastUsedAt` DESC
  /// (seats with no `lastUsedAt` sort last), `id` DESC tiebreak.
  Future<List<LocalPlayerSeat>> listRecentSeats();
}
