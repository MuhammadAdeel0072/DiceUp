import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/diceup_components.dart';
import '../../../core/design_system/diceup_spacing.dart';
import '../../../l10n/app_strings.dart';
import '../../navigation/app_routes.dart';
import '../../providers/app_providers.dart';
import 'auth_error_messages.dart';
import 'auth_widgets.dart';

/// Registration screen (Phase 5, Stage 2; FR-02, UI-05).
///
/// Client validation mirrors the backend DTO (email, username
/// 3–30 chars, password ≥ 8) so obvious mistakes never hit the
/// network; the backend remains the authority (its
/// `VALIDATION_FAILED` details surface under the field). On success
/// the account exists but is unverified, so the screen replaces
/// itself with the verification screen for the new email.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _usernamePattern = RegExp(r'^[a-zA-Z0-9_.-]{3,30}$');

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final ok = await ref
        .read(authStateProvider.notifier)
        .register(
          email: email,
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          displayName: _displayNameController.text.trim(),
        );
    if (!mounted || !ok) return;
    Navigator.of(context)
        .pushReplacementNamed(AppRoutes.verifyEmail, arguments: email);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    final auth = ref.watch(authStateProvider);
    return AuthScreenScaffold(
      title: l10n.registerTitle,
      errorMessage: authErrorMessage(l10n, auth.errorCode),
      infoMessage: authInfoMessage(l10n, auth.infoCode),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DiceUpTextField(
              label: l10n.authEmailLabel,
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
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
            const SizedBox(height: DiceUpSpacing.md),
            DiceUpTextField(
              label: l10n.authUsernameLabel,
              controller: _usernameController,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              enabled: !auth.isBusy,
              errorText: auth.fieldErrors['username'],
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return l10n.authErrorRequired;
                if (!_usernamePattern.hasMatch(text)) {
                  return l10n.authErrorInvalidUsername;
                }
                return null;
              },
            ),
            const SizedBox(height: DiceUpSpacing.md),
            DiceUpTextField(
              label: l10n.authDisplayNameLabel,
              controller: _displayNameController,
              textInputAction: TextInputAction.next,
              enabled: !auth.isBusy,
              errorText: auth.fieldErrors['displayName'],
            ),
            const SizedBox(height: DiceUpSpacing.md),
            DiceUpTextField(
              label: l10n.authPasswordLabel,
              controller: _passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              enabled: !auth.isBusy,
              errorText: auth.fieldErrors['password'],
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
              label: l10n.registerButton,
              isLoading: auth.isBusy,
              onPressed: auth.isBusy ? null : _submit,
            ),
            const SizedBox(height: DiceUpSpacing.md),
            TextButton(
              onPressed: () => Navigator.of(context).pushNamed(AppRoutes.login),
              child: Text(l10n.registerHaveAccount),
            ),
          ],
        ),
      ),
    );
  }
}
