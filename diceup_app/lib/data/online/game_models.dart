/// Room / lobby / matchmaking models (Phase 5, Stage 3).
///
/// Shapes mirror the backend `RoomView` / `MatchStartedView` /
/// matchmaking-status payloads. Plain data only — no I/O, no Flutter.
library;

/// One member of a room, as the lobby renders them (FR-46).
class RoomMember {
  const RoomMember({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.isReady,
    required this.isHost,
    required this.joinedAt,
  });

  factory RoomMember.fromJson(Map<String, Object?> json) => RoomMember(
    userId: json['userId'] as String,
    username: json['username'] as String? ?? '',
    displayName:
        json['displayName'] as String? ?? json['username'] as String? ?? '',
    isReady: json['isReady'] as bool? ?? false,
    isHost: json['isHost'] as bool? ?? false,
    joinedAt: json['joinedAt'] as String? ?? '',
  );

  final String userId;
  final String username;
  final String displayName;
  final bool isReady;
  final bool isHost;
  final String joinedAt;

  RoomMember copyWith({bool? isReady, bool? isHost}) => RoomMember(
    userId: userId,
    username: username,
    displayName: displayName,
    isReady: isReady ?? this.isReady,
    isHost: isHost ?? this.isHost,
    joinedAt: joinedAt,
  );
}

/// A room with its members — the REST shape and the `room:updated`
/// payload's `room` + `members` (SDD §12.6).
class RoomView {
  const RoomView({
    required this.id,
    required this.code,
    required this.hostId,
    required this.maxPlayers,
    required this.status,
    required this.rulesetVersion,
    required this.source,
    required this.members,
    required this.matchId,
  });

  factory RoomView.fromJson(Map<String, Object?> json) {
    final members = json['members'];
    return RoomView(
      id: json['id'] as String,
      code: json['code'] as String,
      hostId: json['hostId'] as String,
      maxPlayers: (json['maxPlayers'] as num).toInt(),
      status: json['status'] as String? ?? 'open',
      rulesetVersion: json['rulesetVersion'] as String? ?? '',
      source: json['source'] as String? ?? 'manual',
      members: members is List
          ? members
                .whereType<Map<String, Object?>>()
                .map(RoomMember.fromJson)
                .toList()
          : const <RoomMember>[],
      matchId: json['matchId'] as String?,
    );
  }

  final String id;
  final String code;
  final String hostId;
  final int maxPlayers;
  final String status;
  final String rulesetVersion;
  final String source;
  final List<RoomMember> members;
  final String? matchId;

  bool get isOpen => status == 'open';
  bool get isPlaying => status == 'playing';

  /// FR-47: host + ≥ 2 present + all ready. The lobby enables Start
  /// only when this holds for the signed-in user.
  bool canStart(String userId) =>
      isOpen &&
      hostId == userId &&
      members.length >= 2 &&
      members.every((m) => m.isReady);

  /// Why Start is disabled, for the lobby hint (null when startable).
  String? startBlocker(String userId) {
    if (!isOpen) return 'started';
    if (hostId != userId) return 'notHost';
    if (members.length < 2) return 'needPlayers';
    if (members.any((m) => !m.isReady)) return 'needReady';
    return null;
  }
}

/// One seat of a started match (SDD §12.6 `match:started`).
class MatchSeat {
  const MatchSeat({
    required this.userId,
    required this.seat,
    required this.colour,
  });

  factory MatchSeat.fromJson(Map<String, Object?> json) => MatchSeat(
    userId: json['userId'] as String,
    seat: (json['seat'] as num).toInt(),
    colour: json['colour'] as String? ?? '',
  );

  final String userId;
  final int seat;
  final String colour;
}

/// The `match:started` broadcast payload (FR-47).
class MatchStarted {
  const MatchStarted({
    required this.matchId,
    required this.roomId,
    required this.seats,
    required this.rulesetVersion,
  });

  factory MatchStarted.fromJson(Map<String, Object?> json) {
    final seats = json['seats'];
    return MatchStarted(
      matchId: json['matchId'] as String,
      roomId: json['roomId'] as String,
      seats: seats is List
          ? seats
                .whereType<Map<String, Object?>>()
                .map(MatchSeat.fromJson)
                .toList()
          : const <MatchSeat>[],
      rulesetVersion: json['rulesetVersion'] as String? ?? '',
    );
  }

