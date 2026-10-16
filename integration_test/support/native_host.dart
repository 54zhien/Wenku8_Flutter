import 'dart:async';
import 'dart:io';

import 'package:integration_test/integration_test.dart';

/// XCTest enables native accessibility as it attaches to the test host. Wait
/// for that suite-owned setup before testWidgets records its semantics-handle
/// baseline. The normal leak assertion remains enabled inside every test.
Future<void> awaitNativeTestHost(
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  const run = String.fromEnvironment('WENKU_TEST_RUN_ID');
  if (run.isEmpty) return; // Normal flutter test/drive owns its own startup.
  final marker = File('${Directory.systemTemp.path}/wenku-host-$run');
  final ready = Completer<void>();
  final watcher = marker.parent.watch().listen(
    (_) async {
      if (await marker.exists() && !ready.isCompleted) ready.complete();
    },
    onError: (Object error, StackTrace stack) {
      if (!ready.isCompleted) ready.completeError(error, stack);
    },
  );
  try {
    if (await marker.exists() && !ready.isCompleted) ready.complete();
    await ready.future.timeout(const Duration(seconds: 240));
  } finally {
    await watcher.cancel();
  }
  // Process native semantics activation before the first tester's leak count.
  await binding.endOfFrame;
  await binding.endOfFrame;
}
