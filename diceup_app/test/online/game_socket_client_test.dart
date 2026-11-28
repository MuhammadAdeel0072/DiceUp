import 'package:diceup/data/online/auth_models.dart';
import 'package:diceup/data/online/game_socket_client.dart';
import 'package:diceup/domain/online/connection_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// A scriptable stand-in for [io.Socket]: records handlers and emits,
/// fires `connect` / `connect_error` / `disconnect` on demand. The
/// production socket is never constructed in these tests.
class FakeSocket extends Fake implements io.Socket {
  bool failConnect = false;

  @override
  bool connected = false;

  final Map<String, List<Function>> handlers = {};
  final List<(String, dynamic)> emitted = [];

  @override
  Function() on(String event, Function handler) {
    (handlers[event] ??= []).add(handler);
    return () {};
  }

  @override
  void emit(String event, [dynamic data]) {
    emitted.add((event, data));
  }

  @override
  io.Socket connect() {
    if (failConnect) {
      connected = false;
      for (final handler in handlers['connect_error'] ?? []) {
        handler(<String, Object?>{
          'success': false,
          'error': <String, Object?>{
            'code': 'UNAUTHORIZED',
            'message': 'Invalid or expired access token.',
          },
        });
      }
      return this;
    }
    connected = true;
    for (final handler in handlers['connect'] ?? []) {
      handler(null);
    }
    return this;
  }

  @override
  void dispose() {
    connected = false;
  }

  void fire(String event, dynamic data) {
    for (final handler in handlers[event] ?? []) {
      handler(data);
    }
  }
}

