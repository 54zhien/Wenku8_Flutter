import 'package:flutter/widgets.dart';

import 'easy_glass.dart';
import 'ios_native_composition.dart';

/// The original single Gaussian and continuous alpha feather. UIKit controls
/// under this region use their cached native texture so the engine cannot apply
/// an unmatched rectangular blur to a live platform view.
class IOSScrollEdge extends StatelessWidget {
  const IOSScrollEdge({
    super.key,
    required this.blur,
    required this.plateau,
    required this.fromBottom,
    required this.child,
  });
  final double blur, plateau;
  final bool fromBottom;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      Positioned.fill(
        child: IOSNativeBlurRegion(
          child: EasyScrollEdge(
            blur: blur,
            plateau: plateau,
            fromBottom: fromBottom,
            child: const SizedBox.expand(),
          ),
        ),
      ),
      child,
    ],
  );
}
