import 'package:diceup/l10n/app_localizations.dart';
import 'package:diceup/l10n/app_localizations_en.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/engine/player_colour.dart';
import 'diceup_colors.dart';
import 'diceup_spacing.dart';
import 'diceup_typography.dart';

/// Localised strings for the build context's locale (M3.10, NFR-38).
///
/// This file cannot use `lib/l10n/app_strings.dart`'s [stringsOf]:
/// that helper imports this file (for [PlayerShape]), so importing it
/// back would be a cycle. The fallback is the same: English when no
/// delegates are registered above [context] (bare-`MaterialApp`
/// widget tests), which renders exactly the strings the tests assert.
AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsEn();

/// Reusable DiceUp components (SDD §11.5).
///
/// Every screen builds from these — no screen invents its own button,
/// card or dialog style. Interactive elements meet the 48x48 dp
/// minimum touch target (SRS NFR-08, confirmed binding by D-21):
/// the button themes in [DiceUpTheme] enforce it, and the
/// hand-built controls (e.g. the setup colour swatches) are sized to
/// [DiceUpSpacing.minTouchTarget]. Board tokens are the one exemption
/// — game pieces, not controls (D-09; full-cell hit area).

/// Primary call-to-action button. Disabled while [onPressed] is null,
/// which is how invalid actions are prevented (SDD §11.2, error prevention).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label),
    );
  }
}

/// Secondary action button.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(onPressed: onPressed, child: Text(label));
  }
}

/// Standard content card.
///
/// [padding] defaults to [DiceUpSpacing.cardPadding]; the game
/// screen's turn banner passes a vertically compact padding on
/// short screens (M2.12, NFR-09) so the dice row stays above the
/// fold at 320x568 — every other card keeps the default.
class DiceUpCard extends StatelessWidget {
  const DiceUpCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = DiceUpSpacing.cardPadding,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: DiceUpSpacing.radiusLgBorder,
      child: card,
    );
  }
}

/// A player's shape marker (NFR-08, D-27): the same per-seat shapes
/// as the board tokens in [LudoBoardPainter] — seat 0 circle, 1
/// square, 2 diamond, 3 triangle — so a player is identifiable by
/// shape as well as by colour and name. The shape follows the *seat*,
/// never the chosen colour: after a colour swap the seat (and its
/// board tokens) stay the same, so the avatar's shape must too.
enum PlayerShape {
  circle,
  square,
  diamond,
  triangle;

  static PlayerShape forSeat(int seatIndex) =>
      PlayerShape.values[seatIndex % PlayerShape.values.length];
}

/// A small filled shape in [color] with a thin white edge (the same
/// treatment as the board tokens, so the marker reads on the white
/// avatar disc). Used as the avatar's shape badge; the board painter
/// keeps its own copy of the shapes (it draws on canvas, not widgets).
class PlayerShapeMarker extends StatelessWidget {
  const PlayerShapeMarker({
    super.key,
    required this.shape,
    required this.color,
    required this.size,
  });

  final PlayerShape shape;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _PlayerShapePainter(shape, color),
    );
  }
}

class _PlayerShapePainter extends CustomPainter {
  _PlayerShapePainter(this.shape, this.color);

  final PlayerShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 1;
    final fill = Paint()..color = color;
    final edge = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    switch (shape) {
      case PlayerShape.circle:
        canvas.drawCircle(centre, radius, fill);
        canvas.drawCircle(centre, radius, edge);
      case PlayerShape.square:
        final rect = Rect.fromCircle(center: centre, radius: radius * 0.92);
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, edge);
      case PlayerShape.diamond:
        final diamond = Path()
          ..moveTo(centre.dx, centre.dy - radius)
          ..lineTo(centre.dx + radius, centre.dy)
          ..lineTo(centre.dx, centre.dy + radius)
          ..lineTo(centre.dx - radius, centre.dy)
          ..close();
        canvas.drawPath(diamond, fill);
        canvas.drawPath(diamond, edge);
      case PlayerShape.triangle:
        final triangle = Path()
          ..moveTo(centre.dx, centre.dy - radius)
          ..lineTo(centre.dx + radius, centre.dy + radius * 0.8)
          ..lineTo(centre.dx - radius, centre.dy + radius * 0.8)
          ..close();
        canvas.drawPath(triangle, fill);
        canvas.drawPath(triangle, edge);
    }
  }

  @override
  bool shouldRepaint(covariant _PlayerShapePainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}

