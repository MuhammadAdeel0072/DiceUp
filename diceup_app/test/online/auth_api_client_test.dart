import 'dart:convert';
import 'dart:io';

import 'package:diceup/data/online/auth_api_client.dart';
import 'package:diceup/data/online/auth_config.dart';
import 'package:diceup/data/online/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const baseUrl = 'http://127.0.0.1:3000/v1';

  AuthApiClient clientWith(MockClient mock) => AuthApiClient(
    config: const AuthConfig(baseUrl: baseUrl),
    httpClient: mock,
  );

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
      'accessToken': 'access',
      'refreshToken': 'refresh',
      'expiresIn': 900,
      'tokenType': 'Bearer',
    },
  };

  http.Response ok(Object? data, [int status = 200]) => http.Response(
    jsonEncode(<String, Object?>{'success': true, 'data': data}),
    status,
    headers: {'content-type': 'application/json'},
  );

  http.Response err(String code, int status, {Object? details}) {
    final error = <String, Object?>{'code': code, 'message': 'Failed.'};
    if (details != null) error['details'] = details;
    return http.Response(
      jsonEncode(<String, Object?>{'success': false, 'error': error}),
      status,
      headers: {'content-type': 'application/json'},
    );
  }

  group('AuthApiClient', () {
    test('login success parses the user and token pair', () async {
      final client = clientWith(
        MockClient((request) async {
          expect(request.url.toString(), '$baseUrl/auth/login');
          expect(request.method, 'POST');
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body['identifier'], 'ada@example.com');
          return ok(authData());
        }),
      );
      final result = await client.login(
        identifier: 'ada@example.com',
        password: 'CorrectHorse!9',
      );
      expect(result.user.email, 'ada@example.com');
      expect(result.user.emailVerified, isFalse);
      expect(result.tokens.accessToken, 'access');
      expect(result.tokens.expiresIn, 900);
    });

    test('login sends the password in the body, never in the URL', () async {
      var sawPasswordInUrl = false;
      final client = clientWith(
        MockClient((request) async {
          sawPasswordInUrl = request.url.toString().contains('CorrectHorse');
          return ok(authData());
        }),
      );
      await client.login(identifier: 'ada', password: 'CorrectHorse!9');
      expect(sawPasswordInUrl, isFalse);
    });

    test('login failure maps 401 INVALID_CREDENTIALS', () async {
      final client = clientWith(
        MockClient((_) async => err('INVALID_CREDENTIALS', 401)),
      );
      await expectLater(
        () => client.login(identifier: 'ada', password: 'wrong'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'INVALID_CREDENTIALS')
              .having((e) => e.httpStatus, 'httpStatus', 401),
        ),
      );
    });

    test('register conflict maps 409 EMAIL_TAKEN', () async {
      final client = clientWith(
        MockClient((_) async => err('EMAIL_TAKEN', 409)),
      );
      await expectLater(
        () => client.register(
          email: 'ada@example.com',
          username: 'ada2',
          password: 'CorrectHorse!9',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'EMAIL_TAKEN'),
        ),
      );
    });

    test('register conflict maps 409 USERNAME_TAKEN', () async {
      final client = clientWith(
        MockClient((_) async => err('USERNAME_TAKEN', 409)),
      );
      await expectLater(
        () => client.register(
          email: 'other@example.com',
          username: 'ada',
          password: 'CorrectHorse!9',
        ),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'USERNAME_TAKEN'),
        ),
      );
    });

    test('validation failure carries per-field details', () async {
      final client = clientWith(
        MockClient(
          (_) async => err(
            'VALIDATION_FAILED',
            400,
            details: {
              'password': ['Password must be at least 8 characters.'],
              'email': ['email must be an email'],
            },
          ),
        ),
      );
      await expectLater(
        () => client.register(email: 'bad', username: 'ada', password: 'short'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'VALIDATION_FAILED')
              .having(
                (e) => e.fieldErrors['password'],
                'password error',
                'Password must be at least 8 characters.',
              )
              .having(
                (e) => e.fieldErrors['email'],
                'email error',
                'email must be an email',
              ),
        ),
      );
    });

    test('rate limiting carries the Retry-After seconds', () async {
      final client = clientWith(
        MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'success': false,
              'error': <String, Object?>{
                'code': 'RATE_LIMITED',
                'message': 'Too many requests.',
              },
            }),
            429,
            headers: {'retry-after': '120'},
          ),
        ),
      );
      await expectLater(
        () => client.login(identifier: 'ada', password: 'x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'RATE_LIMITED')
              .having((e) => e.retryAfterSeconds, 'retryAfter', 120),
        ),
      );
    });

    test('refresh success parses the rotated pair', () async {
      final client = clientWith(
        MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          expect(body['refreshToken'], 'old-refresh');
          return ok(<String, Object?>{
            'accessToken': 'new-access',
            'refreshToken': 'new-refresh',
            'expiresIn': 900,
            'tokenType': 'Bearer',
          });
        }),
      );
      final pair = await client.refresh(refreshToken: 'old-refresh');
      expect(pair.accessToken, 'new-access');
      expect(pair.refreshToken, 'new-refresh');
    });

    test('logout sends the Bearer token', () async {
      var authorization = '';
      final client = clientWith(
        MockClient((request) async {
          authorization = request.headers['Authorization'] ?? '';
          return ok(<String, Object?>{'loggedOut': true});
        }),
      );
      await client.logout(accessToken: 'access');
      expect(authorization, 'Bearer access');
    });

    test('verify-email maps 410 TOKEN_EXPIRED', () async {
      final client = clientWith(
        MockClient((_) async => err('TOKEN_EXPIRED', 410)),
      );
      await expectLater(
        () => client.verifyEmail(token: 'stale-code'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'TOKEN_EXPIRED'),
        ),
      );
    });

    test('verify-email maps 409 TOKEN_ALREADY_USED', () async {
      final client = clientWith(
        MockClient((_) async => err('TOKEN_ALREADY_USED', 409)),
      );
      await expectLater(
        () => client.verifyEmail(token: 'used-code'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'TOKEN_ALREADY_USED',
          ),
        ),
      );
    });

    test('getProfile maps 403 EMAIL_NOT_VERIFIED', () async {
      final client = clientWith(
        MockClient((request) async {
          expect(request.url.toString(), '$baseUrl/users/me');
          return err('EMAIL_NOT_VERIFIED', 403);
        }),
      );
      await expectLater(
        () => client.getProfile(accessToken: 'access'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'EMAIL_NOT_VERIFIED',
          ),
        ),
      );
    });

    test('socket failure maps to NETWORK_ERROR', () async {
      final client = clientWith(
        MockClient((_) async => throw const SocketException('no route')),
      );
      await expectLater(
        () => client.login(identifier: 'ada', password: 'x'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'NETWORK_ERROR'),
        ),
      );
    });

    test('non-JSON body maps to UNEXPECTED_RESPONSE', () async {
      final client = clientWith(
        MockClient((_) async => http.Response('not json', 200)),
      );
      await expectLater(
        () => client.login(identifier: 'ada', password: 'x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'UNEXPECTED_RESPONSE',
          ),
        ),
      );
    });

    test('GET retries once on a transient failure, then succeeds', () async {
      var attempts = 0;
      final client = clientWith(
        MockClient((_) async {
          attempts++;
          if (attempts == 1) throw const SocketException('reset');
          return ok(<String, Object?>{
            'id': '00000000-0000-0000-0000-000000000001',
            'email': 'ada@example.com',
            'username': 'ada',
            'displayName': 'Ada',
            'avatarKey': 'default',
            'emailVerified': true,
            'status': 'active',
            'matchesPlayed': 0,
            'matchesWon': 0,
            'notificationPreferences': <String, Object?>{},
            'createdAt': '2026-01-01T00:00:00.000Z',
          });
        }),
      );
      final profile = await client.getProfile(accessToken: 'access');
      expect(attempts, 2);
      expect(profile.user.username, 'ada');
    });

    test('POST is never retried on a transient failure', () async {
      var attempts = 0;
      final client = clientWith(
        MockClient((_) async {
          attempts++;
          throw const SocketException('reset');
        }),
      );
      await expectLater(
        () => client.login(identifier: 'ada', password: 'x'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'NETWORK_ERROR'),
        ),
      );
      expect(attempts, 1);
    });
  });
}
