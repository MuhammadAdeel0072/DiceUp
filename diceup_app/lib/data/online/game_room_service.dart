import 'dart:async';

import 'auth_models.dart';
import 'auth_service.dart';
import 'game_api_client.dart';
import 'game_models.dart';
import 'game_socket_client.dart';
import '../../domain/online/connection_state.dart';

/// Online rooms + matchmaking service (Phase 5, Stage 3; SDD §5.1.8
/// `GameRoomModule` API).
///
/// Owns the REST calls (via [AuthService.callAuthenticated] — silent
/// refresh + 401-retry, exactly as the auth screens use) and the
/// `/game` socket (JWT handshake via [AuthService.freshAccessToken]).
/// Screens never touch the client or the socket directly; the
/// Riverpod notifiers drive this service (see `app_providers.dart`).
///
/// * `createRoom(maxPlayers)`, `joinRoom(code)`, `leaveRoom()`,
///   `setReady(ready)`, `startMatch()` — the §5.1.8 API. REST creates
///   / joins / leaves the room; readiness and start are socket intents
///   (`room:ready`, `match:start`) so the lobby has one live authority.
/// * `inviteFriend(userId)` — room-code share ONLY (scope decision:
///   friend-graph invitations FR-60–62 are Stage 3, out of Phase 5).
///   The `userId` is accepted for §5.1.8 signature compatibility; the
///   invite is delivered by sharing the 6-char code, never by a
///   friend-graph lookup or a notification provider (none exists).
/// * Matchmaking (FR-45): `joinMatchmaking`, `leaveMatchmaking`,
///   `refreshMatchmakingStatus`. Group size 4, arrival order only;
///   a queue entry never expires on its own (G-6) — cancel explicitly.
/// * Gameplay (Stage 7): the match streams (`match:state`,
///   `dice:rolled`, `token:moved`, `turn:changed`, `match:ended`,
///   `action:rejected`, `player:*`) are exposed as-is from the
///   socket, and the intents (`rollDice`, `moveToken`,
///   `requestMatchState`) forward to it. The service owns no game
///   state — the `OnlineGameController` is the only mirror.
/// * Throws [ApiException] on failure; never throws a raw transport
///   error. The current room is kept here and re-emitted on every
///   `room:updated` so the lobby notifier has one source of truth.
class GameRoomService {
  GameRoomService({
    required AuthService auth,
    required GameApiClient client,
    required GameSocketClient socket,
  }) : _auth = auth,
       _client = client,
       _socket = socket {
    _socket.onRoomUpdated.listen((room) {
      _currentRoom = room;
      _roomUpdates.add(room);
    });
    _socket.onMatchStarted.listen(_matchStarted.add);
    _socket.onMatchmakingMatched.listen(_matchmakingMatched.add);
    _socket.onSocketError.listen(_socketErrors.add);
    _socket.onDisconnected.listen((_) {
      _disconnected.add(null);
    });
  }

  final AuthService _auth;
  final GameApiClient _client;
  final GameSocketClient _socket;

  final _roomUpdates = StreamController<RoomView>.broadcast();
  final _matchStarted = StreamController<MatchStarted>.broadcast();
  final _matchmakingMatched = StreamController<MatchmakingMatched>.broadcast();
  final _socketErrors = StreamController<ApiException>.broadcast();
  final _disconnected = StreamController<void>.broadcast();

  /// Live room state (REST results + `room:updated` broadcasts).
  Stream<RoomView> get roomUpdates => _roomUpdates.stream;

  /// Live `match:started` broadcasts.
  Stream<MatchStarted> get matchStarted => _matchStarted.stream;

  /// Live `matchmaking:matched` broadcasts.
  Stream<MatchmakingMatched> get matchmakingMatched =>
      _matchmakingMatched.stream;

  /// Server `exception` events from the socket.
  Stream<ApiException> get socketErrors => _socketErrors.stream;

  /// Socket drops (no auto-reconnect — Stage 6).
  Stream<void> get disconnected => _disconnected.stream;

  // -- Gameplay (Phase 5, Stage 7) ---------------------------------------
  //
  // Straight delegation to the socket client: the service adds no
  // interpretation, so the controller sees exactly what the server
  // sent (raw `Map` payloads; the controller parses them into
  // [MatchStateView] / [MatchEndedView] / [ActionRejectedView] /
  // [PlayerPresenceView]).

