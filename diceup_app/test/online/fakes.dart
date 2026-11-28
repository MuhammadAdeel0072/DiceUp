import 'dart:async';

import 'package:diceup/data/online/auth_api_client.dart';
import 'package:diceup/data/online/auth_config.dart';
import 'package:diceup/data/online/auth_models.dart';
import 'package:diceup/data/online/auth_service.dart';
import 'package:diceup/data/online/game_api_client.dart';
import 'package:diceup/data/online/game_models.dart';
import 'package:diceup/data/online/game_room_service.dart';
import 'package:diceup/data/online/game_socket_client.dart';
import 'package:diceup/domain/online/connection_state.dart';
import 'package:diceup/data/online/token_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory [TokenStorage] for tests: same contract as the secure
/// implementation, no platform channel, no persistence.
class InMemoryTokenStorage implements TokenStorage {
  AuthSession? _session;

  @override
  Future<void> saveSession(AuthSession session) async {
    _session = session;
  }

  @override
  Future<AuthSession?> readSession() async => _session;

  @override
  Future<void> clearSession() async {
    _session = null;
  }
}

/// A scriptable [AuthService] for widget/notifier tests: every
/// method either returns its scripted result or throws its scripted
/// [ApiException], and records calls. Defaults succeed with a
/// canned session. The underlying client never performs HTTP (the
/// mock answers 500 to anything, and no method reaches it).
class FakeAuthService extends AuthService {
  FakeAuthService()
    : super(
        client: AuthApiClient(
          config: const AuthConfig(baseUrl: 'http://127.0.0.1:1/v1'),
          httpClient: MockClient((_) async => http.Response('{}', 500)),
        ),
        storage: InMemoryTokenStorage(),
      );

  AuthSession? restoreResult;
  AuthSession Function()? loginResult;
  ApiException? loginError;
  AuthSession Function()? registerResult;
  ApiException? registerError;
  ApiException? verifyError;
  ApiException? resendError;
  ApiException? forgotError;
  ApiException? resetError;
  ApiException? changePasswordError;
  ApiException? fetchProfileError;
  ApiException? logoutError;
  OwnProfile? profileResult;

  int restoreCalls = 0;
  int loginCalls = 0;
  int registerCalls = 0;
  int verifyCalls = 0;
  int resendCalls = 0;
  int forgotCalls = 0;
  int resetCalls = 0;
  int changePasswordCalls = 0;
  int logoutCalls = 0;
  int fetchProfileCalls = 0;

  String? lastIdentifier;
  String? lastEmail;
  String? lastUsername;
  String? lastToken;

  static AuthSession cannedSession({bool verified = false}) {
    return AuthSession(
      user: AuthUser(
        id: '00000000-0000-0000-0000-000000000001',
        email: 'ada@example.com',
        username: 'ada',
        displayName: 'Ada',
        avatarKey: 'default',
        emailVerified: verified,
      ),
      tokens: const TokenPair(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresIn: 900,
      ),
      accessTokenExpiresAt: DateTime.now().add(const Duration(minutes: 14)),
    );
  }

  @override
  Future<AuthSession?> restoreSession() async {
    restoreCalls++;
    return restoreResult;
  }

  @override
  Future<AuthSession> login({
    required String identifier,
    required String password,
  }) async {
    loginCalls++;
    lastIdentifier = identifier;
    if (loginError != null) throw loginError!;
    return (loginResult ?? () => cannedSession())();
  }

  @override
  Future<AuthSession> register({
    required String email,
    required String username,
    required String password,
    String? displayName,
  }) async {
    registerCalls++;
    lastEmail = email;
    lastUsername = username;
    if (registerError != null) throw registerError!;
    return (registerResult ?? () => cannedSession())();
  }

