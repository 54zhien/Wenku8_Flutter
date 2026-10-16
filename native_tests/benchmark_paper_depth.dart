// AOT CPU microbenchmark of the actual production depth kernel. This does not
// measure app FPS, UIKit, rasterization, or physical-device presentation.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:wenku8_flutter/paper_depth.dart';

double baseline(double progress, double row, double column) {
  if (progress <= 0 || progress >= 1) return 0;
  double smooth(double value) {
    final x = value.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  final v = row.clamp(0.0, 1.0);
  final peel = smooth((progress - .025 - v * .11) / .11);
  final landing = ((progress - .58) / .42).clamp(0.0, 1.0);
  final contact = (1 - v) * .66 + column.clamp(0.0, 1.0) * .34;
  final floating = 1 - smooth((landing - contact * .70) / .30);
  final breeze = math.sin((v * 1.3 - progress * 1.6) * math.pi * 2);
  return peel *
      floating *
      (17 +
          7 * math.sin(v * math.pi) +
          3 * breeze * math.sin(progress * math.pi));
}

double run(bool cached, int iterations) {
  var checksum = 0.0;
  for (var tick = 0; tick < iterations; tick++) {
    final progress = (tick % 120) / 120;
    final sine = math.sin(progress * math.pi);
    for (var row = 0; row < 49; row++) {
      final v = row / 48;
      final sample = cached
          ? PaperDepthRow.sample(progress, v, sineProgress: sine)
          : null;
      for (var column = 0; column < 17; column++) {
        final u = column / 16;
        checksum += cached ? sample!.at(u) : baseline(progress, v, u);
      }
    }
  }
  return checksum;
}

void main(List<String> arguments) {
  final iterations = arguments.isEmpty ? 12000 : int.parse(arguments.first);
  run(false, 1200);
  run(true, 1200);
  final before = <int>[], after = <int>[];
  double measure(bool cached) {
    final clock = Stopwatch()..start();
    final checksum = run(cached, iterations);
    clock.stop();
    (cached ? after : before).add(clock.elapsedMicroseconds);
    return checksum;
  }

  for (var sample = 0; sample < 7; sample++) {
    final a = sample.isEven ? measure(false) : measure(true);
    final b = sample.isEven ? measure(true) : measure(false);
    if ((a - b).abs() > a.abs() * 1e-10) {
      throw StateError('Choreography checksum mismatch');
    }
  }
  int median(List<int> values) =>
      (List<int>.of(values)..sort())[values.length ~/ 2];
  stdout.writeln(
    jsonEncode({
      'scope': 'production paper-depth CPU kernel only; not app FPS',
      'runtime': Platform.version,
      'os': Platform.operatingSystem,
      'iterations_per_sample': iterations,
      'vertices_per_iteration': 49 * 17,
      'before_us': before,
      'after_us': after,
      'before_median_us': median(before),
      'after_median_us': median(after),
      'speedup': median(before) / median(after),
    }),
  );
}
