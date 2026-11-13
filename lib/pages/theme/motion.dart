import 'package:flutter/widgets.dart';

/// Shared policy for non-essential movement, including system preference changes.
abstract final class AppMotion {
  static bool reducedOf(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final reduceMotion = MediaQuery.reduceMotionOf(context);
    return disableAnimations || reduceMotion;
  }

  static Duration durationOf(BuildContext context, Duration normal) =>
      reducedOf(context) ? Duration.zero : normal;
}
