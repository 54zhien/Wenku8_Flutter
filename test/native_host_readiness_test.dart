import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/native_host.dart';

void main() {
  late Directory directory;
  late File marker;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wenku-native-host-');
    marker = File('${directory.path}/ready');
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'native readiness works when iOS filesystem watching is unavailable',
    () async {
      await marker.writeAsString('');
      await IOOverrides.runZoned(
        () => waitForNativeTestHostFile(marker),
        fsWatchIsSupported: () => false,
        fsWatch: (_, _, _) => throw UnsupportedError('iOS file watching'),
      );
    },
  );

  test('native readiness waits for the actual host marker', () async {
    final waiting = waitForNativeTestHostFile(marker);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await marker.writeAsString('');
    await waiting;
  });

  test(
    'missing native host marker fails within its readiness budget',
    () async {
      await expectLater(
        waitForNativeTestHostFile(
          marker,
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );
}
