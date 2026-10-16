import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A radius feather that Flutter can also apply to embedded UIKit views.
///
/// iOS receives each backdrop filter's rectangular clip and Gaussian radius,
/// but not a Flutter-painted alpha ramp inside that filter. Feathering with
/// dstIn would therefore leave a uniformly blurred rectangle over native views.
/// Disjoint clips keep both renderers on the same radius without masking either
/// plane. At most eight feather passes plus one plateau are needed per edge.
class IOSScrollEdge extends StatelessWidget {
  const IOSScrollEdge({
    super.key,
    required this.blur,
    required this.plateau,
    required this.fromBottom,
    required this.child,
  });

  final double blur;
  final double plateau;
  final bool fromBottom;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      Positioned.fill(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            if (!height.isFinite ||
                height <= 0 ||
                !constraints.maxWidth.isFinite ||
                !(blur > 0) ||
                !blur.isFinite) {
              return const SizedBox.shrink();
            }
            final dpr = MediaQuery.devicePixelRatioOf(context);
            final held = plateau.isFinite
                ? ((plateau.clamp(0, height) * dpr).round() / dpr).clamp(
                    0.0,
                    height,
                  )
                : 0.0;
            final feather = height - held;
            final bands = <({double start, double end, double sigma})>[
              if (held > 0) (start: 0, end: held, sigma: blur),
            ];
            if (feather > 0) {
              final count = math.min(8, math.max(1, (feather * dpr).floor()));
              var start = held;
              for (var index = 0; index < count; index++) {
                final end = index == count - 1
                    ? height
                    : ((held + feather * (index + 1) / count) * dpr).round() /
                          dpr;
                if (end <= start) continue;
                final t = ((start + end) / 2 - held) / feather;
                final fade = t * t * (3 - 2 * t);
                bands.add((start: start, end: end, sigma: blur * (1 - fade)));
                start = end;
              }
            }
            return Stack(
              children: [
                for (final band in bands)
                  Positioned(
                    top: fromBottom ? null : band.start,
                    bottom: fromBottom ? band.start : null,
                    left: 0,
                    right: 0,
                    height: band.end - band.start,
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(
                          sigmaX: band.sigma,
                          sigmaY: band.sigma,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      child,
    ],
  );
}
