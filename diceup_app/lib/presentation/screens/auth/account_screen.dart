import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/diceup_components.dart';
import '../../../core/design_system/diceup_spacing.dart';
import '../../../core/design_system/diceup_typography.dart';
import '../../../l10n/app_strings.dart';
import '../../navigation/app_routes.dart';
import '../../providers/app_providers.dart';
import 'auth_error_messages.dart';
import 'auth_widgets.dart';

/// Account screen (Phase 5, Stage 2; FR-07/08, UI-05).
///
/// Own profile from `GET /users/me` (unverified users cannot load
/// it — the `EmailVerifiedGuard` answers 403 — so the screen falls
/// back to the session's stored user and offers verification).
/// Change password revokes all sessions server-side, so success
/// signs the user out locally and leaves for the login screen.
/// Log out revokes the current session and returns Home.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _profileLoaded = false;
  bool _loadingProfile = true;
  bool _changingPassword = false;

  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await ref.read(authStateProvider.notifier).fetchProfile();
    if (!mounted) return;
    setState(() {
      _profileLoaded = profile != null;
      _loadingProfile = false;
    });
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _changingPassword = true);
    final ok = await ref
        .read(authStateProvider.notifier)
        .changePassword(
          currentPassword: _currentController.text,
          newPassword: _newController.text,
        );
    if (!mounted) return;
    setState(() => _changingPassword = false);
    if (!ok) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  Future<void> _logout() async {
    await ref.read(authStateProvider.notifier).logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.home, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    final busy = auth.isBusy || _changingPassword;
    return AuthScreenScaffold(
      title: l10n.accountTitle,
      errorMessage: authErrorMessage(l10n, auth.errorCode),
      infoMessage: authInfoMessage(l10n, auth.infoCode),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loadingProfile)
            const Center(child: CircularProgressIndicator())
          else if (user == null)
            Text(l10n.authErrorUnexpected)
          else ...[
            Text(
              l10n.accountSignedInAs(user.displayName),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: DiceUpSpacing.md),
            _ProfileRow(label: l10n.accountUsername, value: user.username),
            _ProfileRow(label: l10n.accountEmail, value: user.email),
            _ProfileRow(
              label: l10n.accountDisplayName,
              value: user.displayName,
            ),
            _ProfileRow(
              label: l10n.accountEmailStatus,
              value: user.emailVerified
                  ? l10n.accountEmailVerified
                  : l10n.accountEmailNotVerified,
            ),
            if (_profileLoaded) ...[
              _ProfileRow(
                label: l10n.accountMatchesPlayed,
                value: (auth.matchesPlayed ?? 0).toString(),
              ),
              _ProfileRow(
                label: l10n.accountMatchesWon,
                value: (auth.matchesWon ?? 0).toString(),
              ),
            ],
            if (!user.emailVerified) ...[
              const SizedBox(height: DiceUpSpacing.md),
              SecondaryButton(
                label: l10n.accountVerifyEmail,
                onPressed: busy
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.verifyEmail, arguments: user.email),
              ),
            ],
          ],
          const SizedBox(height: DiceUpSpacing.lg),
          Text(
            l10n.accountChangePassword,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: DiceUpSpacing.md),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DiceUpTextField(
                  label: l10n.authCurrentPasswordLabel,
                  controller: _currentController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.next,
                  enabled: !busy,
                  errorText: auth.fieldErrors['currentPassword'],
                  validator: (value) => value == null || value.isEmpty
                      ? l10n.authErrorRequired
                      : null,
                ),
                const SizedBox(height: DiceUpSpacing.md),
                DiceUpTextField(
                  label: l10n.authNewPasswordLabel,
                  controller: _newController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  enabled: !busy,
                  errorText: auth.fieldErrors['newPassword'],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.authErrorRequired;
                    }
                    if (value.length < 8) {
                      return l10n.authErrorPasswordTooShort;
                    }
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
                  onFieldSubmitted: (_) => _changePassword(),
                  enabled: !busy,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.authErrorRequired;
                    }
                    if (value != _newController.text) {
                      return l10n.authErrorPasswordsDoNotMatch;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: DiceUpSpacing.md),
                PrimaryButton(
                  label: l10n.accountChangePassword,
                  isLoading: _changingPassword,
                  onPressed: busy ? null : _changePassword,
                ),
              ],
            ),
          ),
          const SizedBox(height: DiceUpSpacing.lg),
          SecondaryButton(
            label: l10n.accountLogOut,
            onPressed: busy ? null : _logout,
          ),
        ],
      ),
    );
  }
}

/// One profile fact: label above value, caption style for the label.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DiceUpSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: DiceUpTypography.caption),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
