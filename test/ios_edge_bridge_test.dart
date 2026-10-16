import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/ios_scroll_edge.dart';

void main() {
  if (!const bool.fromEnvironment('WENKU8_NATIVE_GLASS')) return;
  const channel = MethodChannel('org.mewx.wenku8/glass_presentation');
  final calls = <MethodCall>[];
  var accepted = true;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    accepted = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return accepted;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget scene({double height = 180, double plateau = 60, double x = 0}) =>
      MaterialApp(
        home: Stack(
          children: [
            Positioned(
              left: 0,
              top: 12,
              width: 300,
              height: height,
              child: Transform.translate(
                offset: Offset(x, 0),
                child: IOSScrollEdge.legacy(
                  blur: 8,
                  plateau: plateau,
                  fromBottom: false,
                  child: const SizedBox.expand(child: Text('foreground')),
                ),
              ),
            ),
          ],
        ),
      );

  testWidgets(
    'edge forwards full vertical feather geometry and removes it on disposal',
    (tester) async {
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle();
      final updates = calls.where((c) => c.method == 'edgeSet').toList();
      expect(updates, hasLength(1));
      final edge = updates.single.arguments as Map;
      expect(edge['y'], 12);
      expect(edge['height'], 180);
      expect(edge['plateau'], 60);
      expect(edge['sigma'], 8);
      expect(edge['fromBottom'], false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(calls.where((c) => c.method == 'edgeRemove').single.arguments, {
        'id': edge['id'],
      });
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'horizontal Cupertino movement does not send per-frame geometry messages',
    (tester) async {
      await tester.pumpWidget(scene());
      await tester.pumpAndSettle();
      for (var frame = 1; frame <= 30; frame++) {
        await tester.pumpWidget(scene(x: frame * 3));
        await tester.pump();
      }
      expect(calls.where((c) => c.method == 'edgeSet'), hasLength(1));
      await tester.pumpWidget(scene(height: 200, plateau: 70));
      await tester.pumpAndSettle();
      final updates = calls.where((c) => c.method == 'edgeSet').toList();
      expect(updates, hasLength(2));
      expect((updates.last.arguments as Map)['height'], 200);
      expect((updates.last.arguments as Map)['plateau'], 70);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  int gaussianCount(WidgetTester tester) => tester.layers
      .where((layer) => layer.engineLayer is ui.BackdropFilterEngineLayer)
      .length;

  testWidgets('a rejected profile never admits a rectangular native Gaussian', (
    tester,
  ) async {
    accepted = false;
    await tester.pumpWidget(scene());
    await tester.pumpAndSettle();
    expect(gaussianCount(tester), 0);
    expect(find.text('foreground'), findsOneWidget);
    accepted = true;
    await tester.pumpWidget(scene(height: 200));
    await tester.pumpAndSettle();
    expect(gaussianCount(tester), 1);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('stale layout acknowledgements cannot open the Gaussian gate', (
    tester,
  ) async {
    final replies = <Completer<bool>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          if (call.method != 'edgeSet') return Future.value(true);
          final reply = Completer<bool>();
          replies.add(reply);
          return reply.future;
        });
    await tester.pumpWidget(scene());
    await tester.pump();
    expect(gaussianCount(tester), 0);
    expect(find.text('foreground'), findsOneWidget);
    await tester.pumpWidget(scene(height: 200));
    await tester.pump();
    await tester.pumpWidget(scene());
    await tester.pump();
    expect(replies, hasLength(3));
    replies[0].complete(true);
    await tester.pump();
    expect(gaussianCount(tester), 0);
    replies[1].complete(true);
    await tester.pump();
    expect(gaussianCount(tester), 0);
    replies[2].complete(true);
    await tester.pumpAndSettle();
    expect(gaussianCount(tester), 1);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
