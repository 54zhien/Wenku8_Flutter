import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/ios_glass.dart';
import 'package:wenku8_flutter/ios_scroll_edge.dart';
import 'package:wenku8_flutter/native_effects.dart';
import 'package:wenku8_flutter/performance_preferences.dart';

class _Stripes extends CustomPainter {
  const _Stripes();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 4, size.height), Paint());
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}

Future<ByteData> _capture(
  WidgetTester tester, {
  bool bottom = false,
  bool white = false,
}) async {
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 232,
            height: 152,
            child: Stack(
              children: [
                Positioned.fill(
                  child: white
                      ? const ColoredBox(color: Colors.white)
                      : const CustomPaint(painter: _Stripes()),
                ),
                Positioned(
                  left: 16,
                  top: 16,
                  width: 200,
                  height: 120,
                  child: IOSScrollEdge(
                    blur: 8,
                    plateau: 60,
                    fromBottom: bottom,
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data;
  }))!;
}

int _contrast(ByteData pixels, int y) {
  var low = 255;
  var high = 0;
  for (var x = 40; x < 192; x++) {
    final value = pixels.getUint8((y * 232 + x) * 4);
    if (value < low) low = value;
    if (value > high) high = value;
  }
  return high - low;
}

void main() {
  testWidgets('scroll edge uses a feather compatible with its renderer', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 120,
            child: NativeBackdrop(
              effect: NativeEffect.progressive,
              blur: 8,
              plateau: 60,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).backgroundBlendMode ==
                BlendMode.dstIn,
      ),
      nativeIOSGlassEnabled ? findsNothing : findsOneWidget,
      reason:
          'UIKit receives the blur mutation but not this Flutter alpha ramp.',
    );
    if (nativeIOSGlassEnabled) {
      expect(
        find.byType(BackdropFilter),
        findsWidgets,
        reason: 'Keep actual blur rather than replacing it with a tint.',
      );
    }
    expect(find.byType(ShaderMask), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'radius feather preserves real blur, clear content and direction',
    (tester) async {
      final top = await _capture(tester);
      expect(_contrast(top, 24), lessThan(20));
      expect(_contrast(top, 116), greaterThan(_contrast(top, 24) + 30));
      expect(_contrast(top, 132), greaterThan(_contrast(top, 116) + 30));
      expect(_contrast(top, 144), 255);
      expect(_contrast(top, 8), 255);
      final bottom = await _capture(tester, bottom: true);
      // The same background is independent of y, so reversing the edge should
      // reverse its actual pixels, not just its widget configuration.
      for (var y = 20; y < 132; y++) {
        expect(
          (_contrast(top, y) - _contrast(bottom, 151 - y)).abs(),
          lessThanOrEqualTo(2),
          reason: 'Mirror mismatch at row $y',
        );
      }
    },
  );

  testWidgets('blur adds no tint or erased pixels to a white background', (
    tester,
  ) async {
    final pixels = await _capture(tester, white: true);
    for (var y = 0; y < 152; y++) {
      for (var x = 32; x < 200; x++) {
        final offset = (y * 232 + x) * 4;
        expect(pixels.getUint8(offset), 255);
        expect(pixels.getUint8(offset + 1), 255);
        expect(pixels.getUint8(offset + 2), 255);
        expect(pixels.getUint8(offset + 3), 255);
      }
    }
  });

  testWidgets('clips cover a resized edge once without subpixel gaps', (
    tester,
  ) async {
    for (final size in [
      const Size(393, 171.3),
      const Size(852, 115.7),
      const Size(200, .2),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 3),
            child: Center(
              child: SizedBox.fromSize(
                size: size,
                child: const IOSScrollEdge(
                  blur: 8,
                  plateau: 59.1,
                  fromBottom: false,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      final filters = find.byType(BackdropFilter);
      expect(
        filters.evaluate().length,
        inInclusiveRange(1, 9),
        reason: 'The feather cost stays bounded in landscape.',
      );
      final rects =
          filters
              .evaluate()
              .map((element) => tester.getRect(find.byWidget(element.widget)))
              .toList()
            ..sort((a, b) => a.top.compareTo(b.top));
      final edge = tester.getRect(find.byType(IOSScrollEdge));
      expect(rects.first.top, closeTo(edge.top, .0001));
      expect(rects.last.bottom, closeTo(edge.bottom, .0001));
      for (var index = 1; index < rects.length; index++) {
        expect(rects[index].top, closeTo(rects[index - 1].bottom, .0001));
        final local = (rects[index].top - edge.top) * 3;
        expect(local, closeTo(local.roundToDouble(), .0001));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'zero blur and disabled edge preference remove all edge filters',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        for (final disabled in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              home: PerformanceScope(
                preferences: PerformancePreferences(enabled: disabled),
                child: Center(
                  child: SizedBox(
                    width: 200,
                    height: 120,
                    child: NativeBackdrop(
                      effect: NativeEffect.progressive,
                      blur: disabled ? 8 : 0,
                      child: const Text('retained child'),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(find.byType(BackdropFilter), findsNothing);
          expect(find.byType(IOSScrollEdge), findsNothing);
          expect(find.text('retained child'), findsOneWidget);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
