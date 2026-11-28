import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';

import 'auth_models.dart';
import 'game_models.dart';
import '../../domain/online/connection_state.dart';

/// Socket.IO client foundation for the `/game` namespace (Phase 5,
/// Stage 3; SDD §12.6), with Stage 6 auto-reconnect (FR-54/55,
/// NFR-32).
///
/// * JWT handshake auth, reusing the Stage 2 token storage via
///   [AuthService.freshAccessToken] (the caller supplies the token —
///   this client never reads secure storage itself).
/// * Every mutating intent carries a client-generated UUID `requestId`
///   (FR-53 idempotency); the server echoes it in `pong` / dedupes on it.
/// * Server events that carry an increasing `seq` are applied through
///   [OrderedEventBuffer] (FR-51): in order, stale ones ignored, a gap
///   triggers a `state:request` snapshot ask. Room events carry no
///   `seq` in §12.6, so they apply immediately; the ordering machinery
///   is exercised fully in Stage 5 when gameplay events land.
/// * Auto-reconnect with back-off (Stage 6): the socket.io manager
///   retries a dropped socket, starting at [reconnectDelay] and
///   doubling up to [reconnectDelayMax] (the manager's own back-off;
///   the values are asserted in tests, the doubling is the package's
///   documented behaviour). Each (re)connect attempt re-authenticates
///   through the `authFn` — the supplied [tokenProvider] is called so
///   an expired token is silently refreshed (Stage 2) instead of
///   retrying forever with a dead one. On reconnect the client
///   re-subscribes to its room (`room:join` with the stored code)
///   and asks for a snapshot (`state:request {matchId, lastSeq}`)
///   so the server's authoritative state replaces the local mirror.
/// * Heartbeat (Stage 6, G-13): while connected the client emits
///   `ping` every [heartbeatInterval]; the server treats the
///   heartbeat as presence (TTL 30 s) and marks a player
///   DISCONNECTED when it lapses.
/// * No duplicate intents: an intent emitted while disconnected
///   throws at the call site (nothing is queued), and a reconnect
///   never re-sends an intent — a pending intent is resolved by
///   the server's `requestId` dedup, or the state it would have
///   changed is re-fetched by the `state:request` above.
class GameSocketClient {
  GameSocketClient({
    io.Socket Function(String url, Map<String, dynamic> options)? socketFactory,
    Duration? heartbeatInterval,
  }) : _socketFactory =
           socketFactory ?? ((url, options) => io.io(url, options)),
       _heartbeatInterval = heartbeatInterval ?? defaultHeartbeatInterval;

  final io.Socket Function(String url, Map<String, dynamic> options)
  _socketFactory;

  /// Heartbeat interval used when the caller does not override it
  /// (the server's presence TTL is 30 s, so a 10 s ping keeps a
  /// live player present). Tests pass a short interval.
  final Duration _heartbeatInterval;

  /// Initial delay before the first reconnect attempt.
  static const Duration reconnectDelay = Duration(seconds: 1);

  /// Maximum delay between reconnect attempts (doubling caps here).
  static const Duration reconnectDelayMax = Duration(seconds: 30);

  /// Heartbeat cadence while connected (the server's presence TTL
  /// is 30 s, so a 10 s ping keeps a live player present).
  static const Duration defaultHeartbeatInterval = Duration(seconds: 10);

  io.Socket? _socket;
  final _roomUpdatedController = StreamController<RoomView>.broadcast();
  final _matchStartedController = StreamController<MatchStarted>.broadcast();
  final _matchmakingMatchedController =
      StreamController<MatchmakingMatched>.broadcast();
  final _socketErrorController = StreamController<ApiException>.broadcast();
  final _disconnectedController = StreamController<void>.broadcast();
  final _connectionStateController =
      StreamController<GameSocketConnectionState>.broadcast();
  // Gameplay streams (Phase 5, Stage 7): registered inside
  // [connect] on every fresh socket, so a reconnect (new socket
  // object) keeps them live. Sequenced ones run through the same
  // [OrderedEventBuffer] as [onSequenced] — in order, stale ones
  // ignored, a gap triggers a `state:request`.
  final _matchStateController =
      StreamController<Map<String, Object?>>.broadcast();
  final _actionRejectedController =
      StreamController<Map<String, Object?>>.broadcast();
  final _diceRolledController =
      StreamController<Map<String, Object?>>.broadcast();
  final _tokenMovedController =
      StreamController<Map<String, Object?>>.broadcast();
  final _turnChangedController =
      StreamController<Map<String, Object?>>.broadcast();
  final _matchEndedController =
      StreamController<Map<String, Object?>>.broadcast();
  final _playerDisconnectedController =
      StreamController<Map<String, Object?>>.broadcast();
  final _playerReconnectedController =
      StreamController<Map<String, Object?>>.broadcast();
  final _playerForfeitedController =
      StreamController<Map<String, Object?>>.broadcast();

