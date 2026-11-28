import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/diceup_components.dart';
import '../../../core/design_system/diceup_spacing.dart';
import '../../../l10n/app_strings.dart';
import '../../navigation/app_routes.dart';
import '../../providers/app_providers.dart';
import 'auth_error_messages.dart';
import 'auth_widgets.dart';

/// Log-in screen (Phase 5, Stage 2; FR-04, UI-05).
///
/// Email-or-username + password against the real backend. Wrong
/// credentials surface the generic `INVALID_CREDENTIALS` message —
/// the screen never says whether the account exists. On success it
/// pops back to where the user came from (Home, or the screen that
/// required login).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(authStateProvider.notifier)
        .login(
          identifier: _identifierController.text.trim(),
          password: _passwordController.text,
        );
    if (!mounted || !ok) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    final auth = ref.watch(authStateProvider);
    return AuthScreenScaffold(
      title: l10n.loginTitle,
      errorMessage: authErrorMessage(l10n, auth.errorCode),
      infoMessage: authInfoMessage(l10n, auth.infoCode),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DiceUpTextField(
              label: l10n.authEmailOrUsernameLabel,
              controller: _identifierController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              enabled: !auth.isBusy,
              errorText: auth.fieldErrors['identifier'],
              validator: (value) => value == null || value.trim().isEmpty
                  ? l10n.authErrorRequired
                  : null,
            ),
            const SizedBox(height: DiceUpSpacing.md),
            DiceUpTextField(
              label: l10n.authPasswordLabel,
              controller: _passwordController,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              enabled: !auth.isBusy,
              errorText: auth.fieldErrors['password'],
              validator: (value) => value == null || value.isEmpty
                  ? l10n.authErrorRequired
                  : null,
            ),
            const SizedBox(height: DiceUpSpacing.lg),
            PrimaryButton(
              label: l10n.loginButton,
              isLoading: auth.isBusy,
              onPressed: auth.isBusy ? null : _submit,
            ),
            const SizedBox(height: DiceUpSpacing.md),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.forgotPassword),
              child: Text(l10n.loginForgotPassword),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.register),
              child: Text(l10n.loginNoAccount),
            ),
          ],
        ),
      ),
    );
  }
}