/// Player avatar (D-27, M2.4): a white disc with the player's initial
/// in navy, a ring in the player's colour, and a per-seat shape marker
/// — so players are distinguishable by name, colour *and* shape, never
/// by colour alone (NFR-08).
///
/// The initial is [DiceUpColors.navy] on white: 14.11:1 by the WCAG
/// formula ([DiceUpColors.contrastRatio]), the same for every seat —
/// the three failing white-on-player-colour ratios (red 3.91, green
/// 3.04, yellow 1.85) no longer apply, because no text sits on a
/// player colour anymore. Board tokens and the palette constants are
/// untouched (D-27): only the avatar changed.
///
/// [colour] is the player's *chosen* colour (M2.2) and drives the
/// ring; when it is null the ring falls back to the seat-order colour
/// ([DiceUpColors.playerColor]). The shape always follows the seat
/// ([PlayerShape.forSeat]), matching the board tokens.
///
/// Semantics (M2.9, NFR-08; D-27): the avatar is one labelled node —
/// the player's name, seat shape and colour name (e.g. "Adeel, circle
/// token, red") — so a screen reader identifies the player by name
/// and shape, never by colour alone, and never hears the bare initial
/// letter ("P") the disc draws. The shape marker and initial are
/// decorative inside that node.
class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.name,
    required this.seatIndex,
    this.colour,
    this.radius = 20,
  });

  final String name;
  final int seatIndex;
  final PlayerColour? colour;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    final ringColour = colour != null
        ? DiceUpColors.forColour(colour!)
        : DiceUpColors.playerColor(seatIndex);
    final shape = PlayerShape.forSeat(seatIndex);
    // The colour name in the label is the ring's colour: the chosen
    // colour when given, else the seat-order colour — the same
    // source as [ringColour] ([DiceUpColors.playerColor] is ordered
    // to match [PlayerColour.values], see diceup_colors.dart).
    // M3.10: the shape and colour names are localised (the same
    // mapping lives in lib/l10n/app_strings.dart for the screens;
    // this file cannot import that helper without a cycle).
    final colourValue =
        colour ?? PlayerColour.values[seatIndex % PlayerColour.values.length];
    final l10n = _l10n(context);
    final shapeLabel = switch (shape) {
      PlayerShape.circle => l10n.shapeCircle,
      PlayerShape.square => l10n.shapeSquare,
      PlayerShape.diamond => l10n.shapeDiamond,
      PlayerShape.triangle => l10n.shapeTriangle,
    };
    final colourLabel = switch (colourValue) {
      PlayerColour.red => l10n.colourRed,
      PlayerColour.green => l10n.colourGreen,
      PlayerColour.yellow => l10n.colourYellow,
      PlayerColour.blue => l10n.colourBlue,
    };
    final ringWidth = (radius * 0.15).clamp(2.0, 3.0);
    final badgeSize = radius * 0.75;
    return Semantics(
      // gen-l10n orders the positional parameters alphabetically
      // (colour, name, shape), not in message order.
      label: l10n.avatarLabel(colourLabel, name, shapeLabel),
      excludeSemantics: true,
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              key: const ValueKey('player-avatar-disc'),
              width: radius * 2,
              height: radius * 2,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: ringColour, width: ringWidth),
              ),
              child: Text(
                initial,
                style: TextStyle(
                  color: DiceUpColors.navy,
                  fontWeight: FontWeight.w700,
                  fontSize: radius * 0.85,
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: PlayerShapeMarker(
                key: ValueKey('player-avatar-shape-${shape.name}'),
                shape: shape,
                color: ringColour,
                size: badgeSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen loading state with an optional message (visibility of
/// system status, SDD §11.2).
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: DiceUpColors.teal),
          if (message != null) ...[
            const SizedBox(height: DiceUpSpacing.md),
            Text(message!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Error state with a retry action. Never shows a stack trace or
/// internal error text to the user.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: DiceUpSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: DiceUpColors.error,
            ),
            const SizedBox(height: DiceUpSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: DiceUpSpacing.md),
              SecondaryButton(
                label: _l10n(context).tryAgain,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty state: an icon, a title and a hint about what to do next.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: DiceUpSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: DiceUpColors.textSecondary),
            const SizedBox(height: DiceUpSpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: DiceUpSpacing.xs),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Section heading (redesign Stage 2, REDESIGN-PLAN.md §3.3/§4):
/// the visible group label for the setup "Players / Seats / House
/// rules" sections, settings groups and results groups. A title in
/// [DiceUpTypography.sectionHeading] with an optional [subtitle] in
/// the caption style — never a bare `titleMedium` label, so sections
/// stop blending into the cards below them. Exposed as a semantics
/// header so a screen reader announces it as a heading.
class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: DiceUpTypography.sectionHeading),
          if (subtitle != null) ...[
            const SizedBox(height: DiceUpSpacing.xxs),
            Text(subtitle!, style: DiceUpTypography.caption),
          ],
        ],
      ),
    );
  }
}

