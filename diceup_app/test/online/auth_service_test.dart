import 'dart:convert';

import 'package:diceup/data/online/auth_api_client.dart';
import 'package:diceup/data/online/auth_config.dart';
import 'package:diceup/data/online/auth_models.dart';
import 'package:diceup/data/online/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

void main() {
  const baseUrl = 'http://127.0.0.1:3000/v1';

  Map<String, Object?> authData({bool verified = false}) => <String, Object?>{
    'user': <String, Object?>{
      'id': '00000000-0000-0000-0000-000000000001',
      'email': 'ada@example.com',
      'username': 'ada',
      'displayName': 'Ada',
      'avatarKey': 'default',
      'emailVerified': verified,
    },
    'tokens': <String, Object?>{
      'accessToken': 'access-1',
      'refreshToken': 'refresh-1',
      'expiresIn': 900,
      'tokenType': 'Bearer',
    },
  };

  http.Response ok(Object? data, [int status = 200]) => http.Response(
    jsonEncode(<String, Object?>{'success': true, 'data': data}),
    status,
    headers: {'content-type': 'application/json'},
  );

  http.Response err(String code, int status) => http.Response(
    jsonEncode(<String, Object?>{
      'success': false,
      'error': <String, Object?>{'code': code, 'message': 'Failed.'},
    }),
    status,
    headers: {'content-type': 'application/json'},
  );

  /// A service whose HTTP layer is scripted per path.
  ({AuthService service, InMemoryTokenStorage storage, List<String> calls})
  scripted(Map<String, http.Response Function(http.Request)> handlers) {
    final calls = <String>[];
    final storage = InMemoryTokenStorage();
    final client = AuthApiClient(
      config: const AuthConfig(baseUrl: baseUrl),
      httpClient: MockClient((request) async {
        final path = request.url.path.replaceFirst('/v1', '');
        calls.add('${request.method} $path');
        final handler = handlers[path];
        if (handler == null) return err('NOT_FOUND', 404);
        return handler(request);
      }),
    );
    return (
      service: AuthService(client: client, storage: storage),
      storage: storage,
      calls: calls,
    );
  }

  group('AuthService', () {
    test('login persists the session to storage', () async {
      final s = scripted({'/auth/login': (_) => ok(authData(), 200)});
      final session = await s.service.login(
        identifier: 'ada@example.com',
        password: 'CorrectHorse!9',
      );
      expect(session.user.username, 'ada');
      expect(s.service.isAuthenticated, isTrue);
      final stored = await s.storage.readSession();
      expect(stored?.tokens.refreshToken, 'refresh-1');
      expect(stored?.user.email, 'ada@example.com');
    });

    test('restore returns a stored session with a live access token', () async {
      final s = scripted({});
      final stored = AuthSession(
        user: AuthUser(
          id: '00000000-0000-0000-0000-000000000001',
          email: 'ada@example.com',
          username: 'ada',
          displayName: 'Ada',
          avatarKey: 'default',
          emailVerified: true,
        ),
        tokens: const TokenPair(
          accessToken: 'live-access',
          refreshToken: 'live-refresh',
          expiresIn: 900,
        ),
        accessTokenExpiresAt: DateTime.now().add(const Duration(minutes: 10)),
      );
      await s.storage.saveSession(stored);
      final restored = await s.service.restoreSession();
      expect(restored?.tokens.accessToken, 'live-access');
      expect(s.calls, isEmpty, reason: 'no refresh for a live token');
    });

    test('restore silently refreshes an expired access token', () async {
      final s = scripted({
        '/auth/refresh': (request) {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body['refreshToken'], 'old-refresh');
          return ok(<String, Object?>{
            'accessToken': 'fresh-access',
            'refreshToken': 'fresh-refresh',
            'expiresIn': 900,
            'tokenType': 'Bearer',
          });
        },
      });
      final expired = AuthSession(
        user: AuthUser(
          id: '00000000-0000-0000-0000-000000000001',
          email: 'ada@example.com',
          username: 'ada',
          displayName: 'Ada',
          avatarKey: 'default',
          emailVerified: true,
        ),
        tokens: const TokenPair(
          accessToken: 'stale-access',
          refreshToken: 'old-refresh',
          expiresIn: 900,
        ),
        accessTokenExpiresAt: DateTime.now().subtract(
          const Duration(minutes: 1),
        ),
      );
      await s.storage.saveSession(expired);
      final restored = await s.service.restoreSession();
      expect(restored?.tokens.accessToken, 'fresh-access');
      final stored = await s.storage.readSession();
      expect(stored?.tokens.refreshToken, 'fresh-refresh');
    });

    test('restore clears the session when refresh fails', () async {
      final s = scripted({'/auth/refresh': (_) => err('UNAUTHORIZED', 401)});
      final expired = AuthSession(
        user: AuthUser(
          id: '00000000-0000-0000-0000-000000000001',
          email: 'ada@example.com',
          username: 'ada',
          displayName: 'Ada',
          avatarKey: 'default',
          emailVerified: true,
        ),
        tokens: const TokenPair(
          accessToken: 'stale-access',
          refreshToken: 'dead-refresh',
          expiresIn: 900,
        ),
        accessTokenExpiresAt: DateTime.now().subtract(
          const Duration(minutes: 1),
        ),
      );
      await s.storage.saveSession(expired);
      final restored = await s.service.restoreSession();
      expect(restored, isNull);
      expect(await s.storage.readSession(), isNull);
      expect(s.service.isAuthenticated, isFalse);
    });

    test('restore returns null when nothing is stored', () async {
      final s = scripted({});
      expect(await s.service.restoreSession(), isNull);
    });

    test('logout revokes on the backend and clears local tokens', () async {
      final s = scripted({
        '/auth/login': (_) => ok(authData(), 200),
        '/auth/logout': (request) {
          expect(request.headers['Authorization'], 'Bearer access-1');
          return ok(<String, Object?>{'loggedOut': true});
        },
      });
      await s.service.login(identifier: 'ada', password: 'CorrectHorse!9');
      await s.service.logout();
      expect(s.calls, contains('POST /auth/logout'));
      expect(await s.storage.readSession(), isNull);
      expect(s.service.isAuthenticated, isFalse);
    });

    test(
      'logout clears local tokens even when the backend call fails',
      () async {
        final s = scripted({
          '/auth/login': (_) => ok(authData(), 200),
          '/auth/logout': (_) => err('UNAUTHORIZED', 401),
        });
        await s.service.login(identifier: 'ada', password: 'CorrectHorse!9');
        await s.service.logout();
        expect(await s.storage.readSession(), isNull);
        expect(s.service.isAuthenticated, isFalse);
      },
    );

    test('fetchProfile retries once after a 401, via refresh', () async {
      var profileCalls = 0;
      final s = scripted({
        '/auth/login': (_) => ok(authData(), 200),
        '/auth/refresh': (_) => ok(<String, Object?>{
          'accessToken': 'access-2',
          'refreshToken': 'refresh-2',
          'expiresIn': 900,
          'tokenType': 'Bearer',
        }),
        '/users/me': (request) {
          profileCalls++;
          if (profileCalls == 1) return err('UNAUTHORIZED', 401);
          return ok(<String, Object?>{
            'id': '00000000-0000-0000-0000-000000000001',
            'email': 'ada@example.com',
            'username': 'ada',
            'displayName': 'Ada',
            'avatarKey': 'default',
            'emailVerified': true,
            'status': 'active',
            'matchesPlayed': 5,
            'matchesWon': 2,
            'notificationPreferences': <String, Object?>{},
            'createdAt': '2026-01-01T00:00:00.000Z',
          });
        },
      });
      await s.service.login(identifier: 'ada', password: 'CorrectHorse!9');
      final profile = await s.service.fetchProfile();
      expect(profileCalls, 2);
      expect(profile.matchesPlayed, 5);
      expect(profile.matchesWon, 2);
      expect(s.calls, contains('POST /auth/refresh'));
    });

    test('verifyEmail marks the stored user verified', () async {
      final s = scripted({
        '/auth/login': (_) => ok(authData(), 200),
        '/auth/verify-email': (_) => ok(<String, Object?>{}),
      });
      await s.service.login(identifier: 'ada', password: 'CorrectHorse!9');
      await s.service.verifyEmail(token: 'some-code');
      expect(s.service.session?.user.emailVerified, isTrue);
      final stored = await s.storage.readSession();
      expect(stored?.user.emailVerified, isTrue);
    });

    test('resetPassword clears the local session', () async {
      final s = scripted({
        '/auth/login': (_) => ok(authData(), 200),
        '/auth/reset-password': (_) => ok(<String, Object?>{}),
      });
      await s.service.login(identifier: 'ada', password: 'CorrectHorse!9');
      await s.service.resetPassword(
        token: 'reset-code',
        newPassword: 'NewHorse!9',
      );
      expect(await s.storage.readSession(), isNull);
      expect(s.service.isAuthenticated, isFalse);
    });
  });
}
