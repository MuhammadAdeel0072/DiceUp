import 'package:diceup/data/online/auth_models.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  ProviderContainer containerWith(FakeAuthService service) {
    final container = ProviderContainer(
      overrides: [authServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('AuthNotifier', () {
    test('restore with no stored session ends signed out', () async {
      final service = FakeAuthService()..restoreResult = null;
      final container = containerWith(service);
      // The notifier restores asynchronously on first read.
      container.read(authStateProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(authStateProvider).status, AuthStatus.signedOut);
      expect(service.restoreCalls, 1);
    });

    test('restore with a stored session ends signed in', () async {
      final service = FakeAuthService()
        ..restoreResult = FakeAuthService.cannedSession(verified: true);
      final container = containerWith(service);
      container.read(authStateProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final state = container.read(authStateProvider);
      expect(state.status, AuthStatus.signedIn);
      expect(state.user?.username, 'ada');
      expect(state.user?.emailVerified, isTrue);
    });

    test('login success signs in and clears errors', () async {
      final service = FakeAuthService();
      final container = containerWith(service);
      final ok = await container
          .read(authStateProvider.notifier)
          .login(identifier: 'ada@example.com', password: 'CorrectHorse!9');
      expect(ok, isTrue);
      final state = container.read(authStateProvider);
      expect(state.status, AuthStatus.signedIn);
      expect(state.user?.email, 'ada@example.com');
      expect(state.errorCode, isNull);
      expect(service.loginCalls, 1);
      expect(service.lastIdentifier, 'ada@example.com');
    });

    test(
      'login failure reports INVALID_CREDENTIALS without signing in',
      () async {
        final service = FakeAuthService()
          ..loginError = const ApiException(
            code: 'INVALID_CREDENTIALS',
            message: 'Email or password is incorrect.',
            httpStatus: 401,
          );
        final container = containerWith(service);
        final ok = await container
            .read(authStateProvider.notifier)
            .login(identifier: 'ada@example.com', password: 'wrong');
        expect(ok, isFalse);
        final state = container.read(authStateProvider);
        expect(state.status, isNot(AuthStatus.signedIn));
        expect(state.errorCode, 'INVALID_CREDENTIALS');
        expect(state.user, isNull);
      },
    );

    test(
      'register failure reports EMAIL_TAKEN with no field data lost',
      () async {
        final service = FakeAuthService()
          ..registerError = const ApiException(
            code: 'EMAIL_TAKEN',
            message: 'Email taken.',
            httpStatus: 409,
          );
        final container = containerWith(service);
        final ok = await container
            .read(authStateProvider.notifier)
            .register(
              email: 'ada@example.com',
              username: 'ada2',
              password: 'CorrectHorse!9',
            );
        expect(ok, isFalse);
        expect(container.read(authStateProvider).errorCode, 'EMAIL_TAKEN');
      },
    );

    test('register success signs in and reports registerDone', () async {
      final service = FakeAuthService();
      final container = containerWith(service);
      final ok = await container
          .read(authStateProvider.notifier)
          .register(
            email: 'ada@example.com',
            username: 'ada',
            password: 'CorrectHorse!9',
          );
      expect(ok, isTrue);
      final state = container.read(authStateProvider);
      expect(state.status, AuthStatus.signedIn);
      expect(state.user?.emailVerified, isFalse);
      expect(state.infoCode, 'registerDone');
    });

    test('verify failure reports TOKEN_EXPIRED', () async {
      final service = FakeAuthService()
        ..verifyError = const ApiException(
          code: 'TOKEN_EXPIRED',
          message: 'Expired.',
          httpStatus: 410,
        );
      final container = containerWith(service);
      final ok = await container
          .read(authStateProvider.notifier)
          .verifyEmail(token: 'stale');
      expect(ok, isFalse);
      expect(container.read(authStateProvider).errorCode, 'TOKEN_EXPIRED');
    });

    test('forgot-password success reports forgotSent', () async {
      final service = FakeAuthService();
      final container = containerWith(service);
      final ok = await container
          .read(authStateProvider.notifier)
          .forgotPassword(email: 'ada@example.com');
      expect(ok, isTrue);
      expect(container.read(authStateProvider).infoCode, 'forgotSent');
    });

    test('reset-password success signs out and reports resetDone', () async {
      final service = FakeAuthService();
      final container = containerWith(service);
      final ok = await container
          .read(authStateProvider.notifier)
          .resetPassword(token: 'code', newPassword: 'NewHorse!9');
      expect(ok, isTrue);
      final state = container.read(authStateProvider);
      expect(state.status, AuthStatus.signedOut);
      expect(state.infoCode, 'resetDone');
    });

    test('logout signs out', () async {
      final service = FakeAuthService()
        ..restoreResult = FakeAuthService.cannedSession(verified: true);
      final container = containerWith(service);
      container.read(authStateProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(authStateProvider).status, AuthStatus.signedIn);
      await container.read(authStateProvider.notifier).logout();
      expect(container.read(authStateProvider).status, AuthStatus.signedOut);
      expect(container.read(authStateProvider).user, isNull);
      expect(service.logoutCalls, 1);
    });
  });
}
