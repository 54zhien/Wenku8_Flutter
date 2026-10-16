import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wenku8_flutter/ios_glass.dart';
import 'package:wenku8_flutter/ios_scroll_edge.dart';

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

  testWidgets(
    'real platform controls retain Gaussian feather and native hit targets',
    (tester) async {
      const diagnostics = MethodChannel('org.mewx.wenku8/glass_presentation');
      await diagnostics.invokeMethod<void>('probeStart');
      final layout = ValueNotifier((
        y: 200.0,
        height: 180.0,
        x: 0.0,
        bottom: false,
      ));
      addTearDown(layout.dispose);
      MethodChannel? control;
      await tester.pumpWidget(
        MaterialApp(
          home: ColoredBox(
            color: Colors.white,
            child: ValueListenableBuilder(
              valueListenable: layout,
              builder: (_, value, _) => Transform.translate(
                offset: Offset(value.x, 0),
                child: Stack(
                  children: [
                    Positioned(
                      left: 80,
                      top: value.y,
                      width: 128,
                      height: value.height,
                      child: UiKitView(
                        viewType: 'org.mewx.wenku8/glass_controls',
                        creationParams: const {'kind': 'edgeProbe'},
                        creationParamsCodec: const StandardMessageCodec(),
                        onPlatformViewCreated: (id) {
                          control = MethodChannel(
                            'org.mewx.wenku8/glass_controls/$id',
                          );
                        },
                      ),
                    ),
                    Positioned(
                      left: 80,
                      top: 200,
                      width: 128,
                      height: 180,
                      child: IgnorePointer(
                        child: IOSScrollEdge(
                          blur: 8,
                          plateau: 60,
                          fromBottom: value.bottom,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Future<List<int>> sample() async {
        await tester.pumpAndSettle();
        await tester.pump();
        await tester.pump();
        final status = await diagnostics.invokeMapMethod<String, dynamic>(
          'probeEdgeStatus',
        );
        expect(status?['compatible'], true);
        expect(status?['maskedFilters'], greaterThan(0));
        expect(control, isNotNull);
        final result = await control!.invokeMapMethod<String, dynamic>(
          'snapshot',
          const {'probe': true},
        );
        expect(result, isNotNull);
        expect(
          result!['nativeHitTarget'],
          true,
          reason:
              'The actual UIWindow hit path must reach the native control under the edge',
        );
        final rows = (result['stripeContrastRows'] as List)
            .map((row) => List<int>.from(row as List))
            .toList();
        expect(rows, hasLength(33));
        for (final row in rows) {
          expect(row[1], lessThanOrEqualTo(2));
          expect(row[2], 255);
        }
        return rows.map((row) => row[0]).toList();
      }

      final top = await sample();
      expect(top[3], lessThan(40));
      expect(top[32], greaterThan(225));
      layout.value = (y: 260.0, height: 80.0, x: 0.0, bottom: false);
      final partial = await sample();
      expect(partial[1], lessThan(40));
      expect(partial[31], greaterThan(150));
      layout.value = (y: 260.0, height: 80.0, x: 20.0, bottom: false);
      final translated = await sample();
      expect(translated[1], lessThan(40));
      expect(translated[31], greaterThan(150));
      layout.value = (y: 200.0, height: 180.0, x: 0.0, bottom: true);
      final bottom = await sample();
      expect(bottom[0], greaterThan(225));
      expect(bottom[29], lessThan(40));
      final counts = await diagnostics.invokeMapMethod<String, dynamic>(
        'probeEnd',
      );
      expect(
        counts?['edge_profiles_registered'],
        2,
        reason:
            'Scrolling and horizontal route movement must not send per-frame edge metadata',
      );
      // ignore: avoid_print
      print(
        'WENKU_EDGE_PROBE_JSON=${jsonEncode({'top_contrast': top, 'partial_contrast': partial, 'translated_contrast': translated, 'bottom_contrast': bottom, 'native_work_counts': counts})}',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final removed = await diagnostics.invokeMapMethod<String, dynamic>(
        'probeEdgeStatus',
      );
      expect(removed?['maskedFilters'], 0);
    },
  );
}