  final String matchId;
  final String roomId;
  final List<MatchSeat> seats;
  final String rulesetVersion;
}

/// Matchmaking queue state (FR-45).
class MatchmakingStatus {
  const MatchmakingStatus({
    required this.status,
    required this.position,
    required this.queueSize,
    required this.groupSize,
    required this.roomId,
    required this.roomCode,
  });

  factory MatchmakingStatus.fromJson(Map<String, Object?> json) =>
      MatchmakingStatus(
        status: json['status'] as String? ?? 'idle',
        position: (json['position'] as num?)?.toInt() ?? 0,
        queueSize: (json['queueSize'] as num?)?.toInt() ?? 0,
        groupSize: (json['groupSize'] as num?)?.toInt() ?? 4,
        roomId: json['roomId'] as String?,
        roomCode: json['roomCode'] as String?,
      );

  /// 'queued' | 'matched' | 'idle'.
  final String status;
  final int position;
  final int queueSize;
  final int groupSize;
  final String? roomId;
  final String? roomCode;

  bool get isQueued => status == 'queued';
  bool get isMatched => status == 'matched';
}

/// The `matchmaking:matched` socket payload (Stage 3 addition to §12.6).
class MatchmakingMatched {
  const MatchmakingMatched({required this.roomId, required this.roomCode});

  factory MatchmakingMatched.fromJson(Map<String, Object?> json) =>
      MatchmakingMatched(
        roomId: json['roomId'] as String,
        roomCode: json['roomCode'] as String,
      );

  final String roomId;
  final String roomCode;
}

// -- Online match state (Phase 5, Stage 7) ---------------------------------
//
// Shapes mirror the backend `match:state` / `match:ended` /
// `action:rejected` / `player:*` payloads (backend
// `src/match/match-payloads.ts`, SDD §12.6). Plain data only — the
// snapshot itself stays an unparsed `Map` here; the controller
// parses it into the Dart engine's [GameState] (the snapshot JSON
// is the engine's own format, TS mirrors Dart 1:1).

/// One player's presence/standing inside a `match:state` payload.
class MatchStatePlayer {
  const MatchStatePlayer({
    required this.userId,
    required this.seat,
    required this.colour,
    required this.disconnected,
    required this.graceEndsAt,
    required this.missedTurns,
    required this.result,
  });

  factory MatchStatePlayer.fromJson(Map<String, Object?> json) =>
      MatchStatePlayer(
        userId: json['userId'] as String,
        seat: (json['seat'] as num).toInt(),
        colour: json['colour'] as String? ?? '',
        disconnected: json['disconnected'] as bool? ?? false,
        graceEndsAt: json['graceEndsAt'] as String?,
        missedTurns: (json['missedTurns'] as num?)?.toInt() ?? 0,
        result: json['result'] as String?,
      );

  final String userId;
  final int seat;
  final String colour;

  /// True while the player is inside their disconnect grace.
  final bool disconnected;

  /// Grace deadline (ISO, Z-suffixed), or null while connected.
  final String? graceEndsAt;
  final int missedTurns;

  /// 'win' | 'loss' | 'forfeit', or null while the match runs.
  final String? result;

  MatchStatePlayer copyWith({
    bool? disconnected,
    String? graceEndsAt,
    bool clearGrace = false,
    int? missedTurns,
    String? result,
  }) => MatchStatePlayer(
    userId: userId,
    seat: seat,
    colour: colour,
    disconnected: disconnected ?? this.disconnected,
    graceEndsAt: clearGrace ? null : (graceEndsAt ?? this.graceEndsAt),
    missedTurns: missedTurns ?? this.missedTurns,
    result: result ?? this.result,
  );
}

/// The `match:state` payload (FR-57): the full snapshot, replacing
/// the client mirror wholesale, plus the turn and per-player
/// presence extras (Stage 6).
class MatchStateView {
  const MatchStateView({
    required this.matchId,
    required this.seq,
    required this.snapshot,
    required this.seats,
    required this.turnPlayerId,
    required this.turnEndsAt,
    required this.players,
  });

