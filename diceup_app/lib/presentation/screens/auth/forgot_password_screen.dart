import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/diceup_components.dart';
import '../../../core/design_system/diceup_spacing.dart';
import '../../../l10n/app_strings.dart';
import '../../navigation/app_routes.dart';
import '../../providers/app_providers.dart';
import 'auth_error_messages.dart';
import 'auth_widgets.dart';

/// Forgot-password screen (Phase 5, Stage 2; FR-06, UI-05).
///
/// Requests a reset code for an email. The response is neutral by
/// design — the screen reports the same outcome whether or not an
/// account exists for the email. On success it moves to the reset
/// screen, which takes the code and the new password.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final ok = await ref
        .read(authStateProvider.notifier)
        .forgotPassword(email: email);
    if (!mounted || !ok) return;
    Navigator.of(context).pushNamed(AppRoutes.resetPassword, arguments: email);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    final auth = ref.watch(authStateProvider);
    return AuthScreenScaffold(
      title: l10n.forgotTitle,
      errorMessage: authErrorMessage(l10n, auth.errorCode),
      infoMessage: authInfoMessage(l10n, auth.infoCode),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.forgotMessage),
            const SizedBox(height: DiceUpSpacing.lg),
            DiceUpTextField(
              label: l10n.authEmailLabel,
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              enabled: !auth.isBusy,
              errorText: auth.fieldErrors['email'],
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return l10n.authErrorRequired;
                if (!_emailPattern.hasMatch(text)) {
                  return l10n.authErrorInvalidEmail;
                }
                return null;
              },
            ),
            const SizedBox(height: DiceUpSpacing.lg),
            PrimaryButton(
              label: l10n.forgotButton,
              isLoading: auth.isBusy,
              onPressed: auth.isBusy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Reset-password screen (Phase 5, Stage 2; FR-06, UI-05).
///
/// The code from the reset email (1 h window) plus the new
/// password. A successful reset revokes all sessions server-side,
/// so the screen leaves for the login screen — the user signs in
/// again with the new password.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.email});

  /// The email the code was sent to (from the forgot screen).
  final String? email;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(authStateProvider.notifier)
        .resetPassword(
          token: _codeController.text.trim(),
          newPassword: _passwordController.text,
        );
    if (!mounted || !ok) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    final auth = ref.watch(authStateProvider);
    return AuthScreenScaffold(
      title: l10n.resetTitle,
      errorMessage: authErrorMessage(l10n, auth.errorCode, tokenContext: true),
      infoMessage: authInfoMessage(l10n, auth.infoCode),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.resetMessage),
            const SizedBox(height: DiceUpSpacing.lg),
            DiceUpTextField(
              label: l10n.authCodeLabel,
              controller: _codeController,
              autofillHints: const [AutofillHints.oneTimeCode],
              textInputAction: TextInputAction.next,
              enabled: !auth.isBusy,
              errorText: auth.fieldErrors['token'],
              validator: (value) => value == null || value.trim().isEmpty
                  ? l10n.authErrorInvalidCode
                  : null,
            ),
            const SizedBox(height: DiceUpSpacing.md),
            DiceUpTextField(
              label: l10n.authNewPasswordLabel,
              controller: _passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              enabled: !auth.isBusy,
              errorText: auth.fieldErrors['newPassword'],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l10n.authErrorRequired;
                }
                if (value.length < 8) return l10n.authErrorPasswordTooShort;
                return null;
              },
            ),
            const SizedBox(height: DiceUpSpacing.md),
            DiceUpTextField(
              label: l10n.authConfirmPasswordLabel,
              controller: _confirmController,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              enabled: !auth.isBusy,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l10n.authErrorRequired;
                }
                if (value != _passwordController.text) {
                  return l10n.authErrorPasswordsDoNotMatch;
                }
                return null;
              },
            ),
            const SizedBox(height: DiceUpSpacing.lg),
            PrimaryButton(
              label: l10n.resetButton,
              isLoading: auth.isBusy,
              onPressed: auth.isBusy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
