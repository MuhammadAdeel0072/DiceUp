import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/diceup_components.dart';
import '../../../core/design_system/diceup_spacing.dart';
import '../../../l10n/app_strings.dart';
import '../../navigation/app_routes.dart';
import '../../providers/app_providers.dart';
import 'auth_error_messages.dart';
import 'auth_widgets.dart';

/// Email-verification screen (Phase 5, Stage 2; FR-03, UI-05).
///
/// The code comes from the verification email (24 h window). A
/// wrong code is a generic 401 — the screen says only that the code
/// isn't right. On success the account is verified and the screen
/// leaves for Home. The resend button asks for a fresh code without
/// leaking whether the account exists.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.email});

  /// The email the code was sent to (from registration, the
  /// account screen, or the signed-in user). Null only when the
  /// screen was opened without one — the message then omits it.
  final String? email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String get _email =>
      widget.email ?? ref.read(authStateProvider).user?.email ?? '';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(authStateProvider.notifier)
        .verifyEmail(token: _codeController.text.trim());
    if (!mounted || !ok) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  Future<void> _resend() async {
    final email = _email;
    if (email.isEmpty) return;
    await ref.read(authStateProvider.notifier).resendVerification(email: email);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    final auth = ref.watch(authStateProvider);
    return AuthScreenScaffold(
      title: l10n.verifyTitle,
      errorMessage: authErrorMessage(l10n, auth.errorCode, tokenContext: true),
      infoMessage: authInfoMessage(l10n, auth.infoCode),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.verifyMessage(_email)),
            const SizedBox(height: DiceUpSpacing.lg),
            DiceUpTextField(
              label: l10n.authCodeLabel,
              controller: _codeController,
              autofillHints: const [AutofillHints.oneTimeCode],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              enabled: !auth.isBusy,
              errorText: auth.fieldErrors['token'],
              validator: (value) => value == null || value.trim().isEmpty
                  ? l10n.authErrorInvalidCode
                  : null,
            ),
            const SizedBox(height: DiceUpSpacing.lg),
            PrimaryButton(
              label: l10n.verifyButton,
              isLoading: auth.isBusy,
              onPressed: auth.isBusy ? null : _submit,
            ),
            const SizedBox(height: DiceUpSpacing.md),
            TextButton(
              onPressed: auth.isBusy || _email.isEmpty ? null : _resend,
              child: Text(l10n.verifyResend),
            ),
          ],
        ),
      ),
    );
  }
}