  @override
  Future<void> verifyEmail({required String token}) async {
    verifyCalls++;
    lastToken = token;
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<void> resendVerification({required String email}) async {
    resendCalls++;
    lastEmail = email;
    if (resendError != null) throw resendError!;
  }

  @override
  Future<void> forgotPassword({required String email}) async {
    forgotCalls++;
    lastEmail = email;
    if (forgotError != null) throw forgotError!;
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    resetCalls++;
    lastToken = token;
    if (resetError != null) throw resetError!;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalls++;
    if (changePasswordError != null) throw changePasswordError!;
  }

  @override
  Future<OwnProfile> fetchProfile() async {
    fetchProfileCalls++;
    if (fetchProfileError != null) throw fetchProfileError!;
    return profileResult ??
        OwnProfile(
          user: cannedSession(verified: true).user,
          status: 'active',
          matchesPlayed: 3,
          matchesWon: 1,
          createdAt: DateTime.utc(2026, 1, 1),
        );
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    if (logoutError != null) throw logoutError!;
  }
}

/// A scriptable [GameRoomService] for lobby / matchmaking widget
/// tests: every method either returns its scripted result or throws
/// its scripted [ApiException], and records calls. The underlying
/// client never performs HTTP (the mock answers 500 to anything, and
/// no method reaches it); the socket is never connected — readiness
/// and match-start effects are simulated by pushing into the room /
/// match streams, exactly as the server broadcasts would.
///
/// Stage 7 adds the gameplay streams + intents: the controller and
/// game-screen tests push `match:state` / `dice:rolled` / … payloads
/// through the `emit*` helpers and assert on the recorded intents.
class FakeGameRoomService extends GameRoomService {
  FakeGameRoomService()
    : super(
        auth: FakeAuthService(),
        client: GameApiClient(
          config: const AuthConfig(baseUrl: 'http://127.0.0.1:1/v1'),
          httpClient: MockClient((_) async => http.Response('{}', 500)),
        ),
        socket: GameSocketClient(),
      );

  final _roomUpdates = StreamController<RoomView>.broadcast();
  final _matchStarted = StreamController<MatchStarted>.broadcast();
  final _matchmakingMatched = StreamController<MatchmakingMatched>.broadcast();
  final _matchState = StreamController<Map<String, Object?>>.broadcast();
  final _diceRolled = StreamController<Map<String, Object?>>.broadcast();
  final _tokenMoved = StreamController<Map<String, Object?>>.broadcast();
  final _turnChanged = StreamController<Map<String, Object?>>.broadcast();
  final _matchEnded = StreamController<Map<String, Object?>>.broadcast();
  final _actionRejected = StreamController<Map<String, Object?>>.broadcast();
  final _playerDisconnected =
      StreamController<Map<String, Object?>>.broadcast();
  final _playerReconnected = StreamController<Map<String, Object?>>.broadcast();
  final _playerForfeited = StreamController<Map<String, Object?>>.broadcast();
  final _connectionStates =
      StreamController<GameSocketConnectionState>.broadcast();

  int connectCalls = 0;

  /// The connection state the fake reports (tests drive it with
  /// [emitConnectionState]).
  GameSocketConnectionState fakeConnectionState =
      GameSocketConnectionState.disconnected;

  @override
  Future<void> connectSocket() async {
    connectCalls++;
  }

  @override
  Stream<RoomView> get roomUpdates => _roomUpdates.stream;

  @override
  Stream<MatchStarted> get matchStarted => _matchStarted.stream;

  @override
  Stream<MatchmakingMatched> get matchmakingMatched =>
      _matchmakingMatched.stream;

  @override
  Stream<Map<String, Object?>> get matchState => _matchState.stream;

  @override
  Stream<Map<String, Object?>> get diceRolled => _diceRolled.stream;

  @override
  Stream<Map<String, Object?>> get tokenMoved => _tokenMoved.stream;

  @override
  Stream<Map<String, Object?>> get turnChanged => _turnChanged.stream;

  @override
  Stream<Map<String, Object?>> get matchEnded => _matchEnded.stream;

  @override
  Stream<Map<String, Object?>> get actionRejected => _actionRejected.stream;

  @override
  Stream<Map<String, Object?>> get playerDisconnected =>
      _playerDisconnected.stream;

  @override
  Stream<Map<String, Object?>> get playerReconnected =>
      _playerReconnected.stream;

