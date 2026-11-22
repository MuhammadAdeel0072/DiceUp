import 'package:flutter/material.dart';

/// Whether the platform is requesting reduced motion (M3 premium,
/// research §2.7.1/R22).
///
/// Android's "Remove animations" setting is exposed through
/// [MediaQuery.disableAnimations]. iOS Reduce Motion is a distinct
/// `dart:ui.AccessibilityFeatures.reduceMotion` feature; it is not a
/// [MediaQueryData] property.
bool isReducedMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .reduceMotion;
