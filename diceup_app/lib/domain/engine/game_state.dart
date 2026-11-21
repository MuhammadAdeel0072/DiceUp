import 'json_validation.dart';
import 'player.dart';
import 'ruleset_config.dart';

/// Turn state machine (SDD §6.4).
enum TurnPhase {
  /// Waiting for the active player to roll.
  awaitingRoll,

  /// A roll is outstanding; waiting for the active player (or AI) to
  /// choose one of the legal moves.
  awaitingMove,

  /// A player has won (BR-11); no further actions are possible.
  finished,
}

/// An immutable snapshot of a whole match (SDD §6.1).
///
/// Every transition takes a [GameState] and returns a new one; the UI,
/// the AI and the resume store all observe snapshots and never mutate
/// live state. A snapshot serialises to JSON, which is how resume
/// (SRS FR-29) and the shared rule test vectors (SDD §6.9) work.
///
/// Deserialization is strict (M1.1, D-22): [GameState.fromJson]
/// throws [FormatException] on any malformed or unsupported snapshot
/// instead of silently repairing it.
class GameState {
  const GameState({
    required this.players,
    required this.currentPlayerIndex,
    required this.rulesetVersion,
    this.ruleset = const RulesetConfig(),
    this.startedAt,
    this.phase = TurnPhase.awaitingRoll,
    this.lastRoll = 0,
    this.consecutiveSixes = 0,
    this.winnerIndex,
    this.moveCount = 0,
    this.lastRollWasThirdSix = false,
    this.lastRollHadNoLegalMove = false,
  });

  /// Players in clockwise seat order.
  final List<Player> players;

  /// Index into [players] of the player whose turn it is.
  final int currentPlayerIndex;

  /// Version of the frozen ruleset (BR-14).
  final String rulesetVersion;

  /// The frozen ruleset this match plays under (BR-14). Its [version]
  /// always agrees with [rulesetVersion]; [fromJson] rejects a
  /// snapshot where they disagree.
  final RulesetConfig ruleset;

  /// Wall-clock time the match started (M1.1). Used by the resume
  /// store to compute match duration. Null for states built directly
  /// in tests; stamped at match start by [GameState.initial].
  /// Required in persisted snapshots: [fromJson] rejects a missing
  /// `startedAt` (see [_startedAt]).
  final DateTime? startedAt;

  final TurnPhase phase;

  /// Most recent dice value (0 = no roll yet in this turn).
  final int lastRoll;

  /// Sixes rolled in the current turn sequence (BR-07).
  final int consecutiveSixes;

  /// Index of the winner once the match is finished (BR-11).
  final int? winnerIndex;

  /// Number of moves applied since the match started.
  final int moveCount;

  /// The last roll was a third consecutive six: it was shown but not
  /// played, and the turn passed (BR-07).
  final bool lastRollWasThirdSix;

  /// The last roll offered no legal move (BR-13).
  final bool lastRollHadNoLegalMove;

  Player get currentPlayer => players[currentPlayerIndex];
  bool get isFinished => phase == TurnPhase.finished;

  GameState copyWith({
    List<Player>? players,
    int? currentPlayerIndex,
    RulesetConfig? ruleset,
    DateTime? startedAt,
    TurnPhase? phase,
    int? lastRoll,
    int? consecutiveSixes,
    int? winnerIndex,
    int? moveCount,
    bool? lastRollWasThirdSix,
    bool? lastRollHadNoLegalMove,
  }) {
    return GameState(
      players: players ?? this.players,
      currentPlayerIndex: currentPlayerIndex ?? this.currentPlayerIndex,
      rulesetVersion: rulesetVersion,
      ruleset: ruleset ?? this.ruleset,
      startedAt: startedAt ?? this.startedAt,
      phase: phase ?? this.phase,
      lastRoll: lastRoll ?? this.lastRoll,
      consecutiveSixes: consecutiveSixes ?? this.consecutiveSixes,
      winnerIndex: winnerIndex ?? this.winnerIndex,
      moveCount: moveCount ?? this.moveCount,
      lastRollWasThirdSix: lastRollWasThirdSix ?? this.lastRollWasThirdSix,
      lastRollHadNoLegalMove:
          lastRollHadNoLegalMove ?? this.lastRollHadNoLegalMove,
    );
  }

