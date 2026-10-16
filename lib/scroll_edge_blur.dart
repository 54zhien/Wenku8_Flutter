import 'package:flutter/material.dart';

import 'native_effects.dart';
import 'ios_glass.dart';

/// Reference radius profile for the continuous-kernel renderer. The default
/// renderer feathers a live native Gaussian, without an opaque gradient fill.
abstract final class ScrollEdgeProfile {
  static double sigma(double progress, {double maximum = 20}) {
    final depth = 1 - progress.clamp(0.0, 1.0);
    // Zero radius and zero slope where clear content first enters the feather.
    return maximum * depth * depth;
  }
}

class ProgressiveBlur extends StatelessWidget {
  const ProgressiveBlur({
    super.key,
    this.maxSigma = 8,
    this.plateauHeight = 0,
    this.fromBottom = false,
  });

  final double maxSigma;
  final double plateauHeight;
  final bool fromBottom;

  @override
  Widget build(BuildContext context) => nativeIOSGlassEnabled
      // Flutter's shader/backdrop compositor can obscure UIKit foregrounds.
      // This is a scroll-edge legibility fade, not a simulated glass material.
      ? IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: fromBottom
                    ? Alignment.bottomCenter
                    : Alignment.topCenter,
                end: fromBottom ? Alignment.topCenter : Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.surface.withValues(alpha: .94),
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0),
                ],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        )
      : IgnorePointer(
          child: maxSigma <= 0
              ? const SizedBox.expand()
              : NativeBackdrop(
                  effect: NativeEffect.progressive,
                  blur: maxSigma,
                  plateau: plateauHeight,
                  fromBottom: fromBottom,
                  child: const SizedBox.expand(),
                ),
        );
}
