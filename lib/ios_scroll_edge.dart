import 'package:flutter/widgets.dart';

import 'easy_glass.dart';

/// The original single Gaussian and continuous alpha feather. This restores
/// Flutter's renderer; live UIKit underlap still needs a shared native edge or
/// engine support for the mask, not image proxies that break real touches.
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
  Widget build(BuildContext context) => EasyScrollEdge(
    blur: blur,
    plateau: plateau,
    fromBottom: fromBottom,
    child: child,
  );
}
