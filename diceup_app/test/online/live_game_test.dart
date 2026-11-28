import 'package:diceup/data/online/auth_api_client.dart';
import 'package:diceup/data/online/auth_config.dart';
import 'package:diceup/data/online/auth_models.dart';
import 'package:diceup/data/online/auth_service.dart';
import 'package:diceup/data/online/game_api_client.dart';
import 'package:diceup/data/online/game_room_service.dart';
import 'package:diceup/data/online/game_socket_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fakes.dart';

/// Live verification of the Flutter rooms + matchmaking layer against
/// the real Stage 3 backend.
///
/// Requires the local dev backend on http://127.0.0.1:3000 with a
/// scratch database (see the Stage 3 report). When the backend is not
/// reachable the tests SKIP with a reason instead of failing — a skip
/// here is not verification: the Stage 3 report records whether
/// these tests ran.
///
/// Users are deterministic (not unique per run) so a first run can
/// register them and a second run can log in after they have been
/// verified in the scratch DB — the socket flows require a verified
/// email (WsJwtGuard), and the dev mailer never logs the token, so
/// verification happens out of band (psql) between runs. The socket
/// tests SKIP with that reason when the user is still unverified.
///
/// Re-run reset (scratch DB + local Redis only): a started match has
/// no Stage 3 API to end it, so a re-run needs the users' game state
/// cleared first, plus the rate-limit windows reset:
///
///   PGPASSWORD=diceup_dev_local_only psql -h localhost -U diceup \
///     -d `<scratch-db>` -c \
///     "TRUNCATE move_events, match_players, matches, room_members, rooms CASCADE;"
///   redis-cli --scan --pattern "ratelimit:*" | xargs -r redis-cli DEL
///   redis-cli DEL matchmaking:queue
///
/// Register is 10/hr per IP, so repeated re-runs inside one hour
/// will 429 even after the reset — wait the window out instead.
void main() {
  const baseUrl = 'http://127.0.0.1:3000/v1';
  const password = 'LivePass!1';

  late bool backendUp;
  late AuthService hostAuth;
  late AuthService guestAuth;
  late AuthService mm1Auth;
  late AuthService mm2Auth;
  late AuthService mm3Auth;
  late AuthService mm4Auth;

  AuthService liveAuth(InMemoryTokenStorage storage) => AuthService(
    client: AuthApiClient(config: const AuthConfig(baseUrl: baseUrl)),
    storage: storage,
  );

  GameRoomService gameService(AuthService auth) => GameRoomService(
    auth: auth,
    client: GameApiClient(config: const AuthConfig(baseUrl: baseUrl)),
    socket: GameSocketClient(),
  );

  GameApiClient apiClient() =>
      GameApiClient(config: const AuthConfig(baseUrl: baseUrl));

  Future<AuthService> ensureUser(String email, String username) async {
    final service = liveAuth(InMemoryTokenStorage());
    try {
      await service.register(
        email: email,
        username: username,
        password: password,
        displayName: username,
      );
    } on ApiException {
      // Already registered by an earlier run — log in instead.
      await service.login(identifier: email, password: password);
    }
    return service;
  }

  setUpAll(() async {
    try {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:3000/v1/health'))
          .timeout(const Duration(seconds: 5));
      backendUp = response.statusCode == 200;
    } catch (_) {
      backendUp = false;
    }
    if (!backendUp) {
      // ignore: avoid_print
      print('live_game_test: backend not reachable — tests will skip.');
      return;
    }
    hostAuth = await ensureUser('live3-host@example.com', 'live3host');
    guestAuth = await ensureUser('live3-guest@example.com', 'live3guest');
    mm1Auth = await ensureUser('live3-mm1@example.com', 'live3mm1');
    mm2Auth = await ensureUser('live3-mm2@example.com', 'live3mm2');
    mm3Auth = await ensureUser('live3-mm3@example.com', 'live3mm3');
    mm4Auth = await ensureUser('live3-mm4@example.com', 'live3mm4');
  });

  /// Records the skip AND stops the test: `markTestSkipped` only
  /// sets the result — it does not abort the body, so a bare call
  /// would let the test run on into real calls and fail. Callers
  /// must `if (!requireBackend()) return;`.
  bool requireBackend() {
    if (backendUp) return true;
    markTestSkipped('local backend not reachable on 127.0.0.1:3000');
    return false;
  }

  /// Same contract as [requireBackend], for socket flows: the
  /// socket guard requires a verified email.
  bool requireVerified(AuthService auth) {
    if (!requireBackend()) return false;
    if (auth.session?.user.emailVerified == true) return true;
    markTestSkipped(
      'user ${auth.session?.user.email} is not verified — '
      'verify in the scratch DB and re-run',
    );
    return false;
  }

  group('live rooms + matchmaking against the real backend', () {
    test('REST rooms: create, join by code, leave, host closes', () async {
      if (!requireBackend()) return;
      final hostClient = apiClient();
      final guestClient = apiClient();
      final room = await hostAuth.callAuthenticated(
        (token) => hostClient.createRoom(accessToken: token, maxPlayers: 2),
      );
      expect(room.code, hasLength(6));
      expect(room.status, 'open');
      expect(room.members, hasLength(1));

      await expectLater(
        () => guestAuth.callAuthenticated(
          (token) => guestClient.joinRoom(accessToken: token, code: 'ZZZZZZ'),
        ),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'ROOM_NOT_FOUND'),
        ),
      );

      final joined = await guestAuth.callAuthenticated(
        (token) => guestClient.joinRoom(accessToken: token, code: room.code),
      );
      expect(joined.members, hasLength(2));

      final afterGuestLeft = await guestAuth.callAuthenticated(
        (token) => guestClient.leaveRoom(accessToken: token, roomId: room.id),
      );
      expect(afterGuestLeft.members, hasLength(1));

      final closed = await hostAuth.callAuthenticated(
        (token) => hostClient.leaveRoom(accessToken: token, roomId: room.id),
      );
      expect(closed.status, 'closed');
    });

    test('socket lobby: ready + start broadcasts match:started', () async {
      if (!requireVerified(hostAuth)) return;
      if (!requireVerified(guestAuth)) return;
      final hostGame = gameService(hostAuth);
      final guestGame = gameService(guestAuth);
      final room = await hostGame.createRoom(maxPlayers: 2);

      final hostSeesTwo = hostGame.roomUpdates.firstWhere(
        (r) => r.members.length == 2,
      );
      await guestGame.joinRoom(room.code);
      await hostSeesTwo.timeout(const Duration(seconds: 10));

      final allReady = hostGame.roomUpdates.firstWhere(
        (r) => r.members.length == 2 && r.members.every((m) => m.isReady),
      );
      await hostGame.setReady(true);
      await guestGame.setReady(true);
      await allReady.timeout(const Duration(seconds: 10));

      final startedFuture = guestGame.matchStarted.first;
      await hostGame.startMatch();
      final started = await startedFuture.timeout(const Duration(seconds: 10));
      expect(started.matchId, isNotEmpty);
      expect(started.seats, hasLength(2));
      expect(started.seats[0].userId, hostAuth.session!.user.id);
      expect(started.seats[0].colour, 'red');
      expect(started.seats[1].userId, guestAuth.session!.user.id);
      expect(started.seats[1].colour, 'green');
      expect(started.rulesetVersion, '1.0.0');
    });

    test('matchmaking: 4 players form one room', () async {
      if (!requireVerified(mm1Auth)) return;
      if (!requireVerified(mm2Auth)) return;
      if (!requireVerified(mm3Auth)) return;
      if (!requireVerified(mm4Auth)) return;
      final games = [
        gameService(mm1Auth),
        gameService(mm2Auth),
        gameService(mm3Auth),
        gameService(mm4Auth),
      ];
      // Connect first: the matched event arrives over the socket
      // while the first three players are waiting.
      for (final game in games) {
        await game.connectSocket();
      }
      final matchedFutures = games
          .map(
            (game) => game.matchmakingMatched.first.timeout(
              const Duration(seconds: 15),
            ),
          )
          .toList();
      final results = <Map<String, Object?>>[];
      for (final game in games) {
        results.add(await game.joinMatchmaking());
      }
      expect(results[0]['matched'], isFalse);
      expect(results[1]['matched'], isFalse);
      expect(results[2]['matched'], isFalse);
      expect(results[3]['matched'], isTrue);
      final matched = await Future.wait(matchedFutures);
      final codes = matched.map((m) => m.roomCode).toSet();
      expect(codes, hasLength(1));
      final room = results[3]['room'] as Map<String, Object?>;
      expect(room['code'], codes.single);
      expect((room['members'] as List).length, 4);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