  /// Live `room:updated` payloads (the room + members + ready map).
  Stream<RoomView> get onRoomUpdated => _roomUpdatedController.stream;

  /// Live `match:started` payloads.
  Stream<MatchStarted> get onMatchStarted => _matchStartedController.stream;

  /// Live `matchmaking:matched` payloads.
  Stream<MatchmakingMatched> get onMatchmakingMatched =>
      _matchmakingMatchedController.stream;

  /// Server `exception` events, mapped to [ApiException] by code.
  Stream<ApiException> get onSocketError => _socketErrorController.stream;

  /// Fired when the socket drops (the manager then retries, unless
  /// the drop was a manual [disconnect]).
  Stream<void> get onDisconnected => _disconnectedController.stream;

  /// Connection-state transitions (Stage 7 renders these).
  Stream<GameSocketConnectionState> get onConnectionState =>
      _connectionStateController.stream;

  /// Full `match:state` snapshots (FR-57): the authoritative state,
  /// replacing the client mirror wholesale. Not sequenced — the
  /// controller applies it only when its `seq` is not behind the
  /// snapshot it already holds.
  Stream<Map<String, Object?>> get onMatchState => _matchStateController.stream;

  /// `action:rejected` payloads (state unchanged): the rejected
  /// intent's code + message (+ `requestId` when supplied).
  Stream<Map<String, Object?>> get onActionRejected =>
      _actionRejectedController.stream;

  /// Sequenced gameplay broadcasts (FR-51).
  Stream<Map<String, Object?>> get onDiceRolled => _diceRolledController.stream;
  Stream<Map<String, Object?>> get onTokenMoved => _tokenMovedController.stream;
  Stream<Map<String, Object?>> get onTurnChanged =>
      _turnChangedController.stream;
  Stream<Map<String, Object?>> get onMatchEnded => _matchEndedController.stream;
  Stream<Map<String, Object?>> get onPlayerDisconnected =>
      _playerDisconnectedController.stream;
  Stream<Map<String, Object?>> get onPlayerReconnected =>
      _playerReconnectedController.stream;
  Stream<Map<String, Object?>> get onPlayerForfeited =>
      _playerForfeitedController.stream;

  GameSocketConnectionState _connectionState =
      GameSocketConnectionState.disconnected;

  GameSocketConnectionState get connectionState => _connectionState;

  bool get isConnected => _socket?.connected ?? false;

  /// Per-match sequence buffers (FR-51), one per match id.
  final Map<String, OrderedEventBuffer> _buffers = {};

  /// Token used for the last (re)connect attempt (authFn fallback
  /// when the provider returns null — e.g. signed out mid-match).
  String? _lastToken;

  /// Refreshes the access token for a (re)connect attempt, or null
  /// to keep the last token. Set per [connect] call.
  Future<String?> Function()? _tokenProvider;

  /// True once this socket instance has connected at least once —
  /// a later `connect` event is a reconnect, not the first handshake.
  bool _hasConnected = false;

  /// True after a manual [disconnect] (suppresses the reconnecting
  /// state — the manager is disposed, so no retry happens).
  bool _manualDisconnect = false;

  /// The room code of the room this client is in (re-subscription).
  String? _activeRoomCode;

  /// The match this client is playing (re-subscription + snapshot).
  String? _activeMatchId;

  /// Heartbeat timer (10 s `ping` while connected).
  Timer? _heartbeatTimer;

  /// Socket generation: incremented on every [connect]/[disconnect]
  /// so a disposed socket's parting `disconnect` event (the real
  /// socket fires one from `dispose()`) cannot reach the handlers
  /// of the socket that replaced it.
  int _generation = 0;

  void _setState(GameSocketConnectionState next) {
    if (_connectionState == next) return;
    _connectionState = next;
    _connectionStateController.add(next);
  }

