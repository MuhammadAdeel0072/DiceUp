import 'package:flutter/material.dart';

import '../../../core/design_system/diceup_colors.dart';
import '../../../core/design_system/diceup_spacing.dart';

/// Shared auth-screen chrome (Phase 5, Stage 2).
///
/// Every auth screen is a [Scaffold] with an app bar, a centred
/// max-width column that scrolls on short screens, and — when set —
/// one error banner or one info banner above the form. Banners are
/// data, not literals: callers pass already-localised copy.
class AuthScreenScaffold extends StatelessWidget {
  const AuthScreenScaffold({
    super.key,
    required this.title,
    required this.child,
    this.errorMessage,
    this.infoMessage,
  });

  final String title;
  final Widget child;
  final String? errorMessage;
  final String? infoMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: DiceUpSpacing.screenPadding,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DiceUpSpacing.maxContentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (errorMessage != null) ...[
                    _AuthBanner(message: errorMessage!, isError: true),
                    const SizedBox(height: DiceUpSpacing.md),
                  ],
                  if (infoMessage != null) ...[
                    _AuthBanner(message: infoMessage!, isError: false),
                    const SizedBox(height: DiceUpSpacing.md),
                  ],
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One banner above an auth form: error (red) or info (muted).
class _AuthBanner extends StatelessWidget {
  const _AuthBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DiceUpSpacing.md),
      decoration: BoxDecoration(
        color: isError
            ? DiceUpColors.error.withValues(alpha: 0.1)
            : DiceUpColors.surfaceMuted,
        borderRadius: DiceUpSpacing.radiusMdBorder,
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: isError ? DiceUpColors.error : DiceUpColors.textSecondary,
        ),
      ),
    );
  }
}
