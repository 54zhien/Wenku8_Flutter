import 'package:flutter/material.dart';

import 'native_effects.dart';

/// A continuous blur radius, not an opaque gradient painted over the content.
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
  Widget build(BuildContext context) => IgnorePointer(
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