  /// Connect with JWT handshake auth. Completes on `connect`; throws
  /// [ApiException] (code from the handshake envelope when present)
  /// when the handshake is refused — the socket is disposed, so a
  /// refused first handshake does not retry forever in the
  /// background; the caller retries [connect] explicitly. A previous
  /// socket is disposed first.
  ///
  /// [tokenProvider] is called for every (re)connect attempt the
  /// manager makes afterwards, so an expired token is silently
  /// refreshed instead of retried stale.
  Future<void> connect({
    required String baseUrl,
    required String token,
    Future<String?> Function()? tokenProvider,
  }) async {
    _manualDisconnect = false;
    _tokenProvider = tokenProvider;
    _lastToken = token;
    _hasConnected = false;
    _activeRoomCode = null;
    _activeMatchId = null;
    _stopHeartbeat();
    _generation++;
    final generation = _generation;
    _disposeSocket();
    _setState(GameSocketConnectionState.connecting);
    final socketUrl = _socketUrl(baseUrl);
    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .setAuthFn((callback) {
          unawaited(_refreshAuth().then((auth) => callback(auth)));
        })
        .setReconnectionDelay(reconnectDelay.inMilliseconds)
        .setReconnectionDelayMax(reconnectDelayMax.inMilliseconds)
        .setRandomizationFactor(0.5)
        .disableAutoConnect()
        .build();
    final socket = _socketFactory(socketUrl, options);
    _socket = socket;
    final connected = Completer<void>();
    ApiException? failure;
    socket.onConnect((_) {
      if (generation != _generation) return;
      _onSocketConnected();
      if (!connected.isCompleted) connected.complete();
    });
    socket.onConnectError((data) {
      if (generation != _generation) return;
      if (!connected.isCompleted) {
        // First handshake refused: fail fast (and stop the manager
        // retrying a dead token in the background).
        failure = _connectError(data);
        _disposeSocket();
        _setState(GameSocketConnectionState.disconnected);
        connected.completeError(failure!);
      }
      // A later connect_error is a failed reconnect attempt — the
      // manager keeps backing off and retries on its own.
    });
    socket.onDisconnect((_) {
      if (generation != _generation) return;
      _stopHeartbeat();
      _disconnectedController.add(null);
      if (!_manualDisconnect) {
        _setState(GameSocketConnectionState.reconnecting);
      }
    });
    socket.on('room:updated', (data) {
      final room = _roomFromEvent(data);
      if (room != null) _roomUpdatedController.add(room);
    });
    socket.on('match:started', (data) {
      if (data is Map<String, Object?>) {
        final started = MatchStarted.fromJson(data);
        _activeMatchId = started.matchId;
        _matchStartedController.add(started);
      }
    });
    socket.on('match:ended', (data) {
      if (data is Map<String, Object?>) {
        // The match is over: no more re-subscription for it.
        _activeMatchId = null;
        _matchEndedController.add(data);
      }
    });
    socket.on('match:state', (data) {
      if (data is Map<String, Object?>) _matchStateController.add(data);
    });
    socket.on('action:rejected', (data) {
      if (data is Map<String, Object?>) _actionRejectedController.add(data);
    });
    _registerSequenced(socket, 'dice:rolled', _diceRolledController);
    _registerSequenced(socket, 'token:moved', _tokenMovedController);
    _registerSequenced(socket, 'turn:changed', _turnChangedController);
    _registerSequenced(
      socket,
      'player:disconnected',
      _playerDisconnectedController,
    );
    _registerSequenced(
      socket,
      'player:reconnected',
      _playerReconnectedController,
    );
    _registerSequenced(socket, 'player:forfeited', _playerForfeitedController);
    socket.on('matchmaking:matched', (data) {
      if (data is Map<String, Object?>) {
        _matchmakingMatchedController.add(MatchmakingMatched.fromJson(data));
      }
    });
    socket.on('exception', (data) {
      _socketErrorController.add(_exception(data));
    });
    socket.connect();
    await connected.future;
  }

  /// Auth map for one (re)connect attempt: a fresh token from the
  /// provider when one is available, else the last token.
  Future<Map<String, Object?>> _refreshAuth() async {
    try {
      final fresh = await _tokenProvider?.call();
      if (fresh != null && fresh.isNotEmpty) _lastToken = fresh;
    } catch (_) {
      // Refresh failed (e.g. offline) — retry with the last token;
      // the server rejects it if expired and the manager retries.
    }
    return <String, Object?>{'token': _lastToken ?? ''};
  }

