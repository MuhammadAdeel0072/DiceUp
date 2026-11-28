import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/design_system/diceup_components.dart';
import '../../../core/design_system/diceup_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_strings.dart';
import '../../navigation/app_routes.dart';
import '../../providers/app_providers.dart';
import '../auth/auth_widgets.dart';
import 'online_connection_banner.dart';
import 'online_error_messages.dart';

/// Online lobby screen (Phase 5, Stage 3; UI-07, FR-43/44/46/47/59).
///
/// Two states, one screen:
/// * No room — entry: create (limit 2–4 + the frozen ruleset summary,
///   G-16) or join by 6-char code, plus a link to matchmaking.
/// * In a room — the waiting lobby: code with copy/share, member list
///   with readiness, a Ready toggle, host Start (enabled only when
///   FR-47 holds), and Leave.
///
/// The screen reads [roomLobbyProvider] and never touches the data
/// layer directly (boundary rule). All copy is localised; the only
/// bare numerals are the 2/3/4 segments (allowlisted, as on setup).
///
/// Stage 7: a `match:started` broadcast navigates to the online game
/// screen (the started banner is gone — the game screen owns the
/// match now), and the connection banner shows while in a room.
class OnlineLobbyScreen extends ConsumerStatefulWidget {
  const OnlineLobbyScreen({super.key});

  @override
  ConsumerState<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

class _OnlineLobbyScreenState extends ConsumerState<OnlineLobbyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  int _maxPlayers = 4;
  bool _enteredRoom = false;
  bool _copied = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    final state = ref.watch(roomLobbyProvider);
    final auth = ref.watch(authStateProvider);
    final userId = auth.user?.id;

    // A `match:started` broadcast opens the game screen (Stage 7).
    // The start is consumed first, so returning to the lobby does
    // not re-navigate on the same start.
    ref.listen(roomLobbyProvider.select((s) => s.matchStarted), (
      previous,
      next,
    ) {
      if (next == null || next == previous) return;
      ref.read(roomLobbyProvider.notifier).clearMatchStarted();
      Navigator.of(context)
          .pushNamed(AppRoutes.onlineGame, arguments: next.matchId);
    });

    // Deep entry from matchmaking: a room id passed as the route
    // argument loads the room once (the notifier owns the fetch).
    final roomIdArg = AppRoutes.roomIdArgOf(context);
    if (state.room == null && roomIdArg != null && !_enteredRoom) {
      _enteredRoom = true;
      Future.microtask(
        () => ref.read(roomLobbyProvider.notifier).enterRoom(roomIdArg),
      );
    }

    final rulesetVersion = ref.watch(authConfigProvider).rulesetVersion;
    return AuthScreenScaffold(
      title: l10n.onlineLobbyTitle,
      errorMessage: onlineErrorMessage(l10n, state.errorCode),
      infoMessage: _infoMessage(l10n, state),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The connection banner belongs here only while in a room
          // (Stage 7): before that the lobby is plain REST and the
          // socket is not yet the live channel.
          if (state.room != null) ...[
            OnlineConnectionBanner(
              state: state.connectionState,
              onRetry: () =>
                  ref.read(roomLobbyProvider.notifier).retryConnection(),
            ),
            const SizedBox(height: DiceUpSpacing.md),
          ],
          if (state.room == null)
            _EntryView(
              formKey: _formKey,
              codeController: _codeController,
              maxPlayers: _maxPlayers,
              rulesetVersion: rulesetVersion,
              isBusy: state.isBusy,
              onMaxPlayers: (value) => setState(() => _maxPlayers = value),
              onCreate: () => ref
                  .read(roomLobbyProvider.notifier)
                  .createRoom(maxPlayers: _maxPlayers),
              onJoin: () {
                if (_formKey.currentState?.validate() ?? false) {
                  ref
                      .read(roomLobbyProvider.notifier)
                      .joinRoom(_codeController.text.trim());
                }
              },
            )
          else
            _LobbyView(
              room: state.room!,
              userId: userId,
              isBusy: state.isBusy,
              copied: _copied,
              onReady: (ready) =>
                  ref.read(roomLobbyProvider.notifier).setReady(ready),
              onStart: () => ref.read(roomLobbyProvider.notifier).startMatch(),
              onLeave: () => ref.read(roomLobbyProvider.notifier).leaveRoom(),
              onCopy: () async {
                await Clipboard.setData(ClipboardData(text: state.room!.code));
                if (mounted) setState(() => _copied = true);
              },
              onShare: () {
                final user = ref.read(authStateProvider).user;
                if (user == null) return;
                final service = ref.read(gameRoomServiceProvider);
                unawaited(
                  SharePlus.instance.share(
                    ShareParams(text: service.inviteFriend(user.id)),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String? _infoMessage(AppLocalizations l10n, RoomLobbyState state) {
    if (_copied) return l10n.onlineCodeCopied;
    return null;
  }
}

/// Entry: create + join + matchmaking link.
class _EntryView extends StatelessWidget {
  const _EntryView({
    required this.formKey,
    required this.codeController,
    required this.maxPlayers,
    required this.rulesetVersion,
    required this.isBusy,
    required this.onMaxPlayers,
    required this.onCreate,
    required this.onJoin,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController codeController;
  final int maxPlayers;
  final String rulesetVersion;
  final bool isBusy;
  final ValueChanged<int> onMaxPlayers;
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.onlineCreateTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: DiceUpSpacing.sm),
        // The frozen ruleset, shown before readiness (G-16, OD-11):
        // every Phase 5 match uses RULESET_VERSION; there are no
        // host-selectable rule options.
        Text(l10n.onlineRulesetSummary(rulesetVersion)),
        const SizedBox(height: DiceUpSpacing.md),
        Row(
          children: [
            Text(l10n.onlineMaxPlayers),
            const SizedBox(width: DiceUpSpacing.md),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(value: 2, label: Text('2')),
                ButtonSegment<int>(value: 3, label: Text('3')),
                ButtonSegment<int>(value: 4, label: Text('4')),
              ],
              selected: {maxPlayers},
              onSelectionChanged: (selection) => onMaxPlayers(selection.first),
            ),
          ],
        ),
        const SizedBox(height: DiceUpSpacing.md),
        PrimaryButton(
          label: l10n.onlineCreateButton,
          onPressed: isBusy ? null : onCreate,
          isLoading: isBusy,
        ),
        const SizedBox(height: DiceUpSpacing.lg),
        Text(
          l10n.onlineJoinTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: DiceUpSpacing.sm),
        Form(
          key: formKey,
          child: DiceUpTextField(
            label: l10n.onlineCodeLabel,
            controller: codeController,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onJoin(),
            enabled: !isBusy,
            inputFormatters: [
              UpperCaseTextFormatter(),
              LengthLimitingTextInputFormatter(6),
            ],
            validator: (value) {
              final code = (value ?? '').trim().toUpperCase();
              if (code.length != 6 ||
                  !RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code)) {
                return l10n.onlineErrorRoomNotFound;
              }
              return null;
            },
          ),
        ),
        const SizedBox(height: DiceUpSpacing.sm),
        Text(l10n.onlineCodeHint),
        const SizedBox(height: DiceUpSpacing.md),
        SecondaryButton(
          label: l10n.onlineJoinButton,
          onPressed: isBusy ? null : onJoin,
        ),
        const SizedBox(height: DiceUpSpacing.lg),
        SecondaryButton(
          label: l10n.onlineJoinQueue,
          onPressed: isBusy
              ? null
              : () => Navigator.of(context).pushNamed(AppRoutes.matchmaking),
        ),
      ],
    );
  }
}

