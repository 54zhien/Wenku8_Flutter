import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/ios_motion_diagnostics.dart';

void main() {
  testWidgets(
    'route capture keeps actual timings, excludes other windows and never includes page content',
    (tester) async {
      var now = DateTime.utc(2026, 10, 16);
      Map<String, Object?>? saved;
      final recorder = IOSMotionDiagnostics(
        environment: () => {'refresh_hz': 60.0, 'reduce_motion': false},
        save: (report) async {
          saved = report;
        },
        now: () => now,
      );
      final previous = PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const Text('private title'),
      );
      final route = PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const Text('private prose'),
        settings: const RouteSettings(name: 'private route'),
      );
      recorder.didPush(previous, null);
      expect(recorder.windowCount, 0);
      recorder.didPush(route, previous);
      tester.binding.platformDispatcher.onReportTimings!([
        ui.FrameTiming(
          vsyncStart: 0,
          buildStart: 100,
          buildFinish: 1100,
          rasterStart: 1200,
          rasterFinish: 2200,
          rasterFinishWallTime: now.microsecondsSinceEpoch + 100000,
        ),
        ui.FrameTiming(
          vsyncStart: 0,
          buildStart: 100,
          buildFinish: 1100,
          rasterStart: 1200,
          rasterFinish: 2200,
          rasterFinishWallTime: now.microsecondsSinceEpoch - 1,
        ),
        ui.FrameTiming(
          vsyncStart: 0,
          buildStart: 100,
          buildFinish: 1100,
          rasterStart: 1200,
          rasterFinish: 2200,
          rasterFinishWallTime: now.microsecondsSinceEpoch + 2000001,
        ),
      ]);
      now = now.add(const Duration(seconds: 4));
      await recorder.flush();
      final event = (saved!['events'] as List).single as Map;
      expect((event['frames'] as List).length, 1);
      expect(event['action'], 'push');
      expect(event['environment'], {
        'refresh_hz': 60.0,
        'reduce_motion': false,
      });
      expect(saved.toString(), isNot(contains('private')));
      expect(saved!['actual_present_fps_measured'], false);
      recorder.dispose();
    },
  );

  testWidgets(
    'diagnostic memory is bounded and disposal removes timing hooks',
    (tester) async {
      final recorder = IOSMotionDiagnostics(
        environment: () => {},
        save: (_) async {},
      );
      final route = PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const SizedBox(),
      );
      for (var i = 0; i < 20; i++) {
        recorder.didPop(route, route);
      }
      expect(recorder.windowCount, 10);
      recorder.dispose();
      expect(recorder.windowCount, 0);
      await recorder.flush();
    },
  );
}
