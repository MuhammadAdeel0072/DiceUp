import 'package:flutter/services.dart';

/// Haptic feedback behind a small abstraction (M1.7, D-32).
///
/// The game screen vibrates through [FeedbackService], never through
/// `HapticFeedback` directly, so the wiring is testable: tests inject
/// a fake that records calls, and the production implementation is
/// one line. The abstraction covers haptics only — sound is a named
/// follow-up (D-32) with no audio dependency and no sound assets in
/// this milestone, so there is deliberately no audio method here.
abstract class FeedbackService {
  /// A short vibration for one completed move.
  Future<void> vibrateMove();
}

/// The production implementation: one light haptic per move.
class HapticFeedbackService implements FeedbackService {
  const HapticFeedbackService();

  @override
  Future<void> vibrateMove() => HapticFeedback.lightImpact();
}
