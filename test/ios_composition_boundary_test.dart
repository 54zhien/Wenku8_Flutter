import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/ios_glass.dart';

void main() {
  if (!const bool.fromEnvironment('WENKU8_NATIVE_GLASS')) return;
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;
  final channels = <MethodChannel>[];
  var captures = 0;
  var creates = 0;
  var missing = false;
  Completer<Map<String, Object?>>? delayed;
  setUp(() {
    captures = creates = 0;
    missing = false;
    delayed = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        creates++;
        final id = (call.arguments as Map)['id'] as int;
        final channel = MethodChannel('org.mewx.wenku8/glass_controls/$id');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'snapshot') {
            captures++;
            if (missing) return null;
            final pending = delayed;
            delayed = null;
            if (pending != null) return pending.future;
            return {'textureId': id + 100, 'width': 46.0, 'height': 46.0};
          }
          return null;
        });
      }
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    channels.clear();
  });
  int nativeLayers(WidgetTester tester) =>
      tester.layers.whereType<PlatformViewLayer>().length;
  int textureLayers(WidgetTester tester) =>
      tester.layers.whereType<TextureLayer>().length;
  void nativeTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Widget control(Key key) => GlassIconButton(
    key: key,
    icon: CupertinoIcons.book,
    label: 'book',
    onPressed: () {},
  );

  nativeTest(
    'missing snapshots keep visible native controls and bound retries',
    (tester) async {
      missing = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Atmosphere(
            child: Center(child: control(const ValueKey('cold'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(nativeLayers(tester), 1);
      expect(textureLayers(tester), 0);
      expect(captures, 3);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        captures,
        3,
        reason: 'Capture failure must not create an idle frame loop',
      );
    },
  );

  nativeTest('a stale asynchronous capture cannot replace the current state', (
    tester,
  ) async {
    final old = Completer<Map<String, Object?>>();
    delayed = old;
    Widget page(bool value) => MaterialApp(
      home: Atmosphere(
        child: Stack(
          children: [
            Positioned(
              top: 32,
              left: 20,
              child: IOSGlassControl(
                kind: 'switch',
                width: 64,
                height: 44,
                configuration: {'value': value},
                onAction: (_) {},
              ),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FrostedHeader(child: SizedBox()),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(page(false));
    await tester.pump();
    expect(nativeLayers(tester), 1);
    await tester.pumpWidget(page(true));
    old.complete({'textureId': 99999, 'width': 64.0, 'height': 44.0});
    await tester.pumpAndSettle();
    expect(nativeLayers(tester), 0);
    expect(
      tester.layers.whereType<TextureLayer>().single.textureId,
      isNot(99999),
    );
    expect(creates, 1);
  });

  nativeTest(
    'an active pointer keeps native ownership while crossing a feather',
    (tester) async {
      final y = ValueNotifier<double>(220);
      addTearDown(y.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Atmosphere(
            child: Stack(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: y,
                  builder: (_, value, _) => Positioned(
                    top: value,
                    left: 20,
                    child: control(const ValueKey('held')),
                  ),
                ),
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FrostedHeader(child: SizedBox()),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('held'))),
      );
      await tester.pump();
      y.value = 32;
      await tester.pump();
      expect(nativeLayers(tester), 1);
      expect(textureLayers(tester), 0);
      await pointer.cancel();
      await tester.pumpAndSettle();
      expect(nativeLayers(tester), 0);
      expect(textureLayers(tester), 1);
    },
  );

  nativeTest(
    'a sheet keeps its native entrance material and uses textures on return',
    (tester) async {
      late BuildContext home;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              home = context;
              return Atmosphere(
                child: Center(child: control(const ValueKey('source'))),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final future = showJellySheet<void>(
        context: home,
        builder: (_) => SizedBox(
          height: 120,
          child: Center(child: control(const ValueKey('sheet-control'))),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        nativeLayers(tester),
        3,
        reason:
            'Cold overlay material retains its native morph until a capture exists',
      );
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byKey(const ValueKey('sheet-control'))),
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(nativeLayers(tester), 1);
      expect(textureLayers(tester), greaterThanOrEqualTo(1));
      await tester.pumpAndSettle();
      await future;
    },
  );

  nativeTest(
    'feathered content uses a texture while header and clear content stay native',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Atmosphere(
            child: Stack(
              children: [
                Positioned(
                  top: 32,
                  left: 20,
                  child: control(const ValueKey('under-edge')),
                ),
                Positioned(
                  top: 220,
                  left: 20,
                  child: control(const ValueKey('clear')),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: FrostedHeader(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: control(const ValueKey('header')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        nativeLayers(tester),
        2,
        reason:
            'The UIKit content below the feather must not receive an unmasked native blur',
      );
      expect(textureLayers(tester), 1);
      expect(
        find.byType(UiKitView),
        findsNWidgets(3),
        reason: 'Rasterization must keep native state mounted',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  nativeTest(
    'both moving pages use cached textures on push and pop without recapture',
    (tester) async {
      late BuildContext home;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              home = context;
              return Atmosphere(
                child: Center(child: control(const ValueKey('source'))),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final source = tester.element(find.byKey(const ValueKey('source')));
      expect(nativeLayers(tester), 1);
      Navigator.of(home).push(
        softRoute<void>(
          Atmosphere(
            child: Center(child: control(const ValueKey('destination'))),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        nativeLayers(tester),
        0,
        reason: 'The outgoing route also moves on push',
      );
      expect(textureLayers(tester), greaterThanOrEqualTo(1));
      await tester.pumpAndSettle();
      expect(nativeLayers(tester), 1);
      final settledCaptures = captures;
      final settledCreates = creates;
      Navigator.of(
        tester.element(find.byKey(const ValueKey('destination'))),
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        nativeLayers(tester),
        0,
        reason:
            'Return must not leave either UIKit page live in the moving composition',
      );
      expect(textureLayers(tester), 2);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        captures,
        settledCaptures,
        reason: 'No capture/readback loop during motion',
      );
      expect(creates, settledCreates);
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byKey(const ValueKey('source'))),
        same(source),
      );
      expect(nativeLayers(tester), 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