void main() {
  const baseUrl = 'http://127.0.0.1:3000/v1';

  Map<String, Object?> roomUpdatedData() => <String, Object?>{
    'room': <String, Object?>{
      'id': 'room-1',
      'code': 'K7Q2XA',
      'hostId': 'host-1',
      'maxPlayers': 4,
      'status': 'open',
      'rulesetVersion': '1.0.0',
      'source': 'manual',
      'createdAt': '2026-11-28T00:00:00.000Z',
      'closedAt': null,
      'matchId': null,
    },
    'members': [
      <String, Object?>{
        'userId': 'host-1',
        'username': 'ada',
        'displayName': 'Ada',
        'isReady': false,
        'isHost': true,
        'joinedAt': '2026-11-28T00:00:00.000Z',
      },
    ],
    'ready': <String, Object?>{'host-1': false},
  };

  test(
    'connect uses the /game namespace with auto-reconnect + authFn',
    () async {
      late String usedUrl;
      late Map<String, dynamic> usedOptions;
      final fake = FakeSocket();
      final client = GameSocketClient(
        socketFactory: (url, options) {
          usedUrl = url;
          usedOptions = options;
          return fake;
        },
      );
      await client.connect(baseUrl: baseUrl, token: 'access-token');
      expect(usedUrl, 'http://127.0.0.1:3000/game');
      // Stage 6: the manager retries with back-off (1 s doubling to
      // 30 s); reconnection is enabled, not disabled.
      expect(usedOptions['reconnection'], isNot(false));
      expect(usedOptions['reconnectionDelay'], 1000);
      expect(usedOptions['reconnectionDelayMax'], 30000);
      // The auth is a function the manager calls on every (re)connect
      // attempt — not a frozen token.
      final authFn = usedOptions['auth'] as Function;
      Map? supplied;
      authFn((Map auth) {
        supplied = auth;
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(supplied?['token'], 'access-token');
      expect(client.isConnected, isTrue);
      expect(client.connectionState, GameSocketConnectionState.connected);
    },
  );

  test('authFn refreshes the token per attempt; null falls back', () async {
    late Map<String, dynamic> usedOptions;
    final fake = FakeSocket();
    var calls = 0;
    final client = GameSocketClient(
      socketFactory: (url, options) {
        usedOptions = options;
        return fake;
      },
    );
    await client.connect(
      baseUrl: baseUrl,
      token: 'access-token',
      tokenProvider: () async {
        calls++;
        return calls == 1 ? 'fresh-token' : null;
      },
    );
    final authFn = usedOptions['auth'] as Function;
    Map? first;
    authFn((Map auth) {
      first = auth;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(first?['token'], 'fresh-token');
    expect(calls, 1);
    Map? second;
    authFn((Map auth) {
      second = auth;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(second?['token'], 'fresh-token'); // last good token kept
    expect(calls, 2);
  });

  test('connect_error surfaces the envelope code', () async {
    final fake = FakeSocket()..failConnect = true;
    final client = GameSocketClient(socketFactory: (_, _) => fake);
    await expectLater(
      client.connect(baseUrl: baseUrl, token: 'bad-token'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'UNAUTHORIZED'),
      ),
    );
  });

  test(
    'room intents carry a UUID requestId; emit before connect throws',
    () async {
      final fake = FakeSocket();
      final client = GameSocketClient(socketFactory: (_, _) => fake);
      expect(
        () => client.emitRoomJoin('K7Q2XA'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'NETWORK_ERROR'),
        ),
      );
      await client.connect(baseUrl: baseUrl, token: 'access-token');
      client.emitRoomJoin('K7Q2XA');
      client.emitRoomReady('room-1', true);
      client.emitMatchStart('room-1');
      client.emitRoomLeave('room-1');
      expect(fake.emitted.map((e) => e.$1), [
        'room:join',
        'room:ready',
        'match:start',
        'room:leave',
      ]);
      for (final (_, payload) in fake.emitted) {
        final requestId = (payload as Map<String, Object?>)['requestId'];
        expect(
          requestId,
          matches(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ),
        );
      }
      expect(
        (fake.emitted[0].$2 as Map<String, Object?>)['roomCode'],
        'K7Q2XA',
      );
      expect((fake.emitted[1].$2 as Map<String, Object?>)['ready'], isTrue);
    },
  );

  test('room:updated is delivered as a RoomView', () async {
    final fake = FakeSocket();
    final client = GameSocketClient(socketFactory: (_, _) => fake);
    await client.connect(baseUrl: baseUrl, token: 'access-token');
    final seen = client.onRoomUpdated.first;
    fake.fire('room:updated', roomUpdatedData());
    final room = await seen;
    expect(room.code, 'K7Q2XA');
    expect(room.members, hasLength(1));
    expect(room.members[0].displayName, 'Ada');
  });

  test('match:started and matchmaking:matched are delivered', () async {
    final fake = FakeSocket();
    final client = GameSocketClient(socketFactory: (_, _) => fake);
    await client.connect(baseUrl: baseUrl, token: 'access-token');
    final startedFuture = client.onMatchStarted.first;
    final matchedFuture = client.onMatchmakingMatched.first;
    fake.fire('match:started', <String, Object?>{
      'matchId': 'match-1',
      'roomId': 'room-1',
      'seats': [
        <String, Object?>{'userId': 'a', 'seat': 0, 'colour': 'red'},
      ],
      'rulesetVersion': '1.0.0',
    });
    fake.fire('matchmaking:matched', <String, Object?>{
      'roomId': 'room-1',
      'roomCode': 'K7Q2XA',
    });
    final started = await startedFuture;
    expect(started.matchId, 'match-1');
    expect(started.seats[0].colour, 'red');
    final matched = await matchedFuture;
    expect(matched.roomCode, 'K7Q2XA');
  });

  test('exception events surface the envelope code', () async {
    final fake = FakeSocket();
    final client = GameSocketClient(socketFactory: (_, _) => fake);
    await client.connect(baseUrl: baseUrl, token: 'access-token');
    final seen = client.onSocketError.first;
    fake.fire('exception', <String, Object?>{
      'success': false,
      'error': <String, Object?>{
        'code': 'ROOM_FULL',
        'message': 'That room is full.',
      },
    });
    expect((await seen).code, 'ROOM_FULL');
  });

  test('disconnect fires onDisconnected and reports reconnecting', () async {
    final fake = FakeSocket();
    final client = GameSocketClient(socketFactory: (_, _) => fake);
    await client.connect(baseUrl: baseUrl, token: 'access-token');
    final seen = client.onDisconnected.first;
    fake.connected = false;
    fake.fire('disconnect', null);
    await seen;
    expect(client.connectionState, GameSocketConnectionState.reconnecting);
  });

  test('connection state reports connecting → connected → reconnecting → connected', () async {
    final fake = FakeSocket();
    final client = GameSocketClient(socketFactory: (_, _) => fake);
    final states = <GameSocketConnectionState>[];
    client.onConnectionState.listen(states.add);
    // The fake connects synchronously, so the getter is already
    // `connected` by the time this line runs — the `connecting`
    // transition is proven by the recorded stream below instead.
    final connecting = client.connect(baseUrl: baseUrl, token: 'access-token');
    await connecting;
    expect(client.connectionState, GameSocketConnectionState.connected);
    fake.connected = false;
    fake.fire('disconnect', null);
    expect(client.connectionState, GameSocketConnectionState.reconnecting);
    fake.connect();
    expect(client.connectionState, GameSocketConnectionState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(states, [
      GameSocketConnectionState.connecting,
      GameSocketConnectionState.connected,
      GameSocketConnectionState.reconnecting,
      GameSocketConnectionState.connected,
    ]);
  });

  test('reconnect re-subscribes to the room and re-requests state', () async {
    final fake = FakeSocket();
    final client = GameSocketClient(socketFactory: (_, _) => fake);
    await client.connect(baseUrl: baseUrl, token: 'access-token');
    client.onSequenced('token:moved', (_) {});
    client.emitRoomJoin('K7Q2XA');
    fake.fire('match:started', <String, Object?>{
      'matchId': 'match-1',
      'roomId': 'room-1',
      'seats': [
        <String, Object?>{'userId': 'a', 'seat': 0, 'colour': 'red'},
      ],
      'rulesetVersion': '1.0.0',
    });
    // One sequenced event lands, so lastSeq is 1.
    fake.fire('token:moved', <String, Object?>{'matchId': 'match-1', 'seq': 1});
    fake.connected = false;
    fake.fire('disconnect', null);
    expect(client.connectionState, GameSocketConnectionState.reconnecting);
    // The manager reconnects: the same socket fires connect again.
    fake.connect();
    expect(client.connectionState, GameSocketConnectionState.connected);
    final joins = fake.emitted.where((e) => e.$1 == 'room:join').toList();
    expect(joins, hasLength(2));
    expect((joins[1].$2 as Map<String, Object?>)['roomCode'], 'K7Q2XA');
    final stateRequests = fake.emitted
        .where((e) => e.$1 == 'state:request')
        .toList();
    expect(stateRequests, hasLength(1));
    expect(stateRequests[0].$2, {'matchId': 'match-1', 'lastSeq': 1});
  });

  test(
    'intents emitted while disconnected throw and are never replayed',
    () async {
      final fake = FakeSocket();
      final client = GameSocketClient(socketFactory: (_, _) => fake);
      await client.connect(baseUrl: baseUrl, token: 'access-token');
      client.emitRoomJoin('K7Q2XA');
      client.emitRoomReady('room-1', true);
      fake.fire('match:started', <String, Object?>{
        'matchId': 'match-1',
        'roomId': 'room-1',
        'seats': [
          <String, Object?>{'userId': 'a', 'seat': 0, 'colour': 'red'},
        ],
        'rulesetVersion': '1.0.0',
      });
      fake.connected = false;
      fake.fire('disconnect', null);
      expect(
        () => client.emitRoomReady('room-1', false),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'NETWORK_ERROR'),
        ),
      );
      fake.connect();
      // Re-subscription only: room:join again (+ state:request), but
      // the failed room:ready is NOT replayed.
      expect(fake.emitted.where((e) => e.$1 == 'room:ready'), hasLength(1));
      expect(fake.emitted.where((e) => e.$1 == 'room:join'), hasLength(2));
      expect(fake.emitted.where((e) => e.$1 == 'state:request'), hasLength(1));
    },
  );

  test('heartbeat pings while connected, stops on disconnect', () async {
    final fake = FakeSocket();
    final client = GameSocketClient(
      socketFactory: (_, _) => fake,
      heartbeatInterval: const Duration(milliseconds: 100),
    );
    await client.connect(baseUrl: baseUrl, token: 'access-token');
    expect(fake.emitted.where((e) => e.$1 == 'ping'), isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final pings = fake.emitted.where((e) => e.$1 == 'ping').length;
    expect(pings, greaterThanOrEqualTo(2));
    fake.connected = false;
    fake.fire('disconnect', null);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(fake.emitted.where((e) => e.$1 == 'ping'), hasLength(pings));
  });

  test(
    'manual disconnect stops reconnecting and clears re-subscription',
    () async {
      final fake = FakeSocket();
      final client = GameSocketClient(socketFactory: (_, _) => fake);
      await client.connect(baseUrl: baseUrl, token: 'access-token');
      client.emitRoomJoin('K7Q2XA');
      await client.disconnect();
      expect(client.connectionState, GameSocketConnectionState.disconnected);
      expect(client.isConnected, isFalse);
    },
  );
}