  /// Initial state for a fresh match: all tokens in their yards.
  /// [startedAt] is stamped with the wall-clock time unless a fixed
  /// value is supplied (tests that need deterministic snapshots).
  factory GameState.initial({
    required List<Player> players,
    RulesetConfig ruleset = const RulesetConfig(),
    DateTime? startedAt,
  }) {
    return GameState(
      players: List.unmodifiable(players),
      currentPlayerIndex: 0,
      rulesetVersion: ruleset.version,
      ruleset: ruleset,
      startedAt: startedAt ?? DateTime.now(),
    );
  }

  Map<String, Object?> toJson() => {
        'formatVersion': 1,
        'rulesetVersion': rulesetVersion,
        'ruleset': ruleset.toJson(),
        'startedAt': startedAt?.toIso8601String(),
        'currentPlayerIndex': currentPlayerIndex,
        'phase': phase.name,
        'lastRoll': lastRoll,
        'consecutiveSixes': consecutiveSixes,
        'winnerIndex': winnerIndex,
        'moveCount': moveCount,
        'lastRollWasThirdSix': lastRollWasThirdSix,
        'lastRollHadNoLegalMove': lastRollHadNoLegalMove,
        'players': players.map((p) => p.toJson()).toList(),
      };

  /// Strict deserialization (M1.1, D-22).
  ///
  /// Throws [FormatException] — never a silent default, substitution,
  /// or type coercion — on: a missing/non-integer/`!= 1`
  /// `formatVersion`; a missing/invalid embedded `ruleset` (see
  /// [RulesetConfig.fromJson]); a `rulesetVersion` that disagrees with
  /// the embedded ruleset version; a missing/non-list `players`, a
  /// player count outside 2–4, a non-map player entry, duplicate
  /// colours, or zero human players; an out-of-range
  /// `currentPlayerIndex`; a `lastRoll` outside 0–6; a
  /// `consecutiveSixes` that the embedded ruleset could not have
  /// produced (negative, or `>= maxConsecutiveSixes` when the limit
  /// is enabled — the engine resets the count to 0 when the limit
  /// fires, so a persisted state never holds it; when the limit is
  /// disabled (`maxConsecutiveSixes: 0`, D-29) any count `>= 0` is
  /// legitimate); a negative `moveCount`; an unknown `phase`; a
  /// `winnerIndex` set while the phase is not finished, a
  /// missing/out-of-range `winnerIndex` while finished, or a
  /// non-integer `winnerIndex`; a missing, null, non-string, or
  /// not-a-complete-ISO-8601-date-time `startedAt` (persisted
  /// snapshots must carry a complete ISO-8601 date-time —
  /// `YYYY-MM-DDTHH:MM:SS` with optional fractional seconds and an
  /// optional `Z` or `±HH:MM` zone; date-only strings and
  /// out-of-range components are rejected — see
  /// [requireIso8601DateTime]); or any wrong-typed field.
  ///
  /// Unknown top-level keys are ignored (forward compatibility).
  /// No `moveHistory` is read or written (D-23).
  factory GameState.fromJson(Map<String, Object?> json) {
    final formatVersion = requireInt(json['formatVersion'], 'formatVersion');
    if (formatVersion != 1) {
      throw FormatException(
        'Unsupported snapshot formatVersion $formatVersion; expected 1.',
      );
    }
    final ruleset =
        RulesetConfig.fromJson(requireMap(json['ruleset'], 'ruleset'));
    final rulesetVersion = requireString(json['rulesetVersion'], 'rulesetVersion');
    if (ruleset.version != rulesetVersion) {
      throw FormatException(
        'Snapshot rulesetVersion "$rulesetVersion" does not match '
        'embedded ruleset version "${ruleset.version}".',
      );
    }
    final rawPlayers = requireList(json['players'], 'players');
    if (rawPlayers.length < 2 || rawPlayers.length > 4) {
      throw FormatException(
        'Snapshot must have 2–4 players (got ${rawPlayers.length}).',
      );
    }
    final players = List<Player>.generate(rawPlayers.length, (i) {
      final raw = requireMap(rawPlayers[i], 'players[$i]');
      return Player.fromJson(i, raw);
    });
    final colours = players.map((p) => p.colour).toSet();
    if (colours.length != players.length) {
      throw const FormatException(
        'Snapshot players must have distinct colours.',
      );
    }
    if (players.every((p) => p.isAi)) {
      throw const FormatException(
        'Snapshot must have at least one human player.',
      );
    }
    final currentPlayerIndex = requireIntInRange(
      json['currentPlayerIndex'],
      'currentPlayerIndex',
      0,
      players.length - 1,
    );
    final phase = requireEnum(json['phase'], 'phase', TurnPhase.values);
    final lastRoll = requireIntInRange(json['lastRoll'], 'lastRoll', 0, 6);
    // Ruleset-aware bound (M1.1 review): the engine resets the count
    // to 0 when the third-six limit fires (see LudoGame.rollDice), so
    // a persisted state can never hold a count >= the limit — except
    // when the limit is disabled (maxConsecutiveSixes: 0, D-29), where
    // the count grows without bound and any value >= 0 is legitimate.
    final consecutiveSixes =
        requireInt(json['consecutiveSixes'], 'consecutiveSixes');
    if (consecutiveSixes < 0 ||
        (ruleset.maxConsecutiveSixes > 0 &&
            consecutiveSixes >= ruleset.maxConsecutiveSixes)) {
      throw FormatException(
        'Snapshot consecutiveSixes $consecutiveSixes is impossible '
        'under ruleset maxConsecutiveSixes '
        '${ruleset.maxConsecutiveSixes}.',
      );
    }
    final moveCount = requireInt(json['moveCount'], 'moveCount');
    if (moveCount < 0) {
      throw const FormatException('Snapshot moveCount must not be negative.');
    }
    final lastRollWasThirdSix =
        requireBool(json['lastRollWasThirdSix'], 'lastRollWasThirdSix');
    final lastRollHadNoLegalMove = requireBool(
      json['lastRollHadNoLegalMove'],
      'lastRollHadNoLegalMove',
    );
    final winnerIndex = _winnerIndex(json, phase, players.length);
    final startedAt = _startedAt(json);
    return GameState(
      players: players,
      currentPlayerIndex: currentPlayerIndex,
      rulesetVersion: rulesetVersion,
      ruleset: ruleset,
      startedAt: startedAt,
      phase: phase,
      lastRoll: lastRoll,
      consecutiveSixes: consecutiveSixes,
      winnerIndex: winnerIndex,
      moveCount: moveCount,
      lastRollWasThirdSix: lastRollWasThirdSix,
      lastRollHadNoLegalMove: lastRollHadNoLegalMove,
    );
  }