  @override
  Stream<Map<String, Object?>> get playerForfeited => _playerForfeited.stream;

  @override
  Stream<GameSocketConnectionState> get connectionStates =>
      _connectionStates.stream;

  @override
  GameSocketConnectionState get connectionState => fakeConnectionState;

  void emitConnectionState(GameSocketConnectionState next) {
    fakeConnectionState = next;
    _connectionStates.add(next);
  }

  /// Push a `match:state` payload into the controller, as the
  /// server would after a `state:request` or a reconnect.
  void emitMatchState(Map<String, Object?> payload) {
    _matchState.add(payload);
  }

  /// Push a `dice:rolled` payload into the controller.
  void emitDiceRolled(Map<String, Object?> payload) {
    _diceRolled.add(payload);
  }

  /// Push a `token:moved` payload into the controller.
  void emitTokenMoved(Map<String, Object?> payload) {
    _tokenMoved.add(payload);
  }

  /// Push a `turn:changed` payload into the controller.
  void emitTurnChanged(Map<String, Object?> payload) {
    _turnChanged.add(payload);
  }

  /// Push a `match:ended` payload into the controller.
  void emitMatchEnded(Map<String, Object?> payload) {
    _matchEnded.add(payload);
  }

  /// Push an `action:rejected` payload into the controller.
  void emitActionRejected(Map<String, Object?> payload) {
    _actionRejected.add(payload);
  }

  /// Push a `player:disconnected` payload into the controller.
  void emitPlayerDisconnected(Map<String, Object?> payload) {
    _playerDisconnected.add(payload);
  }

  /// Push a `player:reconnected` payload into the controller.
  void emitPlayerReconnected(Map<String, Object?> payload) {
    _playerReconnected.add(payload);
  }

  /// Push a `player:forfeited` payload into the controller.
  void emitPlayerForfeited(Map<String, Object?> payload) {
    _playerForfeited.add(payload);
  }

  int rollDiceCalls = 0;
  int moveTokenCalls = 0;
  int requestStateCalls = 0;
  int setActiveMatchCalls = 0;
  String? lastRollMatchId;
  String? lastMoveMatchId;
  String? lastMoveTokenId;
  String? lastStateMatchId;
  int? lastStateSeq;
  String? lastActiveMatchId;

  @override
  void setActiveMatch(String matchId) {
    setActiveMatchCalls++;
    lastActiveMatchId = matchId;
  }

  @override
  void rollDice(String matchId) {
    rollDiceCalls++;
    lastRollMatchId = matchId;
  }

  @override
  void moveToken(String matchId, String tokenId) {
    moveTokenCalls++;
    lastMoveMatchId = matchId;
    lastMoveTokenId = tokenId;
  }

  @override
  void requestMatchState(String matchId, int lastSeq) {
    requestStateCalls++;
    lastStateMatchId = matchId;
    lastStateSeq = lastSeq;
  }

  RoomView? scriptedRoom;
  ApiException? createError;
  ApiException? joinError;
  ApiException? readyError;
  ApiException? startError;
  ApiException? leaveError;
  ApiException? enterError;
  ApiException? queueError;
  Map<String, Object?>? queueJoinResult;
  MatchmakingStatus? scriptedStatus;

  int createCalls = 0;
  int joinCalls = 0;
  int leaveCalls = 0;
  int setReadyCalls = 0;
  int startCalls = 0;
  int queueJoinCalls = 0;
  int queueLeaveCalls = 0;

  int? lastMaxPlayers;
  String? lastCode;
  bool? lastReady;

  static RoomView cannedRoom({
    String code = 'K7Q2XA',
    String hostId = '00000000-0000-0000-0000-000000000001',
    List<RoomMember>? members,
  }) {
    return RoomView(
      id: '00000000-0000-0000-0000-000000000099',
      code: code,
      hostId: hostId,
      maxPlayers: 4,
      status: 'open',
      rulesetVersion: '1.0.0',
      source: 'manual',
      members:
          members ??
          [
            const RoomMember(
              userId: '00000000-0000-0000-0000-000000000001',
              username: 'ada',
              displayName: 'Ada',
              isReady: false,
              isHost: true,
              joinedAt: '2026-11-28T00:00:00.000Z',
            ),
          ],
      matchId: null,
    );
  }