  factory MatchStateView.fromJson(Map<String, Object?> json) {
    final snapshot = json['snapshot'];
    final seats = json['seats'];
    final turn = json['turn'];
    final players = json['players'];
    final turnMap = turn is Map<String, Object?>
        ? turn
        : const <String, Object?>{};
    return MatchStateView(
      matchId: json['matchId'] as String,
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      snapshot: snapshot is Map<String, Object?>
          ? snapshot
          : const <String, Object?>{},
      seats: seats is List
          ? seats
                .whereType<Map<String, Object?>>()
                .map(MatchSeat.fromJson)
                .toList()
          : const <MatchSeat>[],
      turnPlayerId: turnMap['playerId'] as String?,
      turnEndsAt: turnMap['turnEndsAt'] as String?,
      players: players is List
          ? players
                .whereType<Map<String, Object?>>()
                .map(MatchStatePlayer.fromJson)
                .toList()
          : const <MatchStatePlayer>[],
    );
  }

  final String matchId;
  final int seq;

  /// The engine snapshot JSON (Dart [GameState] format).
  final Map<String, Object?> snapshot;
  final List<MatchSeat> seats;

  /// The player to move (null when the match has ended).
  final String? turnPlayerId;

  /// Deadline of the current turn (ISO, Z-suffixed), or null.
  final String? turnEndsAt;
  final List<MatchStatePlayer> players;
}

/// One row of the final standings (FR-58, `match:ended`).
class MatchStanding {
  const MatchStanding({
    required this.userId,
    required this.seat,
    required this.colour,
    required this.rank,
    required this.result,
    required this.tokensHome,
  });

  factory MatchStanding.fromJson(Map<String, Object?> json) => MatchStanding(
    userId: json['userId'] as String,
    seat: (json['seat'] as num).toInt(),
    colour: json['colour'] as String? ?? '',
    rank: (json['rank'] as num).toInt(),
    result: json['result'] as String? ?? 'loss',
    tokensHome: (json['tokensHome'] as num?)?.toInt() ?? 0,
  );

  final String userId;
  final int seat;
  final String colour;
  final int rank;

  /// 'win' | 'loss' | 'forfeit'.
  final String result;
  final int tokensHome;
}

/// The `match:ended` payload (FR-58).
class MatchEndedView {
  const MatchEndedView({
    required this.matchId,
    required this.winnerId,
    required this.standings,
  });

  factory MatchEndedView.fromJson(Map<String, Object?> json) {
    final standings = json['standings'];
    return MatchEndedView(
      matchId: json['matchId'] as String,
      winnerId: json['winnerId'] as String,
      standings: standings is List
          ? standings
                .whereType<Map<String, Object?>>()
                .map(MatchStanding.fromJson)
                .toList()
          : const <MatchStanding>[],
    );
  }

  final String matchId;
  final String winnerId;
  final List<MatchStanding> standings;
}

/// An `action:rejected` payload: the intent was refused, the state
/// is unchanged. Carries the backend error code — the UI maps it to
/// localised copy, never renders the raw code or message.
class ActionRejectedView {
  const ActionRejectedView({
    required this.matchId,
    required this.code,
    required this.message,
    required this.requestId,
  });

  factory ActionRejectedView.fromJson(Map<String, Object?> json) =>
      ActionRejectedView(
        matchId: json['matchId'] as String? ?? '',
        code: json['code'] as String? ?? 'INTERNAL_ERROR',
        message: json['message'] as String? ?? '',
        requestId: json['requestId'] as String?,
      );

  final String matchId;
  final String code;
  final String message;
  final String? requestId;
}

/// A `player:disconnected` / `player:reconnected` /
/// `player:forfeited` payload (Stage 6, FR-54/55/56).
class PlayerPresenceView {
  const PlayerPresenceView({
    required this.matchId,
    required this.playerId,
    required this.graceEndsAt,
  });

  factory PlayerPresenceView.fromJson(Map<String, Object?> json) =>
      PlayerPresenceView(
        matchId: json['matchId'] as String? ?? '',
        playerId: json['playerId'] as String,
        graceEndsAt: json['graceEndsAt'] as String?,
      );

  final String matchId;
  final String playerId;

  /// Grace deadline (ISO) — only on `player:disconnected`.
  final String? graceEndsAt;
}