  /// A (re)connect landed: report it, (re)start the heartbeat, and
  /// — when this is a reconnect — re-subscribe to the room and ask
  /// the server for the authoritative state (FR-55).
  void _onSocketConnected() {
    final isReconnect = _hasConnected;
    _hasConnected = true;
    _setState(GameSocketConnectionState.connected);
    _startHeartbeat();
    if (!isReconnect) return;
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    final roomCode = _activeRoomCode;
    if (roomCode != null) {
      socket.emit('room:join', <String, Object?>{
        'roomCode': roomCode,
        'requestId': const Uuid().v4(),
      });
    }
    final matchId = _activeMatchId;
    if (matchId != null) {
      final lastSeq = _buffers[matchId]?.lastSeq ?? 0;
      socket.emit('state:request', <String, Object?>{
        'matchId': matchId,
        'lastSeq': lastSeq,
      });
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final socket = _socket;
      if (socket == null || !socket.connected) return;
      socket.emit('ping', <String, Object?>{'requestId': const Uuid().v4()});
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Register a handler for a future sequenced server event (FR-51):
  /// the payload must carry `matchId` + int `seq`. Events apply in
  /// order per match; a stale one is ignored; a gap emits
  /// `state:request {matchId, lastSeq}` and the event is NOT applied
  /// (the snapshot replaces the client mirror wholesale, Stage 5).
  void onSequenced(
    String event,
    void Function(Map<String, Object?> payload) handler,
  ) {
    final socket = _socket;
    if (socket == null) return;
    _registerSequenced(socket, event, null, handler: handler);
  }

  /// Shared sequenced registration (FR-51), used by [onSequenced]
  /// and by the fixed gameplay streams registered in [connect].
  /// Either [target] (a broadcast controller the payload is added
  /// to) or [handler] (a callback) receives the in-order payloads.
  void _registerSequenced(
    io.Socket socket,
    String event,
    StreamController<Map<String, Object?>>? target, {
    void Function(Map<String, Object?> payload)? handler,
  }) {
    socket.on(event, (data) {
      if (data is! Map<String, Object?>) return;
      final matchId = data['matchId'];
      final seq = data['seq'];
      if (matchId is! String || seq is! num) return;
      final buffer = _buffers.putIfAbsent(
        matchId,
        () => OrderedEventBuffer(
          onGap: (lastSeq) => _socket?.emit('state:request', <String, Object?>{
            'matchId': matchId,
            'lastSeq': lastSeq,
          }),
        ),
      );
      buffer.apply(seq.toInt(), () {
        target?.add(data);
        handler?.call(data);
      });
    });
  }

  /// The `/game` namespace URL for a REST base URL (`…/v1` stripped).
  static String socketUrlFor(String baseUrl) => _socketUrl(baseUrl);

  static String _socketUrl(String baseUrl) {
    final trimmed = baseUrl.endsWith('/v1')
        ? baseUrl.substring(0, baseUrl.length - 3)
        : baseUrl;
    return '$trimmed/game';
  }

  /// `room:join { roomCode, requestId }` (FR-44).
  void emitRoomJoin(String roomCode) {
    _activeRoomCode = roomCode;
    _emit('room:join', <String, Object?>{
      'roomCode': roomCode,
      'requestId': const Uuid().v4(),
    });
  }

  /// `room:leave { roomId, requestId }` (FR-59).
  void emitRoomLeave(String roomId) {
    _activeRoomCode = null;
    _activeMatchId = null;
    _emit('room:leave', <String, Object?>{
      'roomId': roomId,
      'requestId': const Uuid().v4(),
    });
  }

  /// `room:ready { roomId, ready, requestId }` (FR-46).
  void emitRoomReady(String roomId, bool ready) =>
      _emit('room:ready', <String, Object?>{
        'roomId': roomId,
        'ready': ready,
        'requestId': const Uuid().v4(),
      });

  /// `match:start { roomId, requestId }` (FR-47, host only).
  void emitMatchStart(String roomId) => _emit('match:start', <String, Object?>{
    'roomId': roomId,
    'requestId': const Uuid().v4(),
  });

  /// `dice:roll { matchId, requestId }` (FR-49): intent only — the
  /// server rolls. Throws [ApiException] (`NETWORK_ERROR`) while
  /// disconnected: nothing is queued, the caller retries.
  void emitDiceRoll(String matchId) => _emit('dice:roll', <String, Object?>{
    'matchId': matchId,
    'requestId': const Uuid().v4(),
  });

  /// `token:move { matchId, tokenId, requestId }` (FR-50): the token
  /// id (`"{seat}:{tokenIndex}"`), never a position. Throws while
  /// disconnected, as [emitDiceRoll].
  void emitTokenMove(String matchId, String tokenId) =>
      _emit('token:move', <String, Object?>{
        'matchId': matchId,
        'tokenId': tokenId,
        'requestId': const Uuid().v4(),
      });

  /// `state:request { matchId, lastSeq }` (FR-57): ask for the full
  /// snapshot. Throws while disconnected, as [emitDiceRoll].
  void emitStateRequest(String matchId, int lastSeq) => _emit(
    'state:request',
    <String, Object?>{'matchId': matchId, 'lastSeq': lastSeq},
  );

  /// Remember the match this client is playing, so a reconnect
  /// re-subscribes to it and re-requests its state (FR-55) — needed
  /// when the game screen is entered without a `match:started`
  /// broadcast in this session (e.g. after an app restart).
  void setActiveMatch(String matchId) {
    _activeMatchId = matchId;
  }

  void _emit(String event, Map<String, Object?> payload) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      throw const ApiException(
        code: 'NETWORK_ERROR',
        message: 'Not connected to the game server.',
      );
    }
    socket.emit(event, payload);
  }

