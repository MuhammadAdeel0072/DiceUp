import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';
import '../../core/design_system/diceup_components.dart';
import '../../core/design_system/diceup_shadows.dart';
import '../../core/design_system/diceup_spacing.dart';
import '../../l10n/app_strings.dart';
import '../navigation/app_routes.dart';

/// Game mode selection (SRS UI-02, FR-12).
///
/// Offline modes are fully available. The online card is visible but
/// honestly unavailable until Phase 5 — it explains that instead of
/// navigating to a dead end.
///
/// Presentation (redesign Stage 3A, REDESIGN-PLAN.md §3.2): the two
/// playable cards are visually distinct from each other — a filled
/// icon disc in the mode's own accent (teal for Play vs AI, navy
/// for Local multiplayer) plus the one-line "what happens" subtitle
/// each already carries — while the online card stays visibly inert
/// (muted surface, muted text, no chevron, no tap). Content centres
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
    // The online card is not tappable (Phase 5): it keeps its plain
    // text, with no button role and no tap action.
    void goVsAi() =>
        Navigator.of(context)
            .pushNamed(AppRoutes.offlineSetup, arguments: OfflineMode.vsAi);
    void goLocal() =>
        Navigator.of(context)
            .pushNamed(AppRoutes.offlineSetup, arguments: OfflineMode.local);
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
                DiceUpCard(
                  child: _ModeRow(
                    icon: Icons.public_outlined,
                    iconBackground: DiceUpColors.surfaceMuted,
                    iconColor: DiceUpColors.textSecondary,
                    title: l10n.modeOnline,
                    subtitle: l10n.modeOnlineDescription,
                    // M2.10 (M-13): no chevron — the card is not tappable
                    // and must not imply navigation. Muted text as
                    // well, so the inert card never reads as playable.
                    showChevron: false,
                    muted: true,
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
    this.showChevron = true,
    this.muted = false,
  });

  final IconData icon;

  /// The filled 48 dp disc behind the icon (D-09): teal for Play vs
  /// AI, navy for Local multiplayer, muted ivory for the inert
  /// online card — the distinct icon treatment that tells the two
  /// playable modes apart at a glance.
  final Color iconBackground;

  /// Icon colour on [iconBackground]: white on the filled teal/navy
  /// discs, secondary on the muted disc.
  final Color iconColor;

  final String title;
  final String subtitle;

  /// Whether the trailing navigation chevron renders. Tappable rows
  /// show it; the non-tappable online card (M2.10) hides it so the
  /// row never implies a destination it cannot reach.
  final bool showChevron;

  /// Whether the row is the inert online card: title and subtitle
  /// render in the secondary colour instead of the primary one.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    final subtitleStyle = Theme.of(context).textTheme.bodySmall;
    // Premium v2: the filled disc becomes a small lit badge — its
    // colour falling to navy at the bottom-right, a raised shadow
    // and a soft tinted ring of its own accent — so each playable
    // mode reads as a game tile instead of a settings row. The
    // inert online card keeps the muted flat disc: it must never
    // borrow the playable modes' energy. Chevron rows end in a
    // quiet tinted circle instead of a bare glyph. Sizes (48 dp
    // disc, D-09) and texts are unchanged.
    final discDecoration = BoxDecoration(
      gradient: muted
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                iconBackground,
                Color.lerp(iconBackground, DiceUpColors.navy, 0.28)!,
              ],
            ),
      color: muted ? iconBackground : null,
      borderRadius: DiceUpSpacing.radiusMdBorder,
      boxShadow: muted
          ? null
          : [
              ...DiceUpShadows.raised,
              BoxShadow(
                color: iconBackground.withValues(alpha: 0.20),
                blurRadius: 0,
                spreadRadius: 3,
              ),
            ],
    );
    return Row(
      children: [
        Container(
          width: DiceUpSpacing.minTouchTarget,
          height: DiceUpSpacing.minTouchTarget,
          alignment: Alignment.center,
          decoration: discDecoration,
          child: Icon(icon, size: 28, color: iconColor),
        ),
        const SizedBox(width: DiceUpSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: muted
                    ? titleStyle?.copyWith(color: DiceUpColors.textSecondary)
                    : titleStyle,
              ),
              const SizedBox(height: DiceUpSpacing.xxs),
              Text(subtitle, style: subtitleStyle),
            ],
          ),
        ),
        if (showChevron)
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: DiceUpColors.surfaceMuted,
            ),
            child: const Icon(
              Icons.chevron_right,
              size: 18,
              color: DiceUpColors.textSecondary,
            ),
          ),
      ],
    );
  }
}