  static RoomMember cannedMember(String userId, String name) => RoomMember(
    userId: userId,
    username: name.toLowerCase(),
    displayName: name,
    isReady: false,
    isHost: false,
    joinedAt: '2026-11-28T00:00:00.000Z',
  );

  @override
  RoomView? get currentRoom => scriptedRoom;

  /// Push a room update into the lobby, as a `room:updated`
  /// broadcast would.
  void emitRoom(RoomView room) {
    scriptedRoom = room;
    _roomUpdates.add(room);
  }

  void emitMatchStarted(MatchStarted started) {
    _matchStarted.add(started);
  }

  @override
  Future<RoomView> createRoom({required int maxPlayers}) async {
    createCalls++;
    lastMaxPlayers = maxPlayers;
    if (createError != null) throw createError!;
    final room = cannedRoom();
    scriptedRoom = room;
    return room;
  }

  @override
  Future<RoomView> joinRoom(String code) async {
    joinCalls++;
    lastCode = code;
    if (joinError != null) throw joinError!;
    final room = cannedRoom(code: code.toUpperCase());
    scriptedRoom = room;
    return room;
  }

  @override
  Future<RoomView> refreshCurrentRoom(String roomId) async {
    if (enterError != null) throw enterError!;
    final room = cannedRoom();
    scriptedRoom = room;
    return room;
  }

  @override
  Future<RoomView?> leaveRoom() async {
    leaveCalls++;
    if (leaveError != null) throw leaveError!;
    scriptedRoom = null;
    return null;
  }

  @override
  Future<void> setReady(bool ready) async {
    setReadyCalls++;
    lastReady = ready;
    if (readyError != null) throw readyError!;
    final room = scriptedRoom;
    if (room != null) {
      emitRoom(
        RoomView(
          id: room.id,
          code: room.code,
          hostId: room.hostId,
          maxPlayers: room.maxPlayers,
          status: room.status,
          rulesetVersion: room.rulesetVersion,
          source: room.source,
          members: room.members
              .map(
                (m) => m.userId == '00000000-0000-0000-0000-000000000001'
                    ? m.copyWith(isReady: ready)
                    : m,
              )
              .toList(),
          matchId: room.matchId,
        ),
      );
    }
  }

  @override
  Future<void> startMatch() async {
    startCalls++;
    if (startError != null) throw startError!;
    final room = scriptedRoom;
    if (room != null) {
      emitMatchStarted(
        MatchStarted(
          matchId: '00000000-0000-0000-0000-000000000077',
          roomId: room.id,
          seats: room.members
              .map(
                (m) => MatchSeat(
                  userId: m.userId,
                  seat: room.members.indexOf(m),
                  colour: 'red',
                ),
              )
              .toList(),
          rulesetVersion: room.rulesetVersion,
        ),
      );
    }
  }

  @override
  String inviteFriend(String userId) =>
      'Join my DiceUp room! Code: ${scriptedRoom?.code ?? '------'}';

  @override
  Future<Map<String, Object?>> joinMatchmaking() async {
    queueJoinCalls++;
    if (queueError != null) throw queueError!;
    return queueJoinResult ??
        const <String, Object?>{
          'matched': false,
          'position': 1,
          'queueSize': 1,
          'groupSize': 4,
        };
  }

  @override
  Future<Map<String, Object?>> leaveMatchmaking() async {
    queueLeaveCalls++;
    if (queueError != null) throw queueError!;
    return const <String, Object?>{'left': true};
  }

  @override
  Future<MatchmakingStatus> refreshMatchmakingStatus() async {
    if (queueError != null) throw queueError!;
    return scriptedStatus ??
        const MatchmakingStatus(
          status: 'idle',
          position: 0,
          queueSize: 0,
          groupSize: 4,
          roomId: null,
          roomCode: null,
        );
  }
}