/// Waiting lobby: code, members, readiness, start, leave.
class _LobbyView extends StatelessWidget {
  const _LobbyView({
    required this.room,
    required this.userId,
    required this.isBusy,
    required this.copied,
    required this.onReady,
    required this.onStart,
    required this.onLeave,
    required this.onCopy,
    required this.onShare,
  });

  final LobbyRoom room;
  final String? userId;
  final bool isBusy;
  final bool copied;
  final ValueChanged<bool> onReady;
  final VoidCallback onStart;
  final VoidCallback onLeave;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    final myMember = room.members
        .where((m) => m.userId == userId)
        .fold<LobbyMember?>(null, (prev, m) => m);
    final myId = userId;
    final canStart = myId != null && room.canStart(myId);
    final blocker = myId != null ? room.startBlocker(myId) : 'notHost';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DiceUpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                room.code,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: DiceUpSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SecondaryButton(
                    label: l10n.onlineCopyCode,
                    onPressed: onCopy,
                  ),
                  const SizedBox(width: DiceUpSpacing.md),
                  SecondaryButton(
                    label: l10n.onlineShareCode,
                    onPressed: onShare,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: DiceUpSpacing.md),
        Text(
          l10n.onlineRulesetSummary(room.rulesetVersion),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: DiceUpSpacing.md),
        Text(
          l10n.onlineMembers,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: DiceUpSpacing.sm),
        ...room.members.map(
          (member) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(member.displayName),
            subtitle: Text(
              [
                if (member.isHost) l10n.onlineHost,
                if (member.userId == userId) l10n.onlineYou,
              ].join(' · '),
            ),
            trailing: member.isReady
                ? Icon(
                    Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : Icon(
                    Icons.radio_button_unchecked,
                    color: Theme.of(context).disabledColor,
                  ),
          ),
        ),
        const SizedBox(height: DiceUpSpacing.md),
        if (myMember != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.onlineReady),
            value: myMember.isReady,
            onChanged: isBusy ? null : onReady,
          ),
        if (!canStart && blocker != null) ...[
          const SizedBox(height: DiceUpSpacing.sm),
          Text(_blockerMessage(l10n, blocker)),
        ],
        const SizedBox(height: DiceUpSpacing.md),
        PrimaryButton(
          label: l10n.onlineStartMatch,
          onPressed: canStart && !isBusy ? onStart : null,
          isLoading: isBusy,
        ),
        const SizedBox(height: DiceUpSpacing.md),
        SecondaryButton(
          label: l10n.onlineLeaveRoom,
          onPressed: isBusy ? null : onLeave,
        ),
      ],
    );
  }

  String _blockerMessage(AppLocalizations l10n, String blocker) {
    return switch (blocker) {
      'notHost' => l10n.onlineNotHost,
      'needPlayers' => l10n.onlineNeedPlayers,
      'needReady' => l10n.onlineNeedReady,
      _ => l10n.onlineNotHost,
    };
  }
}

/// Upper-cases room-code input as it is typed.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