  /// Full `match:state` snapshots (FR-57).
  Stream<Map<String, Object?>> get matchState => _socket.onMatchState;

  /// `dice:rolled` broadcasts (FR-49).
  Stream<Map<String, Object?>> get diceRolled => _socket.onDiceRolled;

  /// `token:moved` broadcasts (FR-50).
  Stream<Map<String, Object?>> get tokenMoved => _socket.onTokenMoved;

  /// `turn:changed` broadcasts (FR-52).
  Stream<Map<String, Object?>> get turnChanged => _socket.onTurnChanged;

  /// `match:ended` broadcasts (FR-58).
  Stream<Map<String, Object?>> get matchEnded => _socket.onMatchEnded;

  /// `action:rejected` reports (state unchanged).
  Stream<Map<String, Object?>> get actionRejected => _socket.onActionRejected;

  /// `player:disconnected` broadcasts (FR-54).
  Stream<Map<String, Object?>> get playerDisconnected =>
      _socket.onPlayerDisconnected;

  /// `player:reconnected` broadcasts (FR-55).
  Stream<Map<String, Object?>> get playerReconnected =>
      _socket.onPlayerReconnected;

  /// `player:forfeited` broadcasts (FR-56).
  Stream<Map<String, Object?>> get playerForfeited => _socket.onPlayerForfeited;

  /// Connection-state transitions (Stage 7 renders these).
  Stream<GameSocketConnectionState> get connectionStates =>
      _socket.onConnectionState;

  /// The socket's current connection state.
  GameSocketConnectionState get connectionState => _socket.connectionState;

  /// Remember the match being played, for reconnect re-subscription
  /// (FR-55) when no `match:started` arrived in this session.
  void setActiveMatch(String matchId) => _socket.setActiveMatch(matchId);

  /// Roll the dice (FR-49). Throws [ApiException] (`NETWORK_ERROR`)
  /// while disconnected — nothing is queued.
  void rollDice(String matchId) => _socket.emitDiceRoll(matchId);

  /// Move one token (FR-50): `tokenId` is `"{seat}:{tokenIndex}"`.
  /// Throws while disconnected, as [rollDice].
  void moveToken(String matchId, String tokenId) =>
      _socket.emitTokenMove(matchId, tokenId);

  /// Ask for the full snapshot (FR-57). Throws while disconnected,
  /// as [rollDice].
  void requestMatchState(String matchId, int lastSeq) =>
      _socket.emitStateRequest(matchId, lastSeq);

  RoomView? _currentRoom;

  /// The room this client is currently in, if any.
  RoomView? get currentRoom => _currentRoom;

  bool get isSocketConnected => _socket.isConnected;

  // -- Rooms (SDD §5.1.8) ---------------------------------------------------

  /// Create a room (FR-43) and join its socket room for live updates.
  Future<RoomView> createRoom({required int maxPlayers}) async {
    final room = await _auth.callAuthenticated(
      (token) => _client.createRoom(accessToken: token, maxPlayers: maxPlayers),
    );
    _currentRoom = room;
    _roomUpdates.add(room);
    await _ensureSocketAndJoin(room.code);
    return room;
  }

  /// Join an open room by code (FR-44) and join its socket room.
  Future<RoomView> joinRoom(String code) async {
    final room = await _auth.callAuthenticated(
      (token) => _client.joinRoom(accessToken: token, code: code.trim()),
    );
    _currentRoom = room;
    _roomUpdates.add(room);
    await _ensureSocketAndJoin(room.code);
    return room;
  }

  /// Load a room by id (e.g. after a matchmaking match) and join its
  /// socket room for live updates. Used when entering the lobby for a
  /// room the client did not create or join via REST in this session.
  Future<RoomView> refreshCurrentRoom(String roomId) async {
    final room = await _auth.callAuthenticated(
      (token) => _client.getRoom(accessToken: token, roomId: roomId),
    );
    _currentRoom = room;
    _roomUpdates.add(room);
    await _ensureSocketAndJoin(room.code);
    return room;
  }