  /// Winner consistency (BR-11): a finished match must name a winner
  /// in range; an unfinished match must not name one.
  static int? _winnerIndex(
    Map<String, Object?> json,
    TurnPhase phase,
    int playerCount,
  ) {
    final raw = json['winnerIndex'];
    if (raw == null) {
      if (phase == TurnPhase.finished) {
        throw const FormatException(
          'A finished snapshot must have a winnerIndex.',
        );
      }
      return null;
    }
    if (raw is! int) {
      throw const FormatException('Snapshot winnerIndex must be an integer.');
    }
    if (phase != TurnPhase.finished) {
      throw const FormatException(
        'Snapshot winnerIndex must be null while the match is not finished.',
      );
    }
    if (raw < 0 || raw >= playerCount) {
      throw FormatException('Snapshot winnerIndex $raw is out of range.');
    }
    return raw;
  }

  /// `startedAt` is required in a persisted snapshot: a missing key,
  /// a null, a non-string, or a string that is not a complete
  /// ISO-8601 date-time all throw [FormatException] (see
  /// [requireIso8601DateTime]). The accepted shape is
  /// `YYYY-MM-DDTHH:MM:SS` with optional fractional seconds and an
  /// optional `Z` or `±HH:MM` zone; the literal `T` separator is
  /// required, seconds are required, and every component is checked
  /// against its real range — [DateTime.tryParse] alone is not enough
  /// because it normalises out-of-range components (month 13 rolls
  /// into the next year) and accepts date-only strings. A naive
  /// date-time (no zone) is accepted because the snapshot writer
  /// emits `DateTime.now().toIso8601String()`, which has no zone
  /// suffix. An offset is converted to the same UTC instant. A leap
  /// second (60) is rejected — the writer never emits one. The
  /// [GameState] constructor itself keeps `startedAt` nullable so
  /// in-memory/test-only states can be built without a timestamp;
  /// only the persisted-snapshot path is strict.
  static DateTime _startedAt(Map<String, Object?> json) {
    if (!json.containsKey('startedAt')) {
      throw const FormatException('Snapshot startedAt is required.');
    }
    return requireIso8601DateTime(json['startedAt'], 'startedAt');
  }

  @override
  String toString() =>
      'GameState(player=$currentPlayerIndex phase=$phase '
      'roll=$lastRoll sixes=$consecutiveSixes winner=$winnerIndex)';
}
