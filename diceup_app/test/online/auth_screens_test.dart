import 'package:diceup/data/local/app_dependencies.dart';
import 'package:diceup/data/online/auth_models.dart';
import 'package:diceup/l10n/app_localizations.dart';
import 'package:diceup/presentation/app_dependencies_scope.dart';
import 'package:diceup/presentation/navigation/app_routes.dart';
import 'package:diceup/presentation/providers/app_providers.dart';
import 'package:diceup/presentation/screens/auth/account_screen.dart';
import 'package:diceup/presentation/screens/auth/forgot_password_screen.dart';
import 'package:diceup/presentation/screens/auth/login_screen.dart';
import 'package:diceup/presentation/screens/auth/register_screen.dart';
import 'package:diceup/presentation/screens/auth/verify_email_screen.dart';
import 'package:diceup/presentation/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repositories/fakes/fakes.dart';
import '../test_providers.dart';
import 'fakes.dart';

void main() {
  AppDependencies fakeDepsForHome() {
    final store = InMemoryStore();
    return AppDependencies(
      matches: InMemoryLocalMatchRepository(store),
      statistics: InMemoryLocalStatisticsRepository(store),
      settings: InMemorySettingsRepository(store),
      players: InMemoryLocalPlayerRepository(store),
      snapshots: InMemorySnapshotRepository(store),
    );
  }

  /// A minimal app hosting one auth screen under test, with the
  /// fake auth service injected. Localisations come from the real
  /// generated delegates.
  Widget testApp({
    required FakeAuthService service,
    required Widget home,
    Map<String, WidgetBuilder>? routes,
  }) {
    return ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
        routes: routes ?? const {},
      ),
    );
  }

  Future<void> enterText(WidgetTester tester, String label, String text) async {
    final field = find.widgetWithText(TextFormField, label);
    expect(field, findsOneWidget, reason: 'field "$label"');
    await tester.enterText(field, text);
  }

  group('LoginScreen', () {
    testWidgets('renders the login form', (tester) async {
      await tester.pumpWidget(
        testApp(service: FakeAuthService(), home: const LoginScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Log in'), findsWidgets);
      expect(
        find.widgetWithText(TextFormField, 'Email or username'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text("Don't have an account? Create one"), findsOneWidget);
    });

    testWidgets('empty submit shows required-field errors', (tester) async {
      await tester.pumpWidget(
        testApp(service: FakeAuthService(), home: const LoginScreen()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
      await tester.pumpAndSettle();
      expect(find.text('This field is required.'), findsNWidgets(2));
    });

    testWidgets('wrong password shows the generic error, no navigation', (
      tester,
    ) async {
      final service = FakeAuthService()
        ..loginError = const ApiException(
          code: 'INVALID_CREDENTIALS',
          message: 'Email or password is incorrect.',
          httpStatus: 401,
        );
      await tester.pumpWidget(
        testApp(service: service, home: const LoginScreen()),
      );
      await tester.pumpAndSettle();
      await enterText(tester, 'Email or username', 'ada@example.com');
      await enterText(tester, 'Password', 'wrong');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
      await tester.pumpAndSettle();
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(service.loginCalls, 1);
    });

    testWidgets('successful login pops the screen', (tester) async {
      final service = FakeAuthService();
      await tester.pumpWidget(
        testApp(
          service: service,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                  ),
                  child: const Text('Open login'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open login'));
      await tester.pumpAndSettle();
      await enterText(tester, 'Email or username', 'ada@example.com');
      await enterText(tester, 'Password', 'CorrectHorse!9');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Log in'));
      await tester.pumpAndSettle();
      expect(find.text('Open login'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('forgot-password link opens the forgot screen', (tester) async {
      await tester.pumpWidget(
        testApp(
          service: FakeAuthService(),
          home: const LoginScreen(),
          routes: {
            AppRoutes.forgotPassword: (_) => const ForgotPasswordScreen(),
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(find.text('Reset password'), findsOneWidget);
    });
  });

  group('RegisterScreen', () {
    testWidgets('invalid email shows the localised error', (tester) async {
      await tester.pumpWidget(
        testApp(service: FakeAuthService(), home: const RegisterScreen()),
      );
      await tester.pumpAndSettle();
      await enterText(tester, 'Email', 'not-an-email');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
    });

    testWidgets('mismatched passwords show the localised error', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(service: FakeAuthService(), home: const RegisterScreen()),
      );
      await tester.pumpAndSettle();
      await enterText(tester, 'Email', 'ada@example.com');
      await enterText(tester, 'Username', 'ada');
      await enterText(tester, 'Password', 'CorrectHorse!9');
      await enterText(tester, 'Confirm password', 'Different!9');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text("Passwords don't match."), findsOneWidget);
    });

    testWidgets('taken email shows the server error', (tester) async {
      final service = FakeAuthService()
        ..registerError = const ApiException(
          code: 'EMAIL_TAKEN',
          message: 'Email taken.',
          httpStatus: 409,
        );
      await tester.pumpWidget(
        testApp(service: service, home: const RegisterScreen()),
      );
      await tester.pumpAndSettle();
      await enterText(tester, 'Email', 'ada@example.com');
      await enterText(tester, 'Username', 'ada2');
      await enterText(tester, 'Password', 'CorrectHorse!9');
      await enterText(tester, 'Confirm password', 'CorrectHorse!9');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(
        find.text('An account with this email already exists.'),
        findsOneWidget,
      );
    });

    testWidgets('successful registration opens the verify screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          service: FakeAuthService(),
          home: const RegisterScreen(),
          routes: {
            AppRoutes.verifyEmail: (context) =>
                VerifyEmailScreen(email: AppRoutes.emailArgOf(context)),
          },
        ),
      );
      await tester.pumpAndSettle();
      await enterText(tester, 'Email', 'ada@example.com');
      await enterText(tester, 'Username', 'ada');
      await enterText(tester, 'Password', 'CorrectHorse!9');
      await enterText(tester, 'Confirm password', 'CorrectHorse!9');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Verify your email'), findsOneWidget);
      expect(
        find.text(
          'We sent a verification code to ada@example.com. Enter it below.',
        ),
        findsOneWidget,
      );
    });
  });

  group('VerifyEmailScreen', () {
    testWidgets('wrong code shows the token error', (tester) async {
      final service = FakeAuthService()
        ..verifyError = const ApiException(
          code: 'UNAUTHORIZED',
          message: 'Unknown token.',
          httpStatus: 401,
        );
      await tester.pumpWidget(
        testApp(
          service: service,
          home: const VerifyEmailScreen(email: 'ada@example.com'),
        ),
      );
      await tester.pumpAndSettle();
      await enterText(tester, 'Verification code', 'bogus-code');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(
        find.text("That code isn't right. Check it and try again."),
        findsOneWidget,
      );
      expect(service.verifyCalls, 1);
      expect(service.lastToken, 'bogus-code');
    });

    testWidgets('expired code shows the expired message', (tester) async {
      final service = FakeAuthService()
        ..verifyError = const ApiException(
          code: 'TOKEN_EXPIRED',
          message: 'Expired.',
          httpStatus: 410,
        );
      await tester.pumpWidget(
        testApp(
          service: service,
          home: const VerifyEmailScreen(email: 'ada@example.com'),
        ),
      );
      await tester.pumpAndSettle();
      await enterText(tester, 'Verification code', 'stale-code');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(
        find.text('That code has expired. Request a new one.'),
        findsOneWidget,
      );
    });

    testWidgets('resend asks for a new code', (tester) async {
      final service = FakeAuthService();
      await tester.pumpWidget(
        testApp(
          service: service,
          home: const VerifyEmailScreen(email: 'ada@example.com'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();
      expect(service.resendCalls, 1);
      expect(service.lastEmail, 'ada@example.com');
      expect(find.text('A new code has been sent.'), findsOneWidget);
    });
  });

  group('ForgotPasswordScreen + ResetPasswordScreen', () {
    testWidgets('forgot success opens the reset screen', (tester) async {
      await tester.pumpWidget(
        testApp(
          service: FakeAuthService(),
          home: const ForgotPasswordScreen(),
          routes: {
            AppRoutes.resetPassword: (context) =>
                ResetPasswordScreen(email: AppRoutes.emailArgOf(context)),
          },
        ),
      );
      await tester.pumpAndSettle();
      await enterText(tester, 'Email', 'ada@example.com');
      await tester.tap(find.text('Send reset code'));
      await tester.pumpAndSettle();
      expect(find.text('Enter reset code'), findsOneWidget);
    });

    testWidgets('reset with mismatched passwords stays on the screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(
          service: FakeAuthService(),
          home: const ResetPasswordScreen(email: 'ada@example.com'),
        ),
      );
      await tester.pumpAndSettle();
      await enterText(tester, 'Verification code', 'reset-code');
      await enterText(tester, 'New password', 'NewHorse!9');
      await enterText(tester, 'Confirm password', 'OtherHorse!9');
      await tester.tap(find.text('Reset password'));
      await tester.pumpAndSettle();
      expect(find.text("Passwords don't match."), findsOneWidget);
      expect(find.text('Enter reset code'), findsOneWidget);
    });
  });

  group('AccountScreen', () {
    testWidgets('shows the profile and the verify action when unverified', (
      tester,
    ) async {
      final service = FakeAuthService()
        ..restoreResult = FakeAuthService.cannedSession(verified: false)
        ..profileResult = null
        ..fetchProfileError = const ApiException(
          code: 'EMAIL_NOT_VERIFIED',
          message: 'Unverified.',
          httpStatus: 403,
        );
      await tester.pumpWidget(
        testApp(service: service, home: const AccountScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Signed in as Ada'), findsOneWidget);
      expect(find.text('Email not verified'), findsOneWidget);
      expect(find.text('Verify email'), findsOneWidget);
      expect(find.text('Change password'), findsWidgets);
      expect(find.text('Log out'), findsOneWidget);
    });

    testWidgets('log out returns home', (tester) async {
      final service = FakeAuthService()
        ..restoreResult = FakeAuthService.cannedSession(verified: true);
      await tester.pumpWidget(
        testApp(
          service: service,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountScreen(),
                    ),
                  ),
                  child: const Text('Open account'),
                ),
              ),
            ),
          ),
          routes: {
            AppRoutes.home: (_) =>
                const Scaffold(body: Center(child: Text('Home stub'))),
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open account'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(service.logoutCalls, 1);
      expect(find.text('Home stub'), findsOneWidget);
      expect(find.byType(AccountScreen), findsNothing);
    });
  });

  group('HomeScreen Play Online entry (FR-42)', () {
    /// Home under test with the fake auth service: the screen reads
    /// repositories through [AppDependenciesScope] (not yet migrated
    /// to providers) and auth state through the provider graph.
    Widget homeApp(FakeAuthService service, {Widget? loginTarget}) {
      final deps = fakeDepsForHome();
      final startup = testStartup(deps);
      return ProviderScope(
        overrides: [
          startupResultProvider.overrideWithValue(startup),
          authServiceProvider.overrideWithValue(service),
        ],
        child: AppDependenciesScope(
          startup: startup,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
            routes: {
              AppRoutes.login: (_) => loginTarget ?? const LoginScreen(),
              AppRoutes.account: (_) => const AccountScreen(),
            },
          ),
        ),
      );
    }

    testWidgets('guest prompt offers Log in, which opens the login screen', (
      tester,
    ) async {
      await tester.pumpWidget(homeApp(FakeAuthService()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play Online'));
      await tester.pumpAndSettle();
      expect(find.text('Log in to play online with friends.'), findsOneWidget);
      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('signed-in prompt shows the account and log-out actions', (
      tester,
    ) async {
      final service = FakeAuthService()
        ..restoreResult = FakeAuthService.cannedSession(verified: true);
      await tester.pumpWidget(homeApp(service));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play Online'));
      await tester.pumpAndSettle();
      expect(find.text("You're signed in as Ada."), findsOneWidget);
      expect(find.text('View account'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
      await tester.tap(find.text('View account'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
    });
  });
}