  /// Manual disconnect: stops the manager retry loop, the
  /// heartbeat, and any re-subscription state.
  Future<void> disconnect() async {
    _manualDisconnect = true;
    _stopHeartbeat();
    _activeRoomCode = null;
    _activeMatchId = null;
    _generation++;
    _disposeSocket();
    _setState(GameSocketConnectionState.disconnected);
  }

  void _disposeSocket() {
    final socket = _socket;
    _socket = null;
    socket?.dispose();
  }

  /// Release the streams. The socket is disposed by [disconnect].
  void dispose() {
    _stopHeartbeat();
    _roomUpdatedController.close();
    _matchStartedController.close();
    _matchmakingMatchedController.close();
    _socketErrorController.close();
    _disconnectedController.close();
    _connectionStateController.close();
    _matchStateController.close();
    _actionRejectedController.close();
    _diceRolledController.close();
    _tokenMovedController.close();
    _turnChangedController.close();
    _matchEndedController.close();
    _playerDisconnectedController.close();
    _playerReconnectedController.close();
    _playerForfeitedController.close();
  }

  RoomView? _roomFromEvent(dynamic data) {
    if (data is! Map<String, Object?>) return null;
    // `room:updated` is { room, members[], ready{} }; the room view
    // is rebuilt from its parts (members live beside the room).
    final room = data['room'];
    final members = data['members'];
    if (room is! Map<String, Object?>) return null;
    return RoomView.fromJson(<String, Object?>{...room, 'members': members});
  }

  ApiException _connectError(dynamic data) {
    final code = _envelopeCode(data);
    return ApiException(
      code: code ?? 'UNAUTHORIZED',
      message: 'Could not connect to the game server.',
    );
  }

  ApiException _exception(dynamic data) {
    final code = _envelopeCode(data);
    return ApiException(
      code: code ?? 'INTERNAL_ERROR',
      message: 'The game server rejected the request.',
    );
  }

  String? _envelopeCode(dynamic data) {
    if (data is Map<String, Object?>) {
      final error = data['error'];
      if (error is Map<String, Object?>) {
        final code = error['code'];
        if (code is String) return code;
      }
      // socket.io-client hands connect_error data as the envelope
      // itself under `data` on the Error; the guard there may already
      // be unwrapped by the transport — accept a top-level code too.
      final code = data['code'];
      if (code is String) return code;
    }
    if (data is Error) {
      final raw = (data as dynamic).data;
      if (raw is Map<String, Object?>) return _envelopeCode(raw);
    }
    return null;
  }
}

/// In-order application of sequenced server events (FR-51, SDD §12.6).
///
/// The client applies broadcasts in sequence order and ignores any
/// event whose `seq` is not exactly last+1, requesting a snapshot on
/// a gap. One buffer per match; `lastSeq` starts at 0 (the
/// `match_started` event is seq 1).
class OrderedEventBuffer {
  OrderedEventBuffer({required this.onGap});

  /// Called with the last applied seq when a gap is detected.
  final void Function(int lastSeq) onGap;

  int lastSeq = 0;

  /// Apply [handle] when [seq] is exactly next; ignore stale or
  /// duplicate seqs; on a gap, call [onGap] and do NOT apply.
  void apply(int seq, void Function() handle) {
    if (seq == lastSeq + 1) {
      lastSeq = seq;
      handle();
    } else if (seq <= lastSeq) {
      // Stale / duplicate delivery — ignore, state already has it.
      return;
    } else {
      onGap(lastSeq);
    }
  }
}
