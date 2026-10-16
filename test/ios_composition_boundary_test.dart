import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/ios_glass.dart';
import 'package:wenku8_flutter/ios_native_composition.dart';

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
    'a failed capture stays native without repeating the expensive readback',
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
      expect(captures, 1);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        captures,
        1,
        reason: 'Capture failure must not create an idle frame loop',
      );
    },
  );

  nativeTest(
    'viewport changes invalidate a crop even when the control size stays fixed',
    (tester) async {
      Widget page(double width) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 600)),
          child: Atmosphere(
            child: Center(child: control(const ValueKey('viewport-control'))),
          ),
        ),
      );
      await tester.pumpWidget(page(400));
      await tester.pumpAndSettle();
      expect(captures, 1);
      final size = tester.getSize(
        find.byKey(const ValueKey('viewport-control')),
      );
      await tester.pumpWidget(page(500));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('viewport-control'))),
        size,
      );
      expect(
        captures,
        2,
        reason:
            'A new viewport changes the native backdrop even when native configuration and control bounds stay the same',
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
    Navigator.of(
      tester.element(find.byType(IOSGlassControl)),
    ).push(softRoute<void>(const Atmosphere(child: SizedBox.expand())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(nativeLayers(tester), 0);
    expect(
      tester.layers.whereType<TextureLayer>().single.textureId,
      isNot(99999),
    );
    expect(creates, 1);
  });

  nativeTest(
    'a capture overlapping route motion cannot become a moving texture',
    (tester) async {
      late BuildContext home;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              home = context;
              return Atmosphere(
                child: Center(child: control(const ValueKey('race-source'))),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pending = Completer<Map<String, Object?>>();
      delayed = pending;
      Navigator.of(home).push(
        softRoute<void>(
          Atmosphere(
            child: Center(child: control(const ValueKey('race-target'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Navigator.of(
        tester.element(find.byKey(const ValueKey('race-target'))),
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(nativeLayers(tester), 1);
      pending.complete({'textureId': 99997, 'width': 46.0, 'height': 46.0});
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        nativeLayers(tester),
        1,
        reason:
            'A capture started before motion can contain a moving window crop',
      );
      expect(textureLayers(tester), 1);
      await tester.pumpAndSettle();
    },
  );

  nativeTest('a reparented control refreshes its previous scene crop', (
    tester,
  ) async {
    final key = GlobalKey();
    final pending = Completer<Map<String, Object?>>();
    delayed = pending;
    Widget page(bool right) => MaterialApp(
      home: IOSNativeComposition(
        key: ValueKey(right),
        child: Align(
          alignment: right ? Alignment.bottomRight : Alignment.topLeft,
          child: control(key),
        ),
      ),
    );
    await tester.pumpWidget(page(false));
    await tester.pump();
    expect(captures, 1);
    await tester.pumpWidget(page(true));
    pending.complete({'textureId': 99996, 'width': 46.0, 'height': 46.0});
    await tester.pumpAndSettle();
    expect(creates, 1);
    expect(
      captures,
      2,
      reason: 'The native control survives, but its old scene image must not',
    );
  });

  nativeTest(
    'passive glass with Flutter foreground never captures baked duplicate text',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Atmosphere(
            child: Center(
              child: IOSGlassSurface(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('菜单正文'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(nativeLayers(tester), 1);
      expect(captures, 0);
      expect(find.text('菜单正文'), findsOneWidget);
    },
  );

  nativeTest(
    'scrolling refreshes the next route snapshot once after settling',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Atmosphere(
            child: ListView(
              children: [
                const SizedBox(height: 200),
                Center(child: control(const ValueKey('scroll-control'))),
                const SizedBox(height: 1600),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(captures, 1);
      final pointer = await tester.startGesture(const Offset(300, 450));
      await pointer.moveBy(const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        captures,
        1,
        reason: 'No full-window readbacks during scroll frames',
      );
      expect(nativeLayers(tester), 1);
      await tester.pump(const Duration(milliseconds: 120));
      await pointer.up();
      await tester.pumpAndSettle();
      expect(
        captures,
        2,
        reason:
            'The next navigation must use the settled position and backdrop',
      );
      expect(creates, 1);
    },
  );

  nativeTest(
    'pending state refresh cannot replay the previous texture on return',
    (tester) async {
      late BuildContext home;
      final value = ValueNotifier(false);
      addTearDown(value.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              home = context;
              return Atmosphere(
                child: Center(child: control(const ValueKey('source-refresh'))),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Navigator.of(home).push(
        softRoute<void>(
          Atmosphere(
            child: Center(
              child: ValueListenableBuilder<bool>(
                valueListenable: value,
                builder: (_, current, _) => IOSGlassControl(
                  key: const ValueKey('pending-refresh'),
                  kind: 'switch',
                  width: 64,
                  height: 44,
                  configuration: {'value': current},
                  onAction: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final pending = Completer<Map<String, Object?>>();
      delayed = pending;
      value.value = true;
      await tester.pump();
      Navigator.of(
        tester.element(find.byKey(const ValueKey('pending-refresh'))),
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        nativeLayers(tester),
        1,
        reason:
            'Pending state must keep the live updated control, not an older raster',
      );
      expect(textureLayers(tester), 1);
      pending.complete({'textureId': 99998, 'width': 64.0, 'height': 44.0});
      await tester.pumpAndSettle();
    },
  );

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
      expect(nativeLayers(tester), 1);
      expect(textureLayers(tester), 0);
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
      expect(nativeLayers(tester), 2);
      expect(textureLayers(tester), greaterThanOrEqualTo(1));
      await tester.pumpAndSettle();
      await future;
    },
  );

  nativeTest(
    'stationary feathered controls keep their real native hit-test plane',
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
        3,
        reason:
            'Removing a native layer also removes its UIView and real UIKit touches',
      );
      expect(textureLayers(tester), 0);
      final native = find.descendant(
        of: find.byKey(const ValueKey('under-edge')),
        matching: find.byType(UiKitView),
      );
      expect(
        tester
            .hitTestOnBinding(tester.getCenter(native))
            .path
            .map((hit) => hit.target),
        contains(tester.renderObject(native)),
      );
      expect(
        find.byType(UiKitView),
        findsNWidgets(3),
        reason: 'All stationary UIKit controls must remain mounted and painted',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  nativeTest(
    'a cancelled interactive return restores the same live native controls',
    (tester) async {
      late BuildContext home;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              home = context;
              return Atmosphere(
                child: Center(child: control(const ValueKey('home'))),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Navigator.of(home).push(
        softRoute<void>(
          Atmosphere(
            child: Center(child: control(const ValueKey('cancel-destination'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final native = tester.element(find.byType(UiKitView).last);
      final settledCreates = creates;
      final settledCaptures = captures;
      final gesture = await tester.startGesture(const Offset(1, 300));
      await gesture.moveBy(const Offset(190, 0));
      await tester.pump();
      final route = ModalRoute.of(
        tester.element(find.byKey(const ValueKey('cancel-destination'))),
      )!;
      expect(route.animation!.value, inExclusiveRange(0, 1));
      expect(nativeLayers(tester), 0);
      expect(textureLayers(tester), 2);
      await gesture.moveBy(const Offset(-180, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(route.animation!.value, 1);
      expect(tester.element(find.byType(UiKitView).last), same(native));
      expect(nativeLayers(tester), 1);
      expect(creates, settledCreates);
      expect(captures, settledCaptures);
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
