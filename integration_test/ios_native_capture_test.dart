import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wenku8_flutter/ios_glass.dart';
import 'package:wenku8_flutter/ios_scroll_edge.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'support/native_host.dart';

Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  await awaitNativeTestHost(binding);
  final reports = <String, Object?>{};
  Future<void> saveReports() => File(
    '${Directory.systemTemp.path}/wenku-native-capture-probe.json',
  ).writeAsString(jsonEncode(reports), flush: true);
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
    var lastRevision = 0;
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
      final revision = result['captureRevision'] as int;
      expect(revision, greaterThan(lastRevision));
      lastRevision = revision;
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
    reports['capture'] = {
      'red_bgra': red,
      'blue_bgra': blue,
      'green_bgra': green,
      'native_work_counts': counts,
    };
    await saveReports();
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
                        child: IOSScrollEdge.legacy(
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
      reports['edge'] = {
        'top_contrast': top,
        'partial_contrast': partial,
        'translated_contrast': translated,
        'bottom_contrast': bottom,
        'native_work_counts': counts,
      };
      await saveReports();
    },
  );
  testWidgets('shared Gaussian plane preserves Metal native and foreground order', (
    tester,
  ) async {
    const diagnostics = MethodChannel('org.mewx.wenku8/glass_presentation');
    await diagnostics.invokeMethod<void>('probeStart');
    final state = ValueNotifier((color: const Color(0xFFFF0000), x: 0.0));
    addTearDown(state.dispose);
    MethodChannel? plane;
    MethodChannel? body;
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder(
          valueListenable: state,
          builder: (_, value, _) => ColoredBox(
            color: value.color,
            child: Transform.translate(
              offset: Offset(value.x, 0),
              child: Stack(
                children: [
                  const Positioned(
                    left: 10,
                    top: 200,
                    width: 48,
                    height: 180,
                    child: CustomPaint(painter: _ProbeForegroundPainter()),
                  ),
                  Positioned(
                    left: 80,
                    top: 200,
                    width: 128,
                    height: 180,
                    child: UiKitView(
                      viewType: 'org.mewx.wenku8/glass_controls',
                      creationParams: const {'kind': 'edgeProbe'},
                      creationParamsCodec: const StandardMessageCodec(),
                      onPlatformViewCreated: (id) => body = MethodChannel(
                        'org.mewx.wenku8/glass_controls/$id',
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 200,
                    height: 180,
                    child: IgnorePointer(
                      child: UiKitView(
                        viewType: 'org.mewx.wenku8/glass_controls',
                        creationParams: const {
                          'kind': 'gaussianEdge',
                          'sigma': 8.0,
                          'plateau': 60.0,
                          'fromBottom': false,
                        },
                        creationParamsCodec: const StandardMessageCodec(),
                        onPlatformViewCreated: (id) => plane = MethodChannel(
                          'org.mewx.wenku8/glass_controls/$id',
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 250,
                    top: 200,
                    width: 32,
                    height: 60,
                    child: CustomPaint(
                      key: ValueKey('shared-gaussian-foreground'),
                      painter: _ProbeForegroundPainter(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.widget<Navigator>(find.byType(Navigator)).clipBehavior,
      Clip.none,
    );
    Future<Map<String, dynamic>> sample() async {
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.pump();
      expect(plane, isNotNull);
      final pixels = await plane!.invokeMapMethod<String, dynamic>('snapshot');
      expect(pixels?['safeAncestors'], true);
      expect(
        pixels?['flutterHitThrough'],
        true,
        reason:
            'Actual UIKit hit testing must pass through the complete platform-view wrapper',
      );
      final black = List<int>.from(pixels!['foregroundBlackBGRA'] as List);
      final white = List<int>.from(pixels['foregroundWhiteBGRA'] as List);
      expect(black[0], lessThan(10));
      expect(
        white[0],
        greaterThan(245),
        reason: 'Flutter foreground above the Gaussian must remain crisp',
      );
      final bodyPixels = await body!.invokeMapMethod<String, dynamic>(
        'snapshot',
        const {'probe': true},
      );
      expect(bodyPixels?['nativeHitTarget'], true);
      return {...pixels, 'bodyRows': bodyPixels!['stripeContrastRows']};
    }

    final red = await sample();
    final redPixel = List<int>.from(red['backgroundPixelBGRA'] as List);
    expect(redPixel[2], greaterThan(245));
    expect(redPixel[0], lessThan(10));
    expect(redPixel[1], lessThan(10));
    int metalContrast(Map<String, dynamic> pixels) =>
        (List<int>.from(pixels['metalBlackBGRA'] as List)[0] -
                List<int>.from(pixels['metalWhiteBGRA'] as List)[0])
            .abs();
    expect(
      metalContrast(red),
      lessThan(40),
      reason:
          'A patterned Flutter backdrop must actually blur, not merely show through',
    );
    for (final key in ['metalBlackBGRA', 'metalWhiteBGRA']) {
      final pixel = List<int>.from(red[key] as List);
      expect(pixel[0], inInclusiveRange(60, 210));
      expect((pixel[0] - pixel[2]).abs(), lessThan(8));
      expect(pixel[3], 255);
    }
    final topRows = (red['bodyRows'] as List)
        .map((row) => List<int>.from(row as List))
        .toList();
    expect(topRows[3][0], lessThan(40));
    expect(topRows[32][0], greaterThan(225));
    state.value = (color: const Color(0xFF0000FF), x: 0.0);
    final blue = await sample();
    final bluePixel = List<int>.from(blue['backgroundPixelBGRA'] as List);
    expect(bluePixel[0], greaterThan(245));
    expect(bluePixel[2], lessThan(10));
    expect(bluePixel[1], lessThan(10));
    expect(metalContrast(blue), lessThan(40));
    state.value = (color: state.value.color, x: 20.0);
    await sample();
    state.value = (color: state.value.color, x: -20.0);
    await sample();
    state.value = (color: state.value.color, x: 0.0);
    await plane!.invokeMethod<void>('state', const {
      'sigma': 8.01,
      'plateau': 60.0,
      'fromBottom': true,
    });
    final bottom = await sample();
    final bottomRows = (bottom['bodyRows'] as List)
        .map((row) => List<int>.from(row as List))
        .toList();
    expect(bottomRows[0][0], greaterThan(225));
    expect(bottomRows[29][0], lessThan(40));
    expect(
      metalContrast(bottom),
      greaterThan(180),
      reason: 'The same feather must reveal the unblurred Flutter stripes',
    );
    final staticCounts = await diagnostics.invokeMapMethod<String, dynamic>(
      'probeEnd',
    );
    expect(staticCounts?['edge_profiles_registered'] ?? 0, 0);
    expect(
      staticCounts?['shared_plane_rebuilt'],
      2,
      reason:
          'Colour changes and horizontal movement must not rebuild the Gaussian/mask',
    );
    await diagnostics.invokeMethod<void>('probeStart');
    final context = tester.element(
      find.byKey(const ValueKey('shared-gaussian-foreground')),
    );
    final navigator = Navigator.of(context);
    MethodChannel? destination;
    final route = softRoute<void>(
      ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 200,
              height: 180,
              child: IgnorePointer(
                child: UiKitView(
                  viewType: 'org.mewx.wenku8/glass_controls',
                  creationParams: const {
                    'kind': 'gaussianEdge',
                    'sigma': 8.0,
                    'plateau': 60.0,
                    'fromBottom': false,
                  },
                  creationParamsCodec: const StandardMessageCodec(),
                  onPlatformViewCreated: (id) => destination = MethodChannel(
                    'org.mewx.wenku8/glass_controls/$id',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    navigator.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(route.animation!.value, inExclusiveRange(0, 1));
    await tester.pump();
    await tester.pump();
    expect(destination, isNotNull);
    expect(
      (await destination!.invokeMapMethod<String, dynamic>(
        'ancestors',
      ))?['safeAncestors'],
      true,
    );
    expect(
      (await plane!.invokeMapMethod<String, dynamic>(
        'ancestors',
      ))?['safeAncestors'],
      true,
    );
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(route.animation!.value, inExclusiveRange(0, 1));
    expect(
      (await plane!.invokeMapMethod<String, dynamic>(
        'ancestors',
      ))?['safeAncestors'],
      true,
    );
    await tester.pumpAndSettle();
    final restored = await sample();
    final restoredPixel = List<int>.from(
      restored['backgroundPixelBGRA'] as List,
    );
    expect(restoredPixel[0], greaterThan(245));
    expect(restoredPixel[2], lessThan(10));
    expect(restoredPixel[1], lessThan(10));
    expect(metalContrast(restored), greaterThan(180));
    final counts = await diagnostics.invokeMapMethod<String, dynamic>(
      'probeEnd',
    );
    expect(counts?['edge_profiles_registered'] ?? 0, 0);
    expect(
      counts?['shared_plane_rebuilt'],
      inInclusiveRange(1, 4),
      reason:
          'Route attachment may recreate an effect; route frames must not do so',
    );
    reports['shared_plane'] = {
      'red': red,
      'blue': blue,
      'bottom': bottom,
      'native_work_counts': counts,
      'static_work_counts': staticCounts,
    };
    await saveReports();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

class _ProbeForegroundPainter extends CustomPainter {
  const _ProbeForegroundPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    for (var x = 0.0; x < size.width; x += 4) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 2, size.height),
        Paint()..color = const Color(0xFF000000),
      );
    }
  }

  @override
  bool shouldRepaint(_ProbeForegroundPainter oldDelegate) => false;
}
