import 'package:flutter/material.dart';

import '../../core/design_system/diceup_colors.dart';

/// A dice face drawn with widgets — no image asset, no emoji.
///
/// [value] 1–6 renders the matching pip layout; null renders a blank
/// face (before the first roll). [rolling] shows a shimmer while the
/// [AnimationController]-driven roll animation runs on the game screen.
class DiceWidget extends StatelessWidget {
  const DiceWidget({
    super.key,
    required this.value,
    this.size = 64,
    this.rolling = false,
  });

  final int? value;
  final double size;
  final bool rolling;

  static const _pipLayouts = <int, List<Alignment>>{
    1: [Alignment.center],
    2: [Alignment.topLeft, Alignment.bottomRight],
    3: [Alignment.topLeft, Alignment.center, Alignment.bottomRight],
    4: [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ],
    5: [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.center,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ],
    6: [
      Alignment.topLeft,
      Alignment.topRight,
      Alignment.centerLeft,
      Alignment.centerRight,
      Alignment.bottomLeft,
      Alignment.bottomRight,
    ],
  };

  @override
  Widget build(BuildContext context) {
    final pips = value == null ? const <Alignment>[] : _pipLayouts[value]!;
    return AnimatedOpacity(
      opacity: rolling ? 0.6 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.18),
          border: Border.all(color: DiceUpColors.border, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: pips
              .map(
                (alignment) => Align(
                  alignment: alignment,
                  child: Padding(
                    padding: EdgeInsets.all(size * 0.14),
                    child: Container(
                      width: size * 0.16,
                      height: size * 0.16,
                      decoration: const BoxDecoration(
                        color: DiceUpColors.navy,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
