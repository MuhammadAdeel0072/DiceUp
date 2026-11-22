import 'package:flutter/material.dart';

/// Whether the platform is requesting reduced motion for this build
/// context (M3 premium, research §2.7.1/R22; SDK-compatibility fix
/// 2026-11-23).
///
/// Reads [MediaQuery.disableAnimations] — Android's "Remove animations"
/// accessibility setting — via [MediaQuery.disableAnimationsOf]. That
/// API has existed since Flutter 3.13, comfortably inside this
/// project's supported range, and the framework's [AnimationController]
/// behaviour already respects it, so reduced-motion support is
/// preserved (not removed) on every supported SDK.
///
/// `MediaQueryData.reduceMotion` — the iOS-only "Reduce Motion" flag —
/// is intentionally NOT read here: it does not exist on the oldest
/// Flutter SDKs this project supports (it broke `flutter build apk`
/// on an SDK that otherwise compiles the app), so on those SDKs the
/// iOS flag cannot be read through MediaQuery at all. If the minimum
/// Flutter version is ever raised to a release that has
/// `reduceMotion`, restore the `|| MediaQuery.of(context).reduceMotion`
/// check here — in this one place only.
///
/// Do not probe for `reduceMotion` with `dynamic`: the whole point of
/// this helper is that the app compiles on SDKs that do not have it.
bool isReducedMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);
