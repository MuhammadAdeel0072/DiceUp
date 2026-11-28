import 'package:flutter/material.dart';

import '../../../core/design_system/diceup_colors.dart';
import '../../../core/design_system/diceup_components.dart';
import '../../../core/design_system/diceup_spacing.dart';
import '../../../domain/online/connection_state.dart';
import '../../../l10n/app_strings.dart';

/// Connection / reconnection banner (Phase 5, Stage 7).
///
/// Renders nothing while [state] is connected — the caller decides
/// *when* a banner belongs on its screen (the game screen always
/// includes it; the lobby only while in a room, where the socket
/// carries the live updates), and this widget decides *what* it
/// says. The copy is honest about the Stage 6 design: no intent is
/// queued or replayed while disconnected, so the banner never
/// promises a later send — it says moves cannot be sent until the
/// connection is back. [onRetry] is the manual reconnect action.
class OnlineConnectionBanner extends StatelessWidget {
  const OnlineConnectionBanner({
    super.key,
    required this.state,
    required this.onRetry,
  });

  final GameSocketConnectionState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (state == GameSocketConnectionState.connected) {
      return const SizedBox.shrink();
    }
    final l10n = stringsOf(context);
    final (message, showRetry) = switch (state) {
      GameSocketConnectionState.connecting => (
        l10n.onlineConnectionConnecting,
        false,
      ),
      GameSocketConnectionState.reconnecting => (
        l10n.onlineConnectionReconnecting,
        true,
      ),
      GameSocketConnectionState.disconnected => (
        l10n.onlineConnectionDisconnected,
        true,
      ),
      GameSocketConnectionState.connected => ('', false),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DiceUpSpacing.md,
        vertical: DiceUpSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: DiceUpColors.amberLight,
        borderRadius: DiceUpSpacing.radiusMdBorder,
        border: Border.all(color: DiceUpColors.amber),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, color: DiceUpColors.amber),
          const SizedBox(width: DiceUpSpacing.sm),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (showRetry) ...[
            const SizedBox(width: DiceUpSpacing.sm),
            SecondaryButton(
              label: l10n.onlineConnectionRetry,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
