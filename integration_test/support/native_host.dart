import 'dart:async';
import 'dart:io';

import 'package:integration_test/integration_test.dart';

/// XCTest enables native accessibility as it attaches to the test host. Wait
/// in setUpAll for that suite-owned setup before testWidgets records its
/// semantics-handle baseline. Register all tests synchronously in main first.
/// The normal leak assertion remains enabled inside every test.
Future<void> awaitNativeTestHost(
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  const run = String.fromEnvironment('WENKU_TEST_RUN_ID');
  if (run.isEmpty) return; // Normal flutter test/drive owns its own startup.
  await waitForNativeTestHostFile(
    File('${Directory.systemTemp.path}/wenku-host-$run'),
  );
  // Process native semantics activation before the first tester's leak count.
  await binding.endOfFrame;
  await binding.endOfFrame;
}

/// iOS has no dart:io filesystem watcher. This bounded readiness check happens
/// in suite setup, outside every measured motion scene.
Future<void> waitForNativeTestHostFile(
  File marker, {
  Duration timeout = const Duration(seconds: 240),
}) async {
  final elapsed = Stopwatch()..start();
  while (!await marker.exists()) {
    final remaining = timeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException(
        'Native XCTest host did not become ready',
        timeout,
      );
    }
    const interval = Duration(milliseconds: 50);
    await Future<void>.delayed(remaining < interval ? remaining : interval);
  }
}
