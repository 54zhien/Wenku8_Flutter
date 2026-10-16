import 'dart:math' as math;

double _smooth(double value) {
  final x = value.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

/// The row's peel and breeze are independent of the mesh column. Compute
/// those transcendental functions once per row, not once per vertex.
class PaperDepthRow {
  const PaperDepthRow(this.coefficient, this.landing, this.rowContact);
  final double coefficient, landing, rowContact;

  factory PaperDepthRow.sample(
    double progress,
    double row, {
    double? sineProgress,
  }) {
    if (progress <= 0 || progress >= 1) return const PaperDepthRow(0, 0, 0);
    final v = row.clamp(0.0, 1.0);
    final peel = _smooth((progress - .025 - v * .11) / .11);
    final landing = ((progress - .58) / .42).clamp(0.0, 1.0);
    final breeze = math.sin((v * 1.3 - progress * 1.6) * math.pi * 2);
    return PaperDepthRow(
      peel *
          (17 +
              7 * math.sin(v * math.pi) +
              3 * breeze * (sineProgress ?? math.sin(progress * math.pi))),
      landing,
      (1 - v) * .66,
    );
  }

  double at(double column) {
    if (coefficient == 0) return 0;
    final contact = rowContact + column.clamp(0.0, 1.0) * .34;
    return coefficient * (1 - _smooth((landing - contact * .70) / .30));
  }
}
