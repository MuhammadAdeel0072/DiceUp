import 'package:diceup/data/online/auth_api_client.dart';
import 'package:diceup/data/online/auth_config.dart';
import 'package:diceup/data/online/auth_models.dart';
import 'package:diceup/data/online/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fakes.dart';

/// Live verification of the Flutter auth layer against the real
/// Phase 4 backend (Stage 2 exit evidence).
///
/// Requires the local dev backend on http://127.0.0.1:3000 with a
/// scratch database (see the Stage 2 report). When the backend is
/// not reachable the tests SKIP with a reason instead of failing —
/// the offline suite must stay green without a backend — but a skip
/// here is not verification: the Stage 2 report records whether
/// these tests ran.
///
/// One user is shared by the whole file: the backend throttles
/// login failures at 5 / 15 min per IP, so failure probes are kept
/// to two (wrong password, unregistered email).
void main() {
  const baseUrl = 'http://127.0.0.1:3000/v1';

  late bool backendUp;

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
      print('live_auth_test: backend not reachable — tests will skip.');
    }
  });

  AuthService liveService(InMemoryTokenStorage storage) => AuthService(
    client: AuthApiClient(config: const AuthConfig(baseUrl: baseUrl)),
    storage: storage,
  );

  var counter = 0;
  String uniqueTag() =>
      'live${DateTime.now().millisecondsSinceEpoch}${counter++}';

  late InMemoryTokenStorage storage;
  late AuthService service;
  late String email;
  late String username;
  late String password;

  setUpAll(() async {
    if (!backendUp) return;
    storage = InMemoryTokenStorage();
    service = liveService(storage);
    final tag = uniqueTag();
    email = '$tag@example.com';
    username = 'u_$tag';
    password = 'CorrectHorse!9';
    await service.register(
      email: email,
      username: username,
      password: password,
      displayName: 'Live Test',
    );
  });

  tearDownAll(() async {
    if (!backendUp) return;
    try {
      await service.logout();
    } catch (_) {
      // Already logged out by the logout test.
    }
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

  group('live auth against the real backend', () {
    test('register created an unverified user with tokens', () {
      if (!requireBackend()) return;
      final session = service.session;
      expect(session, isNotNull);
      expect(session!.user.email, email);
      expect(session.user.emailVerified, isFalse);
      expect(session.tokens.accessToken, isNotEmpty);
      expect(session.tokens.refreshToken, isNotEmpty);
      expect(session.tokens.expiresIn, 900);
    });

    test('wrong password → 401 INVALID_CREDENTIALS', () async {
      if (!requireBackend()) return;
      final probe = liveService(InMemoryTokenStorage());
      await expectLater(
        () => probe.login(identifier: email, password: 'WrongPass!1'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'INVALID_CREDENTIALS',
          ),
        ),
      );
    });

    test('unregistered email → 401 INVALID_CREDENTIALS', () async {
      if (!requireBackend()) return;
      final probe = liveService(InMemoryTokenStorage());
      await expectLater(
        () => probe.login(
          identifier: 'nobody-here-$email',
          password: 'Whatever!1',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'INVALID_CREDENTIALS',
          ),
        ),
      );
    });

    test('login with the right password succeeds', () async {
      if (!requireBackend()) return;
      final probeStorage = InMemoryTokenStorage();
      final probe = liveService(probeStorage);
      final session = await probe.login(identifier: email, password: password);
      expect(session.user.username, username);
      // Login by username also works (email-or-username).
      final byUsername = liveService(InMemoryTokenStorage());
      final session2 = await byUsername.login(
        identifier: username,
        password: password,
      );
      expect(session2.user.id, session.user.id);
    });

    test('unverified user gets 403 EMAIL_NOT_VERIFIED on /users/me', () async {
      if (!requireBackend()) return;
      await expectLater(
        () => service.fetchProfile(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'EMAIL_NOT_VERIFIED',
          ),
        ),
      );
    });

    test('verify with a wrong code → 401', () async {
      if (!requireBackend()) return;
      await expectLater(
        () => service.verifyEmail(token: 'definitely-not-a-real-code'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'UNAUTHORIZED'),
        ),
      );
    });

    test('refresh rotates the token pair', () async {
      if (!requireBackend()) return;
      final before = service.session!;
      final refreshed = await service.refreshSession();
      expect(refreshed, isNotNull);
      expect(refreshed!.tokens.accessToken, isNot(before.tokens.accessToken));
      expect(refreshed.tokens.refreshToken, isNot(before.tokens.refreshToken));
    });

    test('a reused refresh token is rejected (family revoked)', () async {
      if (!requireBackend()) return;
      // A separate user, so the revocation cannot disturb the
      // shared session the other tests use.
      final tag = uniqueTag();
      final probeStorage = InMemoryTokenStorage();
      final probe = liveService(probeStorage);
      final session = await probe.register(
        email: '$tag@example.com',
        username: 'u_$tag',
        password: password,
      );
      final rotated = await probe.refreshSession();
      expect(rotated, isNotNull);
      final stale = AuthApiClient(config: const AuthConfig(baseUrl: baseUrl));
      await expectLater(
        () => stale.refresh(refreshToken: session.tokens.refreshToken),
        throwsA(isA<ApiException>().having((e) => e.httpStatus, 'status', 401)),
      );
      // The reuse revoked the whole family: even the rotated
      // refresh token is now dead.
      await expectLater(
        () => stale.refresh(refreshToken: rotated!.tokens.refreshToken),
        throwsA(isA<ApiException>().having((e) => e.httpStatus, 'status', 401)),
      );
    });

    test('restart restores the session from storage', () async {
      if (!requireBackend()) return;
      // A new service over the SAME storage is an app restart: the
      // in-memory session is gone, the stored one must restore.
      final restarted = liveService(storage);
      expect(restarted.session, isNull);
      final restored = await restarted.restoreSession();
      expect(restored, isNotNull);
      expect(restored!.user.email, email);
    });

    test('expired access token restores via silent refresh', () async {
      if (!requireBackend()) return;
      final current = service.session!;
      final expired = AuthSession(
        user: current.user,
        tokens: current.tokens,
        accessTokenExpiresAt: DateTime.now().subtract(
          const Duration(minutes: 1),
        ),
      );
      final scratchStorage = InMemoryTokenStorage();
      await scratchStorage.saveSession(expired);
      final restarted = liveService(scratchStorage);
      final restored = await restarted.restoreSession();
      expect(restored, isNotNull);
      expect(restored!.tokens.accessToken, isNot(current.tokens.accessToken));
      expect(restored.accessTokenExpired, isFalse);
    });

    test('logout invalidates the session', () async {
      if (!requireBackend()) return;
      final probeStorage = InMemoryTokenStorage();
      final probe = liveService(probeStorage);
      final session = await probe.login(identifier: email, password: password);
      final accessToken = session.tokens.accessToken;
      await probe.logout();
      expect(await probeStorage.readSession(), isNull);
      // The revoked access token now fails: the backend's sid check
      // rejects it immediately, inside the 15-minute window.
      final client = AuthApiClient(config: const AuthConfig(baseUrl: baseUrl));
      await expectLater(
        () => client.getProfile(accessToken: accessToken),
        throwsA(isA<ApiException>().having((e) => e.httpStatus, 'status', 401)),
      );
    });

    test('duplicate registration → 409 EMAIL_TAKEN', () async {
      if (!requireBackend()) return;
      final probe = liveService(InMemoryTokenStorage());
      await expectLater(
        () => probe.register(
          email: email,
          // A valid, unused username: the conflict must be the email.
          username: 'dup${DateTime.now().millisecondsSinceEpoch}',
          password: password,
        ),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'EMAIL_TAKEN'),
        ),
      );
    });
  });
}
