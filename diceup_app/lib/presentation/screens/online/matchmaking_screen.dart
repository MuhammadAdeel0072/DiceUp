import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/diceup_components.dart';
import '../../../core/design_system/diceup_spacing.dart';
import '../../../l10n/app_strings.dart';
import '../../navigation/app_routes.dart';
import '../../providers/app_providers.dart';
import '../auth/auth_widgets.dart';
import 'online_error_messages.dart';

/// Matchmaking screen (Phase 5, Stage 3; FR-45, UI-07).
///
/// Join the queue, watch the position, cancel any time. A queue entry
/// never expires on its own (G-6) — the player waits until a group of
/// 4 forms or cancels. When a group forms, the screen shows the room
/// code and offers the lobby (the room loads there via
/// [RoomLobbyNotifier.enterRoom]).
///
/// The screen reads [matchmakingProvider] and never touches the data
/// layer directly (boundary rule). All copy is localised.
class MatchmakingScreen extends ConsumerWidget {
  const MatchmakingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = stringsOf(context);
    final state = ref.watch(matchmakingProvider);
    final notifier = ref.read(matchmakingProvider.notifier);

    return AuthScreenScaffold(
      title: l10n.onlineMatchmakingTitle,
      errorMessage: onlineErrorMessage(l10n, state.errorCode),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.isQueued) ...[
            Text(l10n.onlineQueuePosition(state.position)),
            const SizedBox(height: DiceUpSpacing.sm),
            Text(l10n.onlineQueueSize(state.queueSize)),
            const SizedBox(height: DiceUpSpacing.md),
            SecondaryButton(
              label: l10n.onlineCancelQueue,
              onPressed: state.isBusy ? null : () => notifier.cancelQueue(),
            ),
          ] else if (state.isMatched && state.roomCode != null) ...[
            Text(l10n.onlineMatched(state.roomCode!)),
            const SizedBox(height: DiceUpSpacing.md),
            PrimaryButton(
              label: l10n.onlineGoToLobby,
              onPressed: state.roomId == null
                  ? null
                  : () => Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.onlineLobby, arguments: state.roomId),
            ),
          ] else ...[
            PrimaryButton(
              label: l10n.onlineJoinQueue,
              onPressed: state.isBusy ? null : () => notifier.joinQueue(),
              isLoading: state.isBusy,
            ),
          ],
        ],
      ),
    );
  }
}
