import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wenku8_flutter/ios_glass.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('native glass texture tracks changing Flutter Metal content', (
    tester,
  ) async {
    expect(nativeIOSGlassEnabled, isTrue);
    final color = ValueNotifier(const Color(0xFFFF0000));
    addTearDown(color.dispose);
    MethodChannel? control;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: ValueListenableBuilder<Color>(
                valueListenable: color,
                builder: (_, value, _) => ColoredBox(color: value),
              ),
            ),
            Positioned(
              left: 80,
              top: 200,
              width: 120,
              height: 80,
              child: UiKitView(
                viewType: 'org.mewx.wenku8/glass_controls',
                creationParams: const {
                  'kind': 'surface',
                  'radius': 0.0,
                  'dark': false,
                },
                creationParamsCodec: const StandardMessageCodec(),
                onPlatformViewCreated: (id) {
                  control = MethodChannel('org.mewx.wenku8/glass_controls/$id');
                },
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    const diagnostics = MethodChannel('org.mewx.wenku8/glass_presentation');
    await diagnostics.invokeMethod<void>('probeStart');
    Future<List<int>> sample() async {
      // Submit two actual frames so the Flutter colour and native backdrop
      // have committed, without a wall-clock sleep or a screenshot retry loop.
      await tester.pump();
      await tester.pump();
      expect(control, isNotNull);
      final result = await control!.invokeMapMethod<String, dynamic>(
        'snapshot',
        const {'probe': true},
      );
      expect(result, isNotNull);
      expect(result!['width'], 120);
      expect(result['height'], 80);
      final pixel = List<int>.from(result['centerPixelBGRA'] as List);
      expect(pixel, hasLength(4));
      expect(pixel[3], 255);
      return pixel;
    }

    final red = await sample();
    expect(red[2], greaterThan(red[0] + 30));
    color.value = const Color(0xFF0000FF);
    await tester.pump();
    final blue = await sample();
    expect(blue[0], greaterThan(blue[2] + 30));
    color.value = const Color(0xFF00FF00);
    await tester.pump();
    final green = await sample();
    expect(green[1], greaterThan(green[0] + 30));
    expect(green[1], greaterThan(green[2] + 30));
    final counts = await diagnostics.invokeMapMethod<String, dynamic>(
      'probeEnd',
    );
    expect(counts?['snapshots_captured'], 3);
    // ignore: avoid_print
    print(
      'WENKU_CAPTURE_PROBE_JSON=${jsonEncode({'red_bgra': red, 'blue_bgra': blue, 'green_bgra': green, 'native_work_counts': counts})}',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
