import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../l10n/app_strings.dart';
import '../navigation/app_routes.dart';
import '../providers/app_providers.dart';

/// Game mode selection (SRS UI-02, FR-12).
///
/// Offline modes are fully available. The online card opens the
/// online flow (Phase 5, Stage 7): signed-in players go to the
/// lobby, guests go to the login screen — the same split the home
/// screen's Play Online entry makes.
///
/// Presentation (redesign Stage 3A, REDESIGN-PLAN.md §3.2): the two
/// playable cards are visually distinct from each other — a filled
/// icon disc in the mode's own accent (teal for Play vs AI, navy
/// for Local multiplayer) plus the one-line "what happens" subtitle
/// each already carries — and the online card carries its own amber
/// disc, so all three read as playable modes. Content centres
/// in a [DiceUpSpacing.maxContentWidth] column on wide screens.
/// Navigation and semantics behaviour are unchanged.
class ModeSelectionScreen extends StatelessWidget {
  const ModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = stringsOf(context);
    // Semantics (M2.9, NFR-08): each tappable mode card is one
    // labelled button — title + subtitle in a single node — so a
    // screen reader hears the mode and what it means, not an icon
    // plus two loose texts plus an unexplained chevron. The tap
    // action is the same navigation the card's InkWell performs.
    void goVsAi() =>
        Navigator.of(context)
            .pushNamed(AppRoutes.offlineSetup, arguments: OfflineMode.vsAi);
    void goLocal() =>
        Navigator.of(context)
            .pushNamed(AppRoutes.offlineSetup, arguments: OfflineMode.local);
    // Online (Phase 5, Stage 7): the auth state is read at tap
    // time through the enclosing [ProviderScope] — never watched
    // in build (see the home screen's Play Online note): bare
    // screens (layout / accessibility tests) run without a scope,
    // and without one the card stays inert instead of crashing.
    void goOnline() {
      AuthStatus? status;
      try {
        final container = ProviderScope.containerOf(context);
        status = container.read(authStateProvider).status;
      } on StateError {
        return;
      }
      if (status == AuthStatus.signedIn) {
        Navigator.of(context).pushNamed(AppRoutes.onlineLobby);
      } else {
        Navigator.of(context).pushNamed(AppRoutes.login);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.modeTitle)),
      // M2.12 (NFR-09): scrolls when the cards cannot fit
      // (320x568 with a wide font, or a large system text scale)
      // instead of overflowing — the plain Column overflowed by
      // 74 px at 320x568 in the test harness, where the mode
      // subtitles wrap to 5–6 lines. On screens where everything
      // fits the layout is unchanged.
      body: SingleChildScrollView(
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
                Semantics(
                  button: true,
                  label: l10n.modeVsAiSemantics,
                  onTap: goVsAi,
                  excludeSemantics: true,
                  child: DiceUpCard(
                    onTap: goVsAi,
                    child: _ModeRow(
                      icon: Icons.smart_toy_outlined,
                      iconBackground: DiceUpColors.teal,
                      iconColor: Colors.white,
                      title: l10n.modeVsAi,
                      subtitle: l10n.modeVsAiDescription,
                    ),
                  ),
                ),
                const SizedBox(height: DiceUpSpacing.md),
                Semantics(
                  button: true,
                  label: l10n.modeLocalSemantics,
                  onTap: goLocal,
                  excludeSemantics: true,
                  child: DiceUpCard(
                    onTap: goLocal,
                    child: _ModeRow(
                      icon: Icons.people_outline,
                      iconBackground: DiceUpColors.navy,
                      iconColor: Colors.white,
                      title: l10n.modeLocal,
                      subtitle: l10n.modeLocalDescription,
                    ),
                  ),
                ),
                const SizedBox(height: DiceUpSpacing.md),
                Semantics(
                  button: true,
                  label: l10n.modeOnlineSemantics,
                  onTap: goOnline,
                  excludeSemantics: true,
                  child: DiceUpCard(
                    onTap: goOnline,
                    child: _ModeRow(
                      icon: Icons.public_outlined,
                      iconBackground: DiceUpColors.amber,
                      iconColor: Colors.white,
                      title: l10n.modeOnline,
                      subtitle: l10n.modeOnlineDescription,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.icon,
    required this.iconBackground,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;

  /// The filled 48 dp disc behind the icon (D-09): teal for Play vs
  /// AI, navy for Local multiplayer, amber for online — the distinct
  /// icon treatment that tells the three modes apart at a glance.
  final Color iconBackground;

  /// Icon colour on [iconBackground]: white on the filled discs.
  final Color iconColor;

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    final subtitleStyle = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        Container(
          width: DiceUpSpacing.minTouchTarget,
          height: DiceUpSpacing.minTouchTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: iconBackground,
            borderRadius: DiceUpSpacing.radiusMdBorder,
          ),
          child: Icon(icon, size: 28, color: iconColor),
        ),
        const SizedBox(width: DiceUpSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: titleStyle),
              const SizedBox(height: DiceUpSpacing.xxs),
              Text(subtitle, style: subtitleStyle),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: DiceUpColors.textSecondary),
      ],
    );
  }
}