  /// Leave the current room (FR-59). No-op when not in a room.
  ///
  /// A room whose match is in progress is a forfeit (Stage 6,
  /// BR-15), not a room leave: REST refuses a playing room (409
  /// INVALID_STATE), so the socket intent is the only path — the
  /// gateway turns a mid-match `room:leave` into a forfeit. The
  /// caller (lobby / game screen) confirms with the player first:
  /// leaving forfeits the match for the leaver.
  Future<RoomView?> leaveRoom() async {
    final room = _currentRoom;
    if (room == null) return null;
    if (room.isPlaying) {
      await _ensureSocket();
      _socket.emitRoomLeave(room.id);
      _currentRoom = null;
      return null;
    }
    final left = await _auth.callAuthenticated(
      (token) => _client.leaveRoom(accessToken: token, roomId: room.id),
    );
    // Best-effort: the REST leave already succeeded, and a dropped
    // socket must not turn it into a failure.
    if (_socket.isConnected) {
      _socket.emitRoomLeave(room.id);
    }
    _currentRoom = null;
    return left;
  }

  /// Set readiness in the current room (FR-46, socket intent).
  Future<void> setReady(bool ready) async {
    final room = _currentRoom;
    if (room == null) {
      throw const ApiException(
        code: 'NOT_ROOM_MEMBER',
        message: 'You are not in a room.',
      );
    }
    await _ensureSocket();
    _socket.emitRoomReady(room.id, ready);
  }

  /// Start the match in the current room (FR-47, host only, socket
  /// intent). The server enforces host + ≥ 2 present + all ready.
  Future<void> startMatch() async {
    final room = _currentRoom;
    if (room == null) {
      throw const ApiException(
        code: 'NOT_ROOM_MEMBER',
        message: 'You are not in a room.',
      );
    }
    await _ensureSocket();
    _socket.emitMatchStart(room.id);
  }

  /// Invite a friend by sharing the room code (FR-48 minimum).
  ///
  /// Returns the share text for the current room. [userId] is accepted
  /// for the §5.1.8 signature but is NOT used to look anybody up:
  /// there is no friend graph in Phase 5 (FR-60–62 are Stage 3) and
  /// no notification provider, so the code itself is the invitation.
  String inviteFriend(String userId) {
    final room = _currentRoom;
    if (room == null) {
      throw const ApiException(
        code: 'NOT_ROOM_MEMBER',
        message: 'You are not in a room.',
      );
    }
    return 'Join my DiceUp room! Code: ${room.code}';
  }

  // -- Matchmaking (FR-45) ---------------------------------------------------

  /// Join the queue. Returns the raw join payload: `{matched: false,
  /// position, queueSize, groupSize}` while waiting, or
  /// `{matched: true, room}` when the group of 4 formed.
  Future<Map<String, Object?>> joinMatchmaking() => _auth.callAuthenticated(
    (token) => _client.joinMatchmaking(accessToken: token),
  );

  /// Cancel the queue entry. Returns `{left: true|false}`.
  Future<Map<String, Object?>> leaveMatchmaking() => _auth.callAuthenticated(
    (token) => _client.leaveMatchmaking(accessToken: token),
  );

  /// Current queue state (queued/matched/idle + position).
  Future<MatchmakingStatus> refreshMatchmakingStatus() =>
      _auth.callAuthenticated(
        (token) => _client.matchmakingStatus(accessToken: token),
      );

  // -- Socket lifecycle --------------------------------------------------------

  /// Connect the socket with a fresh token (no-op when already
  /// connected). Matchmaking needs this explicitly: the queue join is
  /// REST, so a waiting player would otherwise never receive the
  /// `matchmaking:matched` event when the group forms.
  Future<void> connectSocket() => _ensureSocket();

  Future<void> _ensureSocketAndJoin(String roomCode) async {
    await _ensureSocket();
    _socket.emitRoomJoin(roomCode);
  }

  Future<void> _ensureSocket() async {
    if (_socket.isConnected) return;
    final token = await _auth.freshAccessToken();
    if (token == null) {
      throw const ApiException(code: 'UNAUTHORIZED', message: 'Not signed in.');
    }
    // Stage 6: the socket re-authenticates on every reconnect
    // attempt through this provider (silent refresh when expired),
    // re-subscribes to the room, and re-requests match state.
    await _socket.connect(
      baseUrl: _client.baseUrl,
      token: token,
      tokenProvider: () => _auth.freshAccessToken(),
    );
  }

  void dispose() {
    _roomUpdates.close();
    _matchStarted.close();
    _matchmakingMatched.close();
    _socketErrors.close();
    _disconnected.close();
  }
}