/// Statistic tile (redesign Stage 2, REDESIGN-PLAN.md §3.6/§3.7):
/// one large numeral ([DiceUpTypography.displayNumeral]) with a
/// caption label underneath, in a [DiceUpCard]. Used for the
/// statistics 2x2 totals grid and the results info stat row. The
/// [value] is a preformatted string (e.g. "12", "04:32") so the
/// tile never formats numbers itself; [icon] is an optional
/// Material/Cupertino glyph, never emoji.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DiceUpCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 24, color: DiceUpColors.teal),
            const SizedBox(height: DiceUpSpacing.xs),
          ],
          Text(
            value,
            style: DiceUpTypography.displayNumeral,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: DiceUpSpacing.xxs),
          Text(
            label,
            style: DiceUpTypography.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Shared dialog shell (redesign Stage 2, REDESIGN-PLAN.md §4/F7):
/// every dialog in the app goes through this wrapper so dialogs
/// share the ivory surface and 16 dp radius from [DiceUpTheme]'s
/// dialog theme instead of each screen building its own stock
/// [AlertDialog]. The title is navy (theme), the content is
/// [content] as given, and [actions] are the caller's buttons —
/// primary as [ElevatedButton], secondary as [TextButton] — in
/// that order, so there is never more than one primary action.
/// [ConfirmationDialog] is built on this; the pause menu and the
/// resume/detail dialogs move to it in Stage 3.
class DiceUpDialog extends StatelessWidget {
  const DiceUpDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });

  final String title;
  final Widget content;
  final List<Widget> actions;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget content,
    List<Widget> actions = const [],
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) =>
          DiceUpDialog(title: title, content: content, actions: actions),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(title: Text(title), content: content, actions: actions);
  }
}

/// Confirmation dialog for destructive or important actions
/// (exit a match, restart, leave a room, delete an account).
class ConfirmationDialog extends StatelessWidget {
  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;

  /// Dismiss action label. Null renders the localised "Cancel"
  /// (M3.10) — callers pass an explicit label only when the
  /// dismissal means something else.
  final String? cancelLabel;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String? cancelLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return DiceUpDialog(
      title: title,
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel ?? _l10n(context).cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Text field following the DiceUp input style.
class DiceUpTextField extends StatelessWidget {
  const DiceUpTextField({
    super.key,
    required this.label,
    this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
    this.onChanged,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;

  /// Input formatters (M2.2: the setup name field caps input at 12
  /// characters with a [LengthLimitingTextInputFormatter], so the
  /// 13th character is blocked while typing instead of rejected
  /// after the fact).
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(labelText: label),
    );
  }
}
