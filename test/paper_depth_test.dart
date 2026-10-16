import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/motion_ui.dart';
import 'package:wenku8_flutter/paper_depth.dart';

void main() {
  test('cached row depth preserves the existing paper choreography', () {
    for (var tick = 0; tick <= 120; tick++) {
      final progress = tick / 120;
      final original = PaperFlightPose(progress);
      for (var row = 0; row <= 48; row++) {
        final v = row / 48;
        final cached = PaperDepthRow.sample(progress, v);
        for (var column = 0; column <= 16; column++) {
          final u = column / 16;
          expect(cached.at(u), closeTo(original.depthAt(v, column: u), 1e-10));
        }
      }
    }
  });
}
